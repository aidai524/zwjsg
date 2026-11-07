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
        [$lat, $lon] = $this->coordinates($locationId);

        $now = Cache::remember("qw:now:$locationId", $ttl['now'], function () use ($lat, $lon) {
            $n = $this->qw->now($lat, $lon);

            return [
                'temp' => self::degrees($n['temperature'] ?? null),
                'feels_like' => self::degrees($n['feelsLike'] ?? $n['temperature'] ?? null),
                'icon' => (int) ($n['condition']['code'] ?? 100),
                'text' => $n['condition']['text'] ?? '',
                'wind_scale' => (int) ($n['wind']['scale'] ?? 0),
                'wind_dir' => config('weather.wind_dirs')[$n['wind']['direction']['compass'] ?? ''] ?? '',
                'humidity' => self::percent($n['humidity'] ?? 0),
                'obs_time' => $n['validTime'] ?? null,
            ];
        });

        $hourly = Cache::remember("qw:hourly:$locationId", $ttl['hourly'], function () use ($lat, $lon) {
            return array_map(fn (array $h) => [
                'time' => $h['forecastTime'],
                'temp' => self::degrees($h['temperature'] ?? null),
                'icon' => (int) $h['condition']['code'],
                'text' => $h['condition']['text'] ?? '',
                'pop' => isset($h['precipitation']['probability']) ? self::percent($h['precipitation']['probability']) : null,
                'wind_scale' => (int) ($h['wind']['scale'] ?? 0),
                'humidity' => self::percent($h['humidity'] ?? 0),
            ], $this->qw->hourly($lat, $lon)['hours'] ?? []);
        });

        $daily = Cache::remember("qw:daily:$locationId", $ttl['daily'], function () use ($lat, $lon) {
            return array_map(fn (array $d) => [
                'date' => substr($d['forecastStartTime'], 0, 10),
                'temp_max' => self::degrees($d['temperatureMax'] ?? null),
                'temp_min' => self::degrees($d['temperatureMin'] ?? null),
                'icon_day' => (int) $d['daytime']['condition']['code'],
                'text_day' => $d['daytime']['condition']['text'] ?? '',
                'icon_night' => (int) ($d['nighttime']['condition']['code'] ?? $d['daytime']['condition']['code']),
                'text_night' => $d['nighttime']['condition']['text'] ?? '',
                // 接口没有全天降水量，白天和夜间相加
                'precip' => round(
                    ($d['daytime']['precipitation']['amount']['value'] ?? 0) + ($d['nighttime']['precipitation']['amount']['value'] ?? 0),
                    2,
                ),
                'uv_index' => (int) round($d['uvIndexMax'] ?? 0),
                // 决策卡看白天，所以取白天的湿度和风力
                'humidity' => self::percent($d['daytime']['humidity'] ?? 0),
                'wind_scale' => (int) ($d['daytime']['wind']['scale'] ?? 0),
            ], $this->qw->daily($lat, $lon)['days'] ?? []);
        });

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

    /** 新接口的温度带小数，页面和规则都用整数 */
    private static function degrees(?array $temperature): int
    {
        return (int) round($temperature['value'] ?? 0);
    }

    /** 新接口的比例是 0 到 1 的小数，页面和规则都用百分比 */
    private static function percent(int|float $ratio): int
    {
        return (int) round($ratio * 100);
    }
}
