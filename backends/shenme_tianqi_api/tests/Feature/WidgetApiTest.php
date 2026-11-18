<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\Support\WeatherFixtures;
use Tests\TestCase;

/** 桌面小组件的精简天气：温度和句子按单位写好，不带吐槽，严肃模式照登预警标题 */
class WidgetApiTest extends TestCase
{
    use RefreshDatabase, WeatherFixtures;

    public function test_widget_gives_a_compact_view_without_quips(): void
    {
        $this->fakeQWeather();

        $res = $this->getJson('/api/v1/widget/101010100')->assertOk();
        $res->assertJsonPath('data.location_id', '101010100')
            ->assertJsonPath('data.unit', 'c')
            ->assertJsonPath('data.temp', '20°')
            ->assertJsonPath('data.text', '多云')
            ->assertJsonPath('data.range', '14°～24°')
            ->assertJsonPath('data.cond', 'cloudy')
            ->assertJsonPath('data.outfit', 'mild')
            ->assertJsonPath('data.serious', false)
            // 一句话结论和关心群的“一句事实”同一套规则
            ->assertJsonPath('data.line', '体感 19°，长袖/薄外套')
            ->assertJsonPath('data.warning', null)
            ->assertJsonPath('data.warnings_count', 0)
            ->assertJsonPath('data.obs_time', '2026-11-06T08:00+08:00')
            ->assertJsonPath('data.credit', '天气服务由和风天气驱动')
            ->assertJsonMissingPath('data.quip')
            ->assertJsonMissingPath('data.hourly');

        $this->assertSame([
            ['key' => 'umbrella', 'title' => '伞', 'label' => '不带', 'action' => false],
            ['key' => 'long_johns', 'title' => '秋裤', 'label' => '不用', 'action' => false],
            ['key' => 'car_wash', 'title' => '洗车', 'label' => '洗', 'action' => true],
            ['key' => 'laundry', 'title' => '晾衣', 'label' => '晾', 'action' => true],
        ], $res->json('data.decisions'));
    }

    public function test_rain_lights_up_the_umbrella_and_leads_the_line(): void
    {
        $this->fakeQWeather(hourlyIcon: [17 => 305]);

        $res = $this->getJson('/api/v1/widget/101010100')->assertOk()
            ->assertJsonPath('data.line', '17点前后降水概率 80%');
        $this->assertSame(['key' => 'umbrella', 'title' => '伞', 'label' => '带', 'action' => true], $res->json('data.decisions.0'));
    }

    public function test_widget_writes_temperatures_in_the_requested_unit(): void
    {
        $this->fakeQWeather();

        // 小组件不用自己换算：温度和句子都按请求的单位写好
        $this->getJson('/api/v1/widget/101010100?unit=f')->assertOk()
            ->assertJsonPath('data.unit', 'f')
            ->assertJsonPath('data.temp', '68°')
            ->assertJsonPath('data.range', '57°～75°')
            ->assertJsonPath('data.line', '体感 66°，长袖/薄外套');
    }

    public function test_widget_in_serious_mode_shows_the_warning_verbatim(): void
    {
        $this->fakeQWeather(warnings: [$this->alert()]);

        $this->getJson('/api/v1/widget/101280101')->assertOk()
            ->assertJsonPath('data.serious', true)
            ->assertJsonPath('data.cond', 'serious')
            ->assertJsonPath('data.line', null)
            ->assertJsonPath('data.warning.title', '广州市气象台发布暴雨橙色预警信号')
            ->assertJsonPath('data.warning.sender', '广州市气象台')
            ->assertJsonPath('data.warning.pub_time', '2026-11-06T07:00+08:00')
            ->assertJsonPath('data.warning.color', 'Orange')
            ->assertJsonPath('data.warnings_count', 1);
    }

    public function test_low_level_warning_does_not_switch_the_widget_to_serious(): void
    {
        $this->fakeQWeather(warnings: [$this->alert(['color' => ['code' => 'blue']])]);

        $this->getJson('/api/v1/widget/101280101')->assertOk()
            ->assertJsonPath('data.serious', false)
            ->assertJsonPath('data.warning', null);
    }

    public function test_widget_validates_input(): void
    {
        $this->fakeQWeather();

        $this->getJson('/api/v1/widget/bad!id')->assertNotFound();
        $this->getJson('/api/v1/widget/101010100?unit=k')->assertUnprocessable();
    }

    public function test_upstream_failure_returns_503(): void
    {
        Http::fake(['*' => Http::failedConnection()]);

        $this->getJson('/api/v1/widget/101010100')->assertStatus(503);
    }
}
