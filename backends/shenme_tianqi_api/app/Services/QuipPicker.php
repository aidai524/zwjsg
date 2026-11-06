<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;

/**
 * 从人工文案库挑一句吐槽。同一天同一触发条件固定一句（下拉刷新不乱跳），
 * 同一用户（或同一设备）7 天内尽量不重复。
 */
class QuipPicker
{
    public function pick(?string $trigger, int $level, string $who): ?string
    {
        if ($trigger === null) {
            return null;
        }

        $lines = config("quips.$trigger.$level") ?? config("quips.$trigger.1") ?? [];
        if ($lines === []) {
            return null;
        }

        $todayKey = 'quips:today:'.md5($who).":$trigger:$level:".now('Asia/Shanghai')->toDateString();
        if ($picked = Cache::get($todayKey)) {
            return $picked;
        }

        $key = 'quips:seen:'.md5($who);
        $seen = Cache::get($key, []);
        $fresh = array_values(array_diff($lines, $seen));
        $line = $fresh !== [] ? $fresh[array_rand($fresh)] : $lines[array_rand($lines)];

        // 只保留最近 50 条，7 天过期
        $seen = array_slice(array_values(array_unique([...$seen, $line])), -50);
        Cache::put($key, $seen, now()->addDays(config('weather.quip_no_repeat_days')));
        Cache::put($todayKey, $line, now('Asia/Shanghai')->endOfDay());

        return $line;
    }
}
