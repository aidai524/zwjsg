<?php

namespace App\Services;

use App\Models\DailyRecord;
use App\Models\User;
use App\Models\UserBreed;
use Carbon\CarbonImmutable;

class DailyRecordService
{
    public function __construct(private DogMeter $meter) {}

    /**
     * 写入（或覆盖）某天的记录，返回记录和这次新解锁的犬种 key。
     * 阶段一律由服务端按狗度重新计算，不信任客户端传的阶段。
     *
     * @param  array{dog_percent:int, minutes_used:int, breed_key?:string|null}  $data
     * @return array{0: DailyRecord, 1: list<string>}
     */
    public function upsert(User $user, string $date, array $data): array
    {
        $percent = (int) $data['dog_percent'];

        $record = DailyRecord::updateOrCreate(
            ['user_id' => $user->id, 'date' => $date],
            [
                'dog_percent' => $percent,
                'stage' => $this->meter->stageFor($percent),
                'minutes_used' => (int) $data['minutes_used'],
                'breed_key' => $data['breed_key'] ?? null,
            ],
        );

        $unlocked = [];

        if ($record->breed_key && $this->unlock($user, $record->breed_key, $date)) {
            $unlocked[] = $record->breed_key;
        }

        if ($this->hasHumanStreak($user, $date) && $this->unlock($user, 'wolf', $date)) {
            $unlocked[] = 'wolf';
        }

        return [$record, $unlocked];
    }

    /**
     * 节日限定犬种能不能记在 $date 这天：那天在这个节日里，而且变狗了（狗度到了“做人”线）。
     * 不是限定犬种的一律可以（App 按刷法判的，服务端拿不到明细，照收）
     */
    public function festivalBreedAllowed(?string $breedKey, string $date, int $dogPercent): bool
    {
        $festival = $breedKey ? config("dog.festival_breeds.{$breedKey}") : null;
        if (! $festival) {
            return true;
        }
        if ($this->meter->isHuman($dogPercent)) {
            return false;
        }
        if (isset($festival['every_year'])) {
            return substr($date, 5) === $festival['every_year'];
        }
        foreach ($festival['windows'] ?? [] as [$start, $end]) {
            if ($date >= $start && $date <= $end) {
                return true;
            }
        }

        return false;
    }

    private function unlock(User $user, string $breedKey, string $date): bool
    {
        $breed = UserBreed::firstOrCreate(
            ['user_id' => $user->id, 'breed_key' => $breedKey],
            ['first_unlocked_on' => $date],
        );

        return $breed->wasRecentlyCreated;
    }

    /** 截止到 $date（含）连续 N 天都是“做人” */
    private function hasHumanStreak(User $user, string $date): bool
    {
        $days = (int) config('dog.legend_streak_days');
        $end = CarbonImmutable::parse($date);
        $start = $end->subDays($days - 1);

        $records = $user->dailyRecords()
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->get(['date', 'dog_percent']);

        if ($records->count() < $days) {
            return false;
        }

        return $records->every(fn (DailyRecord $r) => $this->meter->isHuman($r->dog_percent));
    }
}
