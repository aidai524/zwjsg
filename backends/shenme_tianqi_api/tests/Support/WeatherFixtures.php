<?php

namespace Tests\Support;

use Illuminate\Support\Facades\Http;

/** 造天气数据：快照结构（给解释器单测）和和风接口返回（给接口测试） */
trait WeatherFixtures
{
    /** 今天 07–22 点的逐小时数据，$overrides 按小时覆盖 */
    protected function hours(string $date = '2026-11-06', array $overrides = []): array
    {
        $hours = [];
        foreach (range(7, 22) as $h) {
            $hours[] = array_merge([
                'time' => sprintf('%sT%02d:00+08:00', $date, $h),
                'temp' => 20, 'icon' => 101, 'text' => '多云', 'pop' => 0, 'wind_scale' => 2, 'humidity' => 50,
            ], $overrides[$h] ?? []);
        }

        return $hours;
    }

    protected function day(string $date, array $o = []): array
    {
        return array_merge([
            'date' => $date, 'temp_max' => 24, 'temp_min' => 14, 'icon_day' => 101, 'text_day' => '多云',
            'icon_night' => 151, 'text_night' => '多云', 'precip' => 0.0, 'uv_index' => 3, 'humidity' => 50, 'wind_scale' => 2,
        ], $o);
    }

    protected function snap(array $now = [], ?array $hourly = null, ?array $daily = null, array $warnings = []): array
    {
        return [
            'location_id' => '101010100',
            'now' => array_merge([
                'temp' => 20, 'feels_like' => 20, 'icon' => 101, 'text' => '多云', 'wind_scale' => 2,
                'wind_dir' => '北风', 'humidity' => 50, 'obs_time' => '2026-11-06T08:00+08:00',
            ], $now),
            'hourly' => $hourly ?? $this->hours(),
            'daily' => $daily ?? [$this->day('2026-11-06'), $this->day('2026-11-07'), $this->day('2026-11-08')],
            'warnings' => $warnings,
            'air' => null,
            'attribution' => '',
        ];
    }

    /** 假的和风接口 */
    protected function fakeQWeather(array $now = [], array $warnings = [], array $hourlyIcon = []): void
    {
        $hourly = [];
        foreach (range(7, 22) as $h) {
            $hourly[] = ['fxTime' => sprintf('2026-11-06T%02d:00+08:00', $h), 'temp' => '20', 'icon' => (string) ($hourlyIcon[$h] ?? 101),
                'text' => '多云', 'pop' => isset($hourlyIcon[$h]) ? '80' : '0', 'windScale' => '1-2', 'humidity' => '50'];
        }
        $daily = [];
        foreach (['2026-11-06', '2026-11-07', '2026-11-08'] as $d) {
            $daily[] = ['fxDate' => $d, 'tempMax' => '24', 'tempMin' => '14', 'iconDay' => '101', 'textDay' => '多云',
                'iconNight' => '151', 'textNight' => '多云', 'precip' => '0.0', 'uvIndex' => '3', 'humidity' => '50', 'windScaleDay' => '1-2'];
        }

        Http::fake([
            '*/v7/weather/now*' => Http::response(['code' => '200', 'now' => array_merge([
                'obsTime' => '2026-11-06T08:00+08:00', 'temp' => '20', 'feelsLike' => '19', 'icon' => '101', 'text' => '多云',
                'windDir' => '北风', 'windScale' => '1-2', 'humidity' => '50',
            ], $now)]),
            '*/v7/weather/24h*' => Http::response(['code' => '200', 'hourly' => $hourly]),
            '*/v7/weather/7d*' => Http::response(['code' => '200', 'daily' => $daily]),
            '*/v7/warning/now*' => Http::response(['code' => '200', 'warning' => $warnings]),
            '*/v7/air/now*' => Http::response(['code' => '200', 'now' => ['aqi' => '42', 'category' => '优', 'primary' => 'NA']]),
            '*/geo/v2/city/lookup*' => Http::response(['code' => '200', 'location' => [
                ['id' => '101280101', 'name' => '广州', 'adm1' => '广东省', 'adm2' => '广州', 'lat' => '23.12', 'lon' => '113.28'],
            ]]),
        ]);
    }
}
