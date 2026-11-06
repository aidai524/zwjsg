<?php

namespace App\Services;

use App\Models\CareGroup;
use App\Models\Mute;
use App\Models\Reminder;
use App\Models\User;
use App\Services\Push\PushGateway;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * 关心群的提醒规则（防骚扰是第一位的）：
 * - 只能选固定的关心话，不能自己打字；
 * - 同一人每天最多提醒同一人 2 次（按被提醒者本地日期）；
 * - 30 分钟内同一话题的提醒合并成一条推送（“妈妈、爸爸提醒你…”）；
 * - 被提醒者本地 22:00–07:00 发的，延迟到 07:00 送达（预警话题除外）；
 * - 被静音时照常显示“已送达”，但不推送、不进收件箱，发送者无感知；
 * - 记录 30 天后删除。
 */
class CareService
{
    public function __construct(private PushGateway $push) {}

    /** phrase_key → [topic, text] */
    public static function phrase(string $key): ?array
    {
        foreach (config('weather.care.phrases') as $topic => $phrases) {
            if (isset($phrases[$key])) {
                return ['topic' => $topic, 'text' => $phrases[$key]];
            }
        }

        return null;
    }

    /** 某个话题可选的关心话 */
    public static function phrasesFor(?string $topic): array
    {
        $topic ??= 'nice';
        $list = config("weather.care.phrases.$topic", []);

        return array_map(fn ($k, $t) => ['key' => $k, 'text' => $t, 'topic' => $topic], array_keys($list), $list);
    }

    public function remainingToday(User $sender, User $recipient): int
    {
        $used = Reminder::where('sender_id', $sender->id)
            ->where('recipient_id', $recipient->id)
            ->where('recipient_date', $recipient->localToday())
            ->count();

        return max(0, config('weather.care.daily_cap_per_pair') - $used);
    }

    public function send(User $sender, CareGroup $group, User $recipient, string $phraseKey): Reminder
    {
        if ($sender->is($recipient)) {
            throw new HttpException(422, '不能提醒自己');
        }
        if (! $group->hasMember($sender) || ! $group->hasMember($recipient)) {
            throw new HttpException(403, '不在同一个关心群');
        }

        $phrase = self::phrase($phraseKey) ?? throw new HttpException(422, '没有这句关心话');
        $nowUtc = CarbonImmutable::now();
        $mergeSince = $nowUtc->subMinutes(config('weather.care.merge_minutes'));

        return DB::transaction(function () use ($sender, $group, $recipient, $phrase, $phraseKey, $nowUtc, $mergeSince) {
            // 同一个人 30 分钟内重复点同一话题：直接返回上一条，不计次数
            $dup = Reminder::where('sender_id', $sender->id)
                ->where('recipient_id', $recipient->id)
                ->where('topic', $phrase['topic'])
                ->where('created_at', '>=', $mergeSince)
                ->latest('id')->first();
            if ($dup) {
                return $dup;
            }

            if ($this->remainingToday($sender, $recipient) <= 0) {
                throw new HttpException(429, '今天已经提醒过 '.config('weather.care.daily_cap_per_pair').' 次了，TA 会照顾好自己的');
            }

            $suppressed = Mute::isMuted($recipient->id, $sender->id, $group->id);

            // 其他人 30 分钟内提醒过同一话题，且还没送达：合并到那一条
            $primary = $suppressed ? null : Reminder::where('recipient_id', $recipient->id)
                ->where('topic', $phrase['topic'])
                ->whereNull('merged_into_id')
                ->where('suppressed', false)
                ->whereNull('delivered_at')
                ->where('created_at', '>=', $mergeSince)
                ->oldest('id')->first();

            $reminder = Reminder::create([
                'care_group_id' => $group->id,
                'sender_id' => $sender->id,
                'recipient_id' => $recipient->id,
                'topic' => $phrase['topic'],
                'phrase_key' => $phraseKey,
                'text' => $phrase['text'],
                'recipient_date' => $recipient->localToday(),
                'deliver_at' => $primary?->deliver_at ?? $this->deliverAt($recipient, $phrase['topic'], $nowUtc),
                'merged_into_id' => $primary?->id,
                'suppressed' => $suppressed,
            ]);

            return $reminder;
        });
    }

    /** 被提醒者本地 22:00–07:00 → 延迟到本地 07:00；预警不延迟 */
    public function deliverAt(User $recipient, string $topic, CarbonImmutable $nowUtc): CarbonImmutable
    {
        if ($topic === 'alert') {
            return $nowUtc;
        }

        $start = config('weather.care.quiet_start');
        $end = config('weather.care.quiet_end');
        $local = $nowUtc->setTimezone($recipient->timezone);

        if ($local->hour >= $start) {
            return $local->addDay()->setTime($end, 0)->utc();
        }
        if ($local->hour < $end) {
            return $local->setTime($end, 0)->utc();
        }

        return $nowUtc;
    }

    /** 把到点的提醒推出去（定时任务每分钟跑一次；发送时也会立刻跑一次） */
    public function deliverDue(): int
    {
        $count = 0;

        Reminder::whereNull('delivered_at')
            ->whereNull('merged_into_id')
            ->where('deliver_at', '<=', now())
            ->with(['recipient', 'sender'])
            ->orderBy('id')
            ->chunkById(100, function (Collection $batch) use (&$count) {
                foreach ($batch as $primary) {
                    $merged = Reminder::where('merged_into_id', $primary->id)->with('sender')->get();
                    $all = collect([$primary])->concat($merged);

                    if (! $primary->suppressed && $primary->recipient) {
                        $names = $all->map(fn (Reminder $r) => $r->sender?->displayName())->filter()->unique()->implode('、');
                        $this->push->send($primary->recipient, "{$names}提醒你", $primary->text, [
                            'type' => 'care_reminder',
                            'reminder_id' => $primary->id,
                        ]);
                        $count++;
                    }

                    Reminder::whereIn('id', $all->pluck('id'))->update(['delivered_at' => now()]);
                }
            });

        return $count;
    }

    /** 被提醒者点“收到 ♥”：合并的几条一起回执，告诉每个发送者 */
    public function ack(User $recipient, Reminder $reminder): void
    {
        if ($reminder->recipient_id !== $recipient->id || $reminder->suppressed) {
            throw new HttpException(404, '提醒不存在');
        }

        $primaryId = $reminder->merged_into_id ?? $reminder->id;
        $all = Reminder::where('id', $primaryId)->orWhere('merged_into_id', $primaryId)->with('sender')->get()
            ->where('recipient_id', $recipient->id);

        foreach ($all as $r) {
            if ($r->acked_at) {
                continue;
            }
            $r->update(['acked_at' => now()]);
            if ($r->sender) {
                $this->push->send($r->sender, "{$recipient->displayName()} 收到了 ♥", '', [
                    'type' => 'care_ack',
                    'reminder_id' => $r->id,
                ]);
            }
        }
    }

    /** 发送者看到的状态：静音时也显示“已送达”，不暴露静音 */
    public static function senderStatus(Reminder $r): string
    {
        if ($r->acked_at && ! $r->suppressed) {
            return 'acked';
        }
        if ($r->deliver_at->isFuture()) {
            return 'scheduled';
        }

        return 'delivered';
    }

    public function prune(): int
    {
        return Reminder::where('created_at', '<', now()->subDays(config('weather.care.retention_days')))->delete();
    }
}
