<?php

namespace App\Services;

/**
 * 狗度规则。App 端有一份相同的实现（app/lib/core/dog_meter.dart），改动时两边一起改。
 */
class DogMeter
{
    /** 狗度百分比 → 阶段 0–5 */
    public function stageFor(int $percent): int
    {
        $stage = 0;
        foreach (config('dog.stage_thresholds') as $i => $threshold) {
            if ($percent >= $threshold) {
                $stage = $i + 1;
            }
        }

        return $stage;
    }

    public function isHuman(int $percent): bool
    {
        return $percent < config('dog.human_below');
    }

    /** 由使用分钟数和目标分钟数算狗度（四舍五入到整数） */
    public function percentFor(int $minutesUsed, int $goalMinutes): int
    {
        if ($goalMinutes <= 0) {
            return 0;
        }

        return (int) round($minutesUsed / $goalMinutes * 100);
    }
}
