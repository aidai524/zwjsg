<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\Support\WeatherFixtures;
use Tests\TestCase;

class WeatherApiTest extends TestCase
{
    use RefreshDatabase, WeatherFixtures;

    public function test_guest_can_view_weather_and_requests_carry_api_key(): void
    {
        config(['services.qweather.key' => 'test-key', 'services.qweather.host' => 'abc.qweatherapi.com']);
        $this->fakeQWeather();

        $res = $this->getJson('/api/v1/weather/101010100?level=2')->assertOk();
        $res->assertJsonPath('data.now.temp', 20)
            ->assertJsonPath('data.view.level', 2)
            ->assertJsonPath('data.view.decisions.umbrella.verdict', 'no');
        $this->assertNotNull($res->json('data.view.quip'));

        Http::assertSent(fn ($req) => $req->hasHeader('X-QW-Api-Key', 'test-key')
            && str_starts_with($req->url(), 'https://abc.qweatherapi.com/'));
    }

    public function test_snapshot_is_cached(): void
    {
        $this->fakeQWeather();
        $this->getJson('/api/v1/weather/101010100')->assertOk();
        $count = count(Http::recorded());
        $this->getJson('/api/v1/weather/101010100')->assertOk();
        $this->assertCount($count, Http::recorded());
    }

    public function test_quip_is_stable_within_a_day(): void
    {
        $this->fakeQWeather();
        $a = $this->getJson('/api/v1/weather/101010100')->json('data.view.quip');
        $b = $this->getJson('/api/v1/weather/101010100')->json('data.view.quip');
        $this->assertSame($a, $b);
    }

    public function test_warnings_are_passed_through_verbatim(): void
    {
        $this->fakeQWeather(warnings: [$this->alert()]);

        $res = $this->getJson('/api/v1/weather/101280101')->assertOk();
        $res->assertJsonPath('data.view.serious', true)
            ->assertJsonPath('data.view.quip', null)
            ->assertJsonPath('data.warnings.0.title', '广州市气象台发布暴雨橙色预警信号')
            ->assertJsonPath('data.warnings.0.text', '预计未来3小时内……请注意防范。')
            ->assertJsonPath('data.warnings.0.sender', '广州市气象台')
            ->assertJsonPath('data.warnings.0.pub_time', '2026-11-06T07:00+08:00')
            ->assertJsonPath('data.warnings.0.type_name', '暴雨')
            ->assertJsonPath('data.warnings.0.color', 'Orange');
    }

    public function test_low_level_warning_only_shows_a_banner(): void
    {
        $this->fakeQWeather(warnings: [$this->alert(['color' => ['code' => 'blue']])]);

        $this->getJson('/api/v1/weather/101280101')->assertOk()
            ->assertJsonPath('data.view.serious', false)
            ->assertJsonPath('data.view.banner_warnings.0.color', 'Blue');
    }

    public function test_cancelled_warning_is_not_shown(): void
    {
        // 解除消息保留原预警的颜色，还会返回 1 小时；不过滤的话解除后还停在严肃模式
        $this->fakeQWeather(warnings: [$this->alert(['messageType' => ['code' => 'cancel', 'supersedes' => ['1']]])]);

        $this->getJson('/api/v1/weather/101280101')->assertOk()
            ->assertJsonPath('data.view.serious', false)
            ->assertJsonCount(0, 'data.warnings');
    }

    public function test_alert_failure_returns_503_instead_of_hiding_warnings(): void
    {
        // 预警决定严肃模式：查不到时不能当成“没有预警”继续吐槽
        Http::fake(['*/weatheralert/v1/current/*' => Http::response(['error' => ['status' => 403]], 403)]);
        $this->fakeQWeather();

        $this->getJson('/api/v1/weather/101280101')->assertStatus(503);
    }

    public function test_alert_and_air_are_queried_by_two_decimal_coordinates(): void
    {
        $this->fakeQWeather();
        $this->getJson('/api/v1/weather/101280101')->assertOk();

        Http::assertSent(fn ($req) => str_contains($req->url(), '/weatheralert/v1/current/23.13/113.28')
            && str_contains($req->url(), 'localTime=true'));
        Http::assertSent(fn ($req) => str_contains($req->url(), '/airquality/v1/current/23.13/113.28'));
    }

    public function test_city_without_coordinates_returns_503(): void
    {
        Http::fake(['*/geo/v2/city/lookup*' => Http::response(['code' => '200', 'location' => []])]);
        $this->fakeQWeather();

        $this->getJson('/api/v1/weather/101280101')->assertStatus(503);
    }

    public function test_air_quality_prefers_china_index(): void
    {
        Http::fake(['*/airquality/v1/current/*' => Http::response(['indexes' => [
            ['code' => 'qaqi', 'aqi' => 1.5, 'category' => 'Excellent', 'primaryPollutant' => null],
            ['code' => 'cn-mee', 'aqi' => 76, 'category' => '良', 'primaryPollutant' => ['code' => 'pm2p5', 'name' => 'PM 2.5']],
        ]])]);
        $this->fakeQWeather();

        $this->getJson('/api/v1/weather/101280101')->assertOk()
            ->assertJsonPath('data.air.aqi', 76)
            ->assertJsonPath('data.air.category', '良')
            ->assertJsonPath('data.air.primary', 'PM 2.5');
    }

    public function test_air_failure_does_not_block_weather(): void
    {
        Http::fake(['*/airquality/v1/current/*' => Http::response(['error' => ['status' => 403]], 403)]);
        $this->fakeQWeather();

        $this->getJson('/api/v1/weather/101280101')->assertOk()->assertJsonPath('data.air', null);
    }

    public function test_forecast_units_are_converted(): void
    {
        $this->fakeQWeather(now: [
            'temperature' => ['value' => -0.6], 'feelsLike' => ['value' => 6.5], 'humidity' => 0.35,
            'wind' => ['direction' => ['degree' => 195, 'compass' => 'ssw'], 'scale' => 3],
        ]);

        $this->getJson('/api/v1/weather/101280101')->assertOk()
            ->assertJsonPath('data.now.temp', -1)
            ->assertJsonPath('data.now.feels_like', 7)
            ->assertJsonPath('data.now.humidity', 35)
            ->assertJsonPath('data.now.wind_scale', 3)
            ->assertJsonPath('data.now.wind_dir', '西南偏南风')
            ->assertJsonPath('data.now.obs_time', '2026-11-06T08:00+08:00')
            ->assertJsonPath('data.hourly.0.time', '2026-11-06T07:00+08:00')
            ->assertJsonPath('data.hourly.0.temp', 20)
            ->assertJsonPath('data.hourly.0.humidity', 50)
            ->assertJsonPath('data.daily.0.date', '2026-11-06')
            ->assertJsonPath('data.daily.0.temp_max', 24)
            ->assertJsonPath('data.daily.0.temp_min', 14)
            ->assertJsonPath('data.daily.0.icon_day', 101)
            ->assertJsonPath('data.daily.0.icon_night', 102)
            ->assertJsonPath('data.daily.0.humidity', 50)
            ->assertJsonPath('data.daily.0.uv_index', 3);
    }

    public function test_rain_probability_becomes_a_percentage(): void
    {
        // 新接口是 0 到 1 的小数，不换算的话取整后永远是 0，下雨也提示不带伞
        $this->fakeQWeather(hourlyIcon: [15 => 305]);

        $this->getJson('/api/v1/weather/101280101')->assertOk()
            ->assertJsonPath('data.hourly.8.pop', 80)
            ->assertJsonPath('data.view.decisions.umbrella.verdict', 'take');
    }

    public function test_daily_precipitation_adds_day_and_night(): void
    {
        Http::fake(['*/weather/v1/daily/*' => Http::response(['days' => [
            $this->forecastDay('2026-11-06', [
                'daytime' => ['precipitation' => ['amount' => ['value' => 1.5]]],
                'nighttime' => ['precipitation' => ['amount' => ['value' => 0.7]]],
            ]),
        ]])]);
        $this->fakeQWeather();

        $this->getJson('/api/v1/weather/101280101')->assertOk()->assertJsonPath('data.daily.0.precip', 2.2);
    }

    public function test_forecast_requests_use_coordinates_and_local_time(): void
    {
        // 新接口默认返回 UTC，小时错了决策卡就看错时段
        $this->fakeQWeather();
        $this->getJson('/api/v1/weather/101280101')->assertOk();

        foreach (['current', 'hourly', 'daily'] as $kind) {
            Http::assertSent(fn ($req) => str_contains($req->url(), "/weather/v1/{$kind}/23.13/113.28")
                && str_contains($req->url(), 'localTime=true'));
        }
    }

    #[DataProvider('windDirections')]
    public function test_wind_direction_uses_official_wording(string $compass, string $expected): void
    {
        $this->fakeQWeather(now: ['wind' => ['direction' => ['degree' => null, 'compass' => $compass]]]);

        $this->getJson('/api/v1/weather/101280101')->assertOk()->assertJsonPath('data.now.wind_dir', $expected);
    }

    public static function windDirections(): array
    {
        return [['ne', '东北风'], ['none', '无持续风向'], ['vrb', '风向变化不定'], ['xyz', '']];
    }

    public function test_logged_in_user_gets_own_snark_level(): void
    {
        $this->fakeQWeather();
        $user = User::factory()->create(['snark_level' => 0]);

        $this->actingAs($user, 'sanctum')
            ->getJson('/api/v1/weather/101010100?level=2')
            ->assertJsonPath('data.view.level', 0);
    }

    public function test_upstream_failure_returns_503(): void
    {
        Http::fake(['*' => Http::response(['code' => '401'], 200)]);
        $this->getJson('/api/v1/weather/101010100')->assertStatus(503);
    }

    public function test_connection_failure_returns_503(): void
    {
        Http::fake(['*' => Http::failedConnection()]);
        $this->getJson('/api/v1/weather/101010100')->assertStatus(503);
        $this->getJson('/api/v1/cities/search?q=北京')->assertStatus(503);
    }

    public function test_missing_host_returns_503(): void
    {
        config(['services.qweather.host' => '']);
        $this->getJson('/api/v1/weather/101010100')->assertStatus(503);
        $this->getJson('/api/v1/cities/search?q=北京')->assertStatus(503);
    }

    public function test_city_search(): void
    {
        $this->fakeQWeather();
        $this->getJson('/api/v1/cities/search?q=广州')
            ->assertOk()
            ->assertJsonPath('data.0.location_id', '101280101')
            ->assertJsonPath('data.0.adm', '广东省');
    }
}
