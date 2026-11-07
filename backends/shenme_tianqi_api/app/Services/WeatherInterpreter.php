<?php

namespace App\Services;

use Carbon\CarbonImmutable;

/**
 * 把天气快照翻译成玩法结论：形象状态、穿衣档、严肃模式、四张决策卡、吐槽触发、关心话题。
 * 纯函数，不访问网络和数据库，方便测试。规则阈值都在 config/weather.php。
 */
class WeatherInterpreter
{
    public function interpret(array $snap, ?string $adm = null): array
    {
        $now = $snap['now'];
        $daily = array_values($snap['daily']);
        [$targetIdx, $hours] = $this->targetDay($snap['hourly'], $daily);
        $target = $daily[$targetIdx] ?? null;

        $warnings = $snap['warnings'] ?? [];
        $bannerColors = config('weather.banner_colors');
        $seriousWarnings = array_values(array_filter($warnings, fn ($w) => ! in_array($w['color'], $bannerColors, true)));
        $serious = $seriousWarnings !== [];

        $outfit = $this->outfit($now['feels_like']);
        $cond = $serious ? 'serious' : $this->cond($now, $adm, $target['date'] ?? null);

        $decisions = [
            'umbrella' => $this->umbrella($hours, $target),
            'long_johns' => $this->longJohns($now, $target, $targetIdx === 0),
            'car_wash' => $this->carWash($daily, $targetIdx),
            'laundry' => $this->laundry($hours, $target),
        ];

        return [
            'cond' => $cond,
            'outfit' => $outfit,
            'serious' => $serious,
            // 严肃模式：原文照登所有黄色及以上预警；否则只把低级别预警放横幅
            'serious_warnings' => $seriousWarnings,
            'banner_warnings' => $serious ? [] : $warnings,
            'decisions' => $decisions,
            'decisions_for' => $target['date'] ?? null,
            'quip_trigger' => $serious ? null : $this->quipTrigger($cond, $outfit['key']),
            'care_topic' => $this->careTopic($cond, $outfit['key'], $decisions['umbrella']['verdict']),
        ];
    }

    public function outfit(int $feelsLike): array
    {
        foreach (config('weather.outfit_bands') as $band) {
            if ($feelsLike >= $band['min']) {
                return ['key' => $band['key'], 'label' => $band['label'], 'feels_like' => $feelsLike];
            }
        }

        $last = last(config('weather.outfit_bands'));

        return ['key' => $last['key'], 'label' => $last['label'], 'feels_like' => $feelsLike];
    }

    public function iconCond(int $icon): ?string
    {
        foreach (config('weather.icon_cond') as $rule) {
            if (isset($rule['codes']) && in_array($icon, $rule['codes'], true)) {
                return $rule['cond'];
            }
            if (isset($rule['range']) && $icon >= $rule['range'][0] && $icon <= $rule['range'][1]) {
                return $rule['cond'];
            }
        }

        return null;
    }

    public function cond(array $now, ?string $adm, ?string $date): string
    {
        $cond = $this->iconCond($now['icon']) ?? 'cloudy';

        if (in_array($cond, ['sunny', 'cloudy'], true) && $now['wind_scale'] >= config('weather.wind_scale_cond')) {
            return 'wind';
        }

        $humid = config('weather.humid');
        $month = $date ? (int) substr($date, 5, 2) : (int) now()->month;
        if (in_array($cond, ['sunny', 'cloudy', 'light_rain', 'smog'], true)
            && $adm && in_array($adm, $humid['adm'], true)
            && in_array($month, $humid['months'], true)
            && $now['humidity'] >= $humid['min_humidity']) {
            return 'humid';
        }

        return $cond;
    }

    /**
     * 决策针对哪一天：当天 22 点前看今天剩下的时段，过了就看明天。
     *
     * @return array{0:int, 1:array}
     */
    private function targetDay(array $hourly, array $daily): array
    {
        [$from, $to] = config('weather.decisions.umbrella.hours');

        foreach ([0, 1] as $idx) {
            $date = $daily[$idx]['date'] ?? null;
            if (! $date) {
                break;
            }
            $hours = array_values(array_filter($hourly, function ($h) use ($date, $from, $to) {
                $t = CarbonImmutable::parse($h['time']);

                // 预报时间自带时区偏移，取当地小时
                return $t->format('Y-m-d') === $date && $t->hour >= $from && $t->hour <= $to;
            }));
            if ($hours !== []) {
                return [$idx, $hours];
            }
        }

        return [0, []];
    }

    private function isRainIcon(int $icon): bool
    {
        [$lo, $hi] = config('weather.rain_icons');

        return ($icon >= $lo && $icon <= $hi) || ($icon >= 400 && $icon <= 499);
    }

    private function umbrella(array $hours, ?array $target): array
    {
        $cfg = config('weather.decisions.umbrella');
        $peak = null;
        foreach ($hours as $h) {
            $pop = $h['pop'] ?? ($this->isRainIcon($h['icon']) ? 100 : 0);
            if ($peak === null || $pop > $peak['pop']) {
                $peak = ['pop' => $pop, 'hour' => CarbonImmutable::parse($h['time'])->hour];
            }
        }

        if ($peak === null && $target) {
            // 没有逐小时数据时，退回用日预报
            $rainy = $this->isRainIcon($target['icon_day']) || $target['precip'] > 0;
            $peak = ['pop' => $rainy ? 60 : 0, 'hour' => null];
        }
        $peak ??= ['pop' => 0, 'hour' => null];

        $at = $peak['hour'] !== null ? "{$peak['hour']}点前后" : '今天';

        if ($peak['pop'] >= $cfg['take_pop']) {
            return ['verdict' => 'take', 'label' => '带', 'reason' => "{$at}降水概率 {$peak['pop']}%", 'pop' => $peak['pop'], 'hour' => $peak['hour']];
        }
        if ($peak['pop'] >= $cfg['maybe_pop']) {
            return ['verdict' => 'maybe', 'label' => '随便', 'reason' => "{$at}降水概率 {$peak['pop']}%，看心情", 'pop' => $peak['pop'], 'hour' => $peak['hour']];
        }
        if ($target && $target['uv_index'] >= $cfg['sun_uv']) {
            return ['verdict' => 'sun', 'label' => '带（防晒）', 'reason' => "紫外线指数 {$target['uv_index']}，打伞防晒", 'pop' => $peak['pop'], 'hour' => null];
        }

        return ['verdict' => 'no', 'label' => '不带', 'reason' => '不会下雨', 'pop' => $peak['pop'], 'hour' => null];
    }

    private function longJohns(array $now, ?array $target, bool $isToday): array
    {
        $min = $target['temp_min'] ?? $now['feels_like'];
        if ($isToday) {
            $min = min($min, $now['feels_like']);
        }
        $wear = $min < config('weather.decisions.long_johns.feels_below');

        return [
            'verdict' => $wear ? 'yes' : 'no',
            'label' => $wear ? '穿' : '不用',
            'reason' => "最低体感约 {$min}°",
            'min_feels' => $min,
        ];
    }

    private function carWash(array $daily, int $from): array
    {
        $days = config('weather.decisions.car_wash.dry_days');
        $window = array_slice($daily, $from, $days);
        $dust = config('weather.dust_icons');

        foreach ($window as $i => $d) {
            $wet = $this->isRainIcon($d['icon_day']) || $this->isRainIcon($d['icon_night']) || $d['precip'] > 0;
            $dusty = in_array($d['icon_day'], $dust, true) || in_array($d['icon_night'], $dust, true);
            if ($wet || $dusty) {
                $when = $i === 0 ? '今天' : ($i === 1 ? '明天' : '后天');

                return ['verdict' => 'no', 'label' => '别洗', 'reason' => $when.($wet ? '有雨' : '有沙尘')];
            }
        }

        if (count($window) < $days) {
            return ['verdict' => 'no', 'label' => '再等等', 'reason' => '预报天数不够'];
        }

        return ['verdict' => 'yes', 'label' => '洗', 'reason' => "未来 {$days} 天无雨"];
    }

    private function laundry(array $hours, ?array $target): array
    {
        $cfg = config('weather.decisions.laundry');
        [$from, $to] = $cfg['hours'];
        $day = array_values(array_filter($hours, function ($h) use ($from, $to) {
            $hour = CarbonImmutable::parse($h['time'])->hour;

            return $hour >= $from && $hour <= $to;
        }));

        if ($day !== []) {
            $rain = (bool) array_filter($day, fn ($h) => $this->isRainIcon($h['icon']) || ($h['pop'] ?? 0) >= 50);
            $humidity = (int) round(array_sum(array_column($day, 'humidity')) / count($day));
            $wind = max(array_column($day, 'wind_scale'));
        } elseif ($target) {
            $rain = $this->isRainIcon($target['icon_day']) || $target['precip'] > 0;
            $humidity = $target['humidity'];
            $wind = $target['wind_scale'];
        } else {
            return ['verdict' => 'no', 'label' => '别晾', 'reason' => '暂无预报'];
        }

        if ($rain) {
            return ['verdict' => 'no', 'label' => '别晾', 'reason' => '白天有雨'];
        }
        if ($wind >= $cfg['max_wind_scale']) {
            return ['verdict' => 'no', 'label' => '别晾', 'reason' => "风力 {$wind} 级，会被吹跑"];
        }
        if ($humidity >= $cfg['max_humidity']) {
            return ['verdict' => 'no', 'label' => '别晾', 'reason' => "湿度 {$humidity}%，干不了"];
        }

        return ['verdict' => 'yes', 'label' => '晾', 'reason' => "湿度 {$humidity}%，白天无雨"];
    }

    private function quipTrigger(string $cond, string $outfitKey): string
    {
        $condTriggers = ['light_rain', 'heavy_rain', 'thunder', 'snow', 'wind', 'smog', 'dust', 'humid'];

        return in_array($cond, $condTriggers, true) ? $cond : $outfitKey;
    }

    /** 关心群里给这个人发提醒时，建议的话题；null 表示没什么好提醒的 */
    private function careTopic(string $cond, string $outfitKey, string $umbrella): ?string
    {
        return match (true) {
            $cond === 'serious' => 'alert',
            $cond === 'light_rain' => 'rain',
            in_array($cond, ['heavy_rain', 'thunder', 'snow', 'wind', 'smog', 'dust'], true) => $cond,
            $umbrella === 'take' => 'rain',
            in_array($outfitKey, ['cold', 'freezing'], true) => 'cold',
            $outfitKey === 'hot' => 'hot',
            $outfitKey === 'mild' && $cond === 'sunny' => 'nice',
            default => null,
        };
    }
}
