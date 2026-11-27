<?php

namespace App\Services;

use App\Models\DailyRecord;
use App\Models\DogGroup;
use App\Models\Nudge;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * 群组：成员今天的状态、昨天的狗王、一起做人连续天数、汪一下的次数、退群。
 * 群里只给狗度、阶段和犬种，不给分钟数，也没有任何 App 明细（服务端本来就没有）。
 */
class GroupService
{
    public function __construct(private DogMeter $meter) {}

    /** App 要的群组数据。[$me] 是看的人：今天按每个成员自己的本地日期，昨天按看的人的本地日期 */
    public function payload(DogGroup $group, User $me): array
    {
        $members = $group->members()->orderBy('dog_group_members.id')->get();
        $yesterday = CarbonImmutable::parse($me->localToday())->subDay();

        $rows = $members->map(function (User $m) use ($me, $group) {
            $isMe = $m->is($me);
            $hidden = (bool) $m->pivot->hide_status;
            // 隐藏了的：别人看不到，自己看得到
            $record = $hidden && ! $isMe ? null : $this->today($m);

            return [
                'id' => $m->id,
                'nickname' => $m->displayName(),
                ...$m->sharedAvatar(),
                'is_me' => $isMe,
                'is_owner' => $group->owner_id === $m->id,
                'hidden' => $hidden,
                'today' => $record ? [
                    'dog_percent' => $record->dog_percent,
                    'stage' => $record->stage,
                    'breed_key' => $record->breed_key,
                ] : null,
                'nudges_left' => $isMe ? null : $this->nudgesLeft($me, $m),
            ];
        });

        // 今天最狗的排前面；没数据、隐藏的放后面（PHP 8 的排序是稳定的，同分按进群先后）
        $sorted = $rows->sortByDesc(fn (array $r) => $r['today']['dog_percent'] ?? -1)->values();
        $mine = $members->firstWhere('id', $me->id)?->pivot;
        $streak = $this->teamStreak($group, $members, $yesterday);
        if ($streak > $group->best_streak) {
            $group->update(['best_streak' => $streak]);
        }

        return [
            'id' => $group->id,
            'name' => $group->name,
            'invite_code' => $group->invite_code,
            'is_owner' => $group->owner_id === $me->id,
            'max_members' => config('dog.groups.max_members'),
            'me' => [
                'hide_status' => (bool) ($mine?->hide_status ?? false),
                'mute_nudges' => (bool) ($mine?->mute_nudges ?? false),
            ],
            'members' => $sorted->all(),
            'king_yesterday' => $this->kingOf($group, $yesterday->toDateString()),
            'team' => [
                'streak' => $streak,
                'best' => max($streak, $group->best_streak),
                'goal' => config('dog.groups.team_streak_goal'),
                'today' => [
                    'human' => $rows->filter(fn ($r) => $r['today'] && $this->meter->isHuman($r['today']['dog_percent']))->count(),
                    'dog' => $rows->filter(fn ($r) => $r['today'] && ! $this->meter->isHuman($r['today']['dog_percent']))->count(),
                    'unknown' => $rows->filter(fn ($r) => ! $r['today'])->count(),
                ],
            ],
        ];
    }

    /** 成员自己本地的今天的记录 */
    public function today(User $m): ?DailyRecord
    {
        return $m->dailyRecords()->where('date', $m->localToday())->first();
    }

    /**
     * 某天的狗王：那天狗度最高的人。隐藏狗度的不参加；那天大家都还是人就没有狗王。
     *
     * @return array<string, mixed>|null
     */
    public function kingOf(DogGroup $group, string $date): ?array
    {
        $visible = $group->members()->wherePivot('hide_status', false)->pluck('users.id');
        $record = DailyRecord::with('user')
            ->whereIn('user_id', $visible)
            ->where('date', $date)
            ->where('dog_percent', '>=', config('dog.human_below'))
            ->orderByDesc('dog_percent')
            ->orderBy('updated_at')
            ->first();
        if (! $record) {
            return null;
        }

        return [
            'user_id' => $record->user->id,
            'nickname' => $record->user->displayName(),
            ...$record->user->sharedAvatar(),
            'date' => $date,
            'dog_percent' => $record->dog_percent,
            'stage' => $record->stage,
            'breed_key' => $record->breed_key,
        ];
    }

    /**
     * 一起做人：从昨天往前数，连续几天“全群都是人”。
     * 只算共享狗度的成员（最近 30 天上报过记录的）：用 iPhone 的不上报使用数据，不能因为他们让大家永远凑不齐。
     * 那天还没进群的不算；那天没有记录的算断了。
     *
     * @param  Collection<int, User>  $members  带着 pivot（进群时间）
     */
    public function teamStreak(DogGroup $group, Collection $members, CarbonImmutable $yesterday): int
    {
        $lookback = (int) config('dog.groups.team_streak_lookback');
        $since = $yesterday->subDays((int) config('dog.groups.sharer_window_days') - 1)->toDateString();
        $sharerIds = DailyRecord::whereIn('user_id', $members->pluck('id'))
            ->where('date', '>=', $since)
            ->distinct()
            ->pluck('user_id');
        $sharers = $members->whereIn('id', $sharerIds);
        if ($sharers->isEmpty()) {
            return 0;
        }

        $byDay = DailyRecord::whereIn('user_id', $sharerIds)
            ->whereBetween('date', [$yesterday->subDays($lookback - 1)->toDateString(), $yesterday->toDateString()])
            ->get(['user_id', 'date', 'dog_percent'])
            ->groupBy(fn (DailyRecord $r) => $r->date->toDateString());

        $streak = 0;
        for ($day = $yesterday; $streak < $lookback; $day = $day->subDay()) {
            $date = $day->toDateString();
            $joined = $sharers->filter(fn (User $m) => $m->pivot->created_at->toDateString() <= $date);
            if ($joined->isEmpty()) {
                break;
            }
            $records = $byDay->get($date, collect())->keyBy('user_id');
            foreach ($joined as $m) {
                $r = $records->get($m->id);
                if (! $r || ! $this->meter->isHuman($r->dog_percent)) {
                    break 2;
                }
            }
            $streak++;
        }

        return $streak;
    }

    /** 今天还能汪 TA 几次（按发的人的本地日期算“今天”） */
    public function nudgesLeft(User $sender, User $recipient): int
    {
        $start = now($sender->timezone)->startOfDay()->utc();
        $sent = Nudge::where('sender_id', $sender->id)
            ->where('recipient_id', $recipient->id)
            ->where('created_at', '>=', $start)
            ->count();

        return max(0, (int) config('dog.groups.nudges_per_pair_per_day') - $sent);
    }

    /** 退群；群主退出时转给最早进群的人，没人了就解散 */
    public function leave(DogGroup $group, User $user): void
    {
        DB::transaction(function () use ($group, $user) {
            $group->members()->detach($user->id);
            $next = $group->members()->orderBy('dog_group_members.id')->first();

            if (! $next) {
                $group->delete();
            } elseif ($group->owner_id === $user->id) {
                $group->update(['owner_id' => $next->id]);
            }
        });
    }
}
