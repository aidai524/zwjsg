<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use RuntimeException;

/**
 * 取天气并整理成统一的“快照”结构，分别缓存。
 * 同一城市的请求在缓存期内只打一次和风接口，控制调用量。
 */
class WeatherService
{
    public function __construct(private QWeatherClient $qw) {}

    public function searchCities(string $keyword): array
    {
        $keyword = trim($keyword);

        return Cache::remember('qw:geo:'.md5($keyword), config('weather.cache_ttl.geo'), function () use ($keyword) {
            return array_map(fn (array $c) => [
                'location_id' => (string) $c['id'],
                'name' => $c['name'],
                'adm' => $c['adm1'] ?? null,
                'adm2' => $c['adm2'] ?? null,
                'lat' => $c['lat'] ?? null,
                'lon' => $c['lon'] ?? null,
            ], $this->qw->cityLookup($keyword));
        });
    }

    /**
     * @return array{location_id:string, now:array, hourly:array, daily:array, warnings:array, air:?array, attribution:string}
     */
    public function snapshot(string $locationId): array
    {
        $ttl = config('weather.cache_ttl');

        $now = Cache::remember("qw:now:$locationId", $ttl['now'], function () use ($locationId) {
            $n = $this->qw->now($locationId)['now'] ?? [];

            return [
                'temp' => (int) ($n['temp'] ?? 0),
                'feels_like' => (int) ($n['feelsLike'] ?? $n['temp'] ?? 0),
                'icon' => (int) ($n['icon'] ?? 100),
                'text' => $n['text'] ?? '',
                'wind_scale' => self::maxScale($n['windScale'] ?? '0'),
                'wind_dir' => $n['windDir'] ?? '',
                'humidity' => (int) ($n['humidity'] ?? 0),
                'obs_time' => $n['obsTime'] ?? null,
            ];
        });

        $hourly = Cache::remember("qw:hourly:$locationId", $ttl['hourly'], function () use ($locationId) {
            return array_map(fn (array $h) => [
                'time' => $h['fxTime'],
                'temp' => (int) $h['temp'],
                'icon' => (int) $h['icon'],
                'text' => $h['text'] ?? '',
                'pop' => ($h['pop'] ?? '') === '' ? null : (int) $h['pop'],
                'wind_scale' => self::maxScale($h['windScale'] ?? '0'),
                'humidity' => (int) ($h['humidity'] ?? 0),
            ], $this->qw->hourly($locationId)['hourly'] ?? []);
        });

        $daily = Cache::remember("qw:daily:$locationId", $ttl['daily'], function () use ($locationId) {
            return array_map(fn (array $d) => [
                'date' => $d['fxDate'],
                'temp_max' => (int) $d['tempMax'],
                'temp_min' => (int) $d['tempMin'],
                'icon_day' => (int) $d['iconDay'],
                'text_day' => $d['textDay'] ?? '',
                'icon_night' => (int) ($d['iconNight'] ?? $d['iconDay']),
                'text_night' => $d['textNight'] ?? '',
                'precip' => (float) ($d['precip'] ?? 0),
                'uv_index' => (int) ($d['uvIndex'] ?? 0),
                'humidity' => (int) ($d['humidity'] ?? 0),
                'wind_scale' => self::maxScale($d['windScaleDay'] ?? '0'),
            ], $this->qw->daily($locationId)['daily'] ?? []);
        });

        [$lat, $lon] = $this->coordinates($locationId);

        // 预警决定严肃模式，查询失败时必须报错，不能当成“没有预警”
        $warnings = Cache::remember("qw:warning:$locationId", $ttl['warning'], function () use ($lat, $lon) {
            $alerts = $this->qw->alerts($lat, $lon)['alerts'] ?? [];
            // 解除消息保留原预警的颜色，还会返回 1 小时，不算生效中的预警
            $active = array_filter($alerts, fn (array $a) => ($a['messageType']['code'] ?? '') !== 'cancel');

            // 预警原文照登：标题、正文、发布单位、发布时间都不改
            return array_values(array_map(fn (array $a) => [
                'id' => $a['id'],
                'sender' => $a['senderName'] ?? '',
                'pub_time' => $a['issuedTime'] ?? null,
                'title' => $a['headline'] ?? '',
                'text' => $a['description'] ?? '',
                'type_name' => $a['eventType']['name'] ?? '',
                // 接口返回小写（yellow），解释器和 App 用首字母大写（Yellow）
                'color' => ucfirst($a['color']['code'] ?? ''),
            ], $active));
        });

        // 空气质量失败不影响主流程
        $air = Cache::remember("qw:air:$locationId", $ttl['air'], function () use ($lat, $lon) {
            try {
                $indexes = $this->qw->air($lat, $lon)['indexes'] ?? [];
            } catch (\Throwable) {
                return null;
            }

            $index = collect($indexes)->firstWhere('code', 'cn-mee') ?? ($indexes[0] ?? null);

            return $index ? [
                'aqi' => (int) $index['aqi'],
                'category' => $index['category'] ?? '',
                'primary' => $index['primaryPollutant']['name'] ?? '',
            ] : null;
        });

        return [
            'location_id' => $locationId,
            'now' => $now,
            'hourly' => $hourly,
            'daily' => $daily,
            'warnings' => $warnings,
            'air' => $air,
            'attribution' => '天气数据：和风天气；预警信息来自当地气象部门',
        ];
    }

    /**
     * 预警和空气质量接口要用的经纬度，接口最多支持两位小数。
     *
     * @return array{string, string}
     */
    private function coordinates(string $locationId): array
    {
        return Cache::remember("qw:coord:$locationId", config('weather.cache_ttl.geo'), function () use ($locationId) {
            $city = $this->qw->cityLookup($locationId)[0] ?? null;
            if (! isset($city['lat'], $city['lon'])) {
                throw new RuntimeException("QWeather no coordinates {$locationId}");
            }

            return [number_format((float) $city['lat'], 2, '.', ''), number_format((float) $city['lon'], 2, '.', '')];
        });
    }

    /** "3-4" → 4，"5" → 5 */
    public static function maxScale(string $scale): int
    {
        $parts = array_map('intval', explode('-', $scale));

        return max($parts ?: [0]);
    }
}
