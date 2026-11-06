<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
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
        $this->fakeQWeather(warnings: [[
            'id' => '1', 'sender' => '广州市气象台', 'pubTime' => '2026-11-06T07:00+08:00',
            'title' => '广州市气象台发布暴雨橙色预警信号', 'text' => '预计未来3小时内……请注意防范。',
            'typeName' => '暴雨', 'severityColor' => 'Orange',
        ]]);

        $res = $this->getJson('/api/v1/weather/101280101')->assertOk();
        $res->assertJsonPath('data.view.serious', true)
            ->assertJsonPath('data.view.quip', null)
            ->assertJsonPath('data.warnings.0.text', '预计未来3小时内……请注意防范。')
            ->assertJsonPath('data.warnings.0.sender', '广州市气象台');
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

    public function test_city_search(): void
    {
        $this->fakeQWeather();
        $this->getJson('/api/v1/cities/search?q=广州')
            ->assertOk()
            ->assertJsonPath('data.0.location_id', '101280101')
            ->assertJsonPath('data.0.adm', '广东省');
    }
}
