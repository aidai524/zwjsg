<?php

namespace Tests\Feature;

use App\Services\WeatherInterpreter;
use Tests\Support\WeatherFixtures;
use Tests\TestCase;

class WeatherInterpreterTest extends TestCase
{
    use WeatherFixtures;

    private function interpret(array $snap, ?string $adm = null): array
    {
        return app(WeatherInterpreter::class)->interpret($snap, $adm);
    }

    public function test_outfit_bands_follow_feels_like(): void
    {
        $i = app(WeatherInterpreter::class);
        $this->assertSame('hot', $i->outfit(35)['key']);
        $this->assertSame('warm', $i->outfit(34)['key']);
        $this->assertSame('mild', $i->outfit(18)['key']);
        $this->assertSame('cool', $i->outfit(10)['key']);
        $this->assertSame('cold', $i->outfit(0)['key']);
        $this->assertSame('freezing', $i->outfit(-1)['key']);
    }

    public function test_icon_codes_map_to_avatar_conditions(): void
    {
        $i = app(WeatherInterpreter::class);
        $this->assertSame('sunny', $i->iconCond(100));
        $this->assertSame('cloudy', $i->iconCond(104));
        $this->assertSame('light_rain', $i->iconCond(305));
        $this->assertSame('heavy_rain', $i->iconCond(307));
        $this->assertSame('thunder', $i->iconCond(302));
        $this->assertSame('snow', $i->iconCond(401));
        $this->assertSame('smog', $i->iconCond(502));
        $this->assertSame('dust', $i->iconCond(507));
    }

    public function test_umbrella_thresholds(): void
    {
        $take = $this->interpret($this->snap(hourly: $this->hours(overrides: [15 => ['pop' => 60]])));
        $this->assertSame('take', $take['decisions']['umbrella']['verdict']);
        $this->assertSame(15, $take['decisions']['umbrella']['hour']);
        $this->assertSame('rain', $take['care_topic']);

        $maybe = $this->interpret($this->snap(hourly: $this->hours(overrides: [15 => ['pop' => 40]])));
        $this->assertSame('maybe', $maybe['decisions']['umbrella']['verdict']);

        $no = $this->interpret($this->snap());
        $this->assertSame('no', $no['decisions']['umbrella']['verdict']);

        $sun = $this->interpret($this->snap(daily: [$this->day('2026-11-06', ['uv_index' => 8]), $this->day('2026-11-07'), $this->day('2026-11-08')]));
        $this->assertSame('sun', $sun['decisions']['umbrella']['verdict']);
    }

    public function test_long_johns_by_lowest_feels_like(): void
    {
        $cold = $this->interpret($this->snap(daily: [$this->day('2026-11-06', ['temp_min' => 6]), $this->day('2026-11-07'), $this->day('2026-11-08')]));
        $this->assertSame('yes', $cold['decisions']['long_johns']['verdict']);

        $warm = $this->interpret($this->snap());
        $this->assertSame('no', $warm['decisions']['long_johns']['verdict']);
    }

    public function test_car_wash_needs_three_dry_days(): void
    {
        $dry = $this->interpret($this->snap());
        $this->assertSame('yes', $dry['decisions']['car_wash']['verdict']);

        $rainLater = $this->interpret($this->snap(daily: [
            $this->day('2026-11-06'), $this->day('2026-11-07'), $this->day('2026-11-08', ['icon_day' => 305, 'precip' => 3.0]),
        ]));
        $this->assertSame('no', $rainLater['decisions']['car_wash']['verdict']);
        $this->assertStringContainsString('后天', $rainLater['decisions']['car_wash']['reason']);
    }

    public function test_laundry_rejects_humid_or_windy_days(): void
    {
        $this->assertSame('yes', $this->interpret($this->snap())['decisions']['laundry']['verdict']);

        $humid = array_fill_keys(range(8, 18), ['humidity' => 85]);
        $this->assertSame('no', $this->interpret($this->snap(hourly: $this->hours(overrides: $humid)))['decisions']['laundry']['verdict']);

        $windy = [12 => ['wind_scale' => 5]];
        $this->assertSame('no', $this->interpret($this->snap(hourly: $this->hours(overrides: $windy)))['decisions']['laundry']['verdict']);
    }

    public function test_strong_wind_and_south_china_humid_override_avatar(): void
    {
        $this->assertSame('wind', $this->interpret($this->snap(['wind_scale' => 6]))['cond']);

        $humidSnap = $this->snap(['humidity' => 95], daily: [
            $this->day('2026-03-06'), $this->day('2026-03-07'), $this->day('2026-03-08'),
        ], hourly: $this->hours('2026-03-06'));
        $this->assertSame('humid', $this->interpret($humidSnap, '广东省')['cond']);
        $this->assertSame('cloudy', $this->interpret($humidSnap, '北京市')['cond']);
    }

    public function test_yellow_warning_enters_serious_mode_without_quip_and_blue_only_banners(): void
    {
        $yellow = ['id' => 'w1', 'sender' => '北京市气象台', 'pub_time' => '2026-11-06T07:00+08:00',
            'title' => '北京市气象台发布暴雨黄色预警', 'text' => '原文', 'type_name' => '暴雨', 'color' => 'Yellow'];
        $view = $this->interpret($this->snap(warnings: [$yellow]));
        $this->assertTrue($view['serious']);
        $this->assertSame('serious', $view['cond']);
        $this->assertNull($view['quip_trigger']);
        $this->assertSame('alert', $view['care_topic']);
        $this->assertSame('北京市气象台发布暴雨黄色预警', $view['serious_warnings'][0]['title']);

        $blue = ['color' => 'Blue'] + $yellow;
        $view = $this->interpret($this->snap(warnings: [$blue]));
        $this->assertFalse($view['serious']);
        $this->assertCount(1, $view['banner_warnings']);
        $this->assertNotNull($view['quip_trigger']);
    }

    public function test_only_low_level_colors_skip_serious_mode(): void
    {
        $warning = ['id' => 'w1', 'sender' => '气象台', 'pub_time' => null, 'title' => '预警', 'text' => '原文', 'type_name' => '大风'];

        foreach (['White', 'Gray', 'Green', 'Blue'] as $color) {
            $this->assertFalse($this->interpret($this->snap(warnings: [['color' => $color] + $warning]))['serious'], $color);
        }
        // 没见过的颜色也进严肃模式：宁可严肃，也不能在预警时吐槽
        foreach (['Yellow', 'Amber', 'Orange', 'Red', 'Purple', 'Black', 'Magenta', ''] as $color) {
            $this->assertTrue($this->interpret($this->snap(warnings: [['color' => $color] + $warning]))['serious'], $color);
        }
    }

    public function test_after_ten_pm_decisions_look_at_tomorrow(): void
    {
        $hourly = array_map(fn ($h) => array_merge($h, ['time' => str_replace('2026-11-06', '2026-11-07', $h['time'])]), $this->hours());
        $view = $this->interpret($this->snap(hourly: $hourly));
        $this->assertSame('2026-11-07', $view['decisions_for']);
    }

    public function test_every_quip_trigger_has_lines_for_all_levels(): void
    {
        $triggers = ['hot', 'warm', 'mild', 'cool', 'cold', 'freezing', 'light_rain', 'heavy_rain', 'thunder', 'snow', 'wind', 'smog', 'dust', 'humid'];
        foreach ($triggers as $t) {
            foreach ([0, 1, 2] as $level) {
                $this->assertNotEmpty(config("quips.$t.$level"), "$t / $level");
            }
        }
    }
}
