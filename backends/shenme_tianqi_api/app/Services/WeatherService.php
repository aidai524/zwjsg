<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;

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

        $warnings = Cache::remember("qw:warning:$locationId", $ttl['warning'], function () use ($locationId) {
            // 预警原文照登：标题、正文、发布单位、发布时间都不改
            return array_map(fn (array $w) => [
                'id' => $w['id'],
                'sender' => $w['sender'] ?? '',
                'pub_time' => $w['pubTime'] ?? null,
                'title' => $w['title'] ?? '',
                'text' => $w['text'] ?? '',
                'type_name' => $w['typeName'] ?? '',
                'color' => $w['severityColor'] ?? '',
            ], $this->qw->warnings($locationId)['warning'] ?? []);
        });

        // 空气质量失败不影响主流程
        $air = Cache::remember("qw:air:$locationId", $ttl['air'], function () use ($locationId) {
            try {
                $a = $this->qw->air($locationId)['now'] ?? null;
            } catch (\Throwable) {
                return null;
            }

            return $a ? [
                'aqi' => (int) $a['aqi'],
                'category' => $a['category'] ?? '',
                'primary' => $a['primary'] ?? '',
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

    /** "3-4" → 4，"5" → 5 */
    public static function maxScale(string $scale): int
    {
        $parts = array_map('intval', explode('-', $scale));

        return max($parts ?: [0]);
    }
}
