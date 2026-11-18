<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Push\PushGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\Support\RecordingPushGateway;
use Tests\Support\WeatherFixtures;
use Tests\TestCase;

class MorningBriefTest extends TestCase
{
    use RefreshDatabase, WeatherFixtures;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_title_writes_the_temperature_in_each_users_unit(): void
    {
        $push = new RecordingPushGateway;
        $this->app->instance(PushGateway::class, $push);
        $this->fakeQWeather();
        Carbon::setTestNow('2026-11-05 23:30:00'); // UTC，北京时间 11 月 6 日周五 07:30

        $users = [];
        foreach (['c', 'f'] as $unit) {
            $users[$unit] = User::factory()->create([
                'temp_unit' => $unit, 'push_token' => "token-{$unit}", 'timezone' => 'Asia/Shanghai',
                'morning_push_on' => true, 'morning_push_weekday' => '07:30',
            ]);
            $users[$unit]->cities()->create(['location_id' => '101280101', 'name' => '广州', 'adm' => '广东省', 'is_home' => true]);
        }

        $this->artisan('weather:morning')->assertSuccessful();

        $this->assertStringStartsWith('广州 20° · 伞：', $push->to($users['c'])[0]['title']);
        $this->assertStringStartsWith('广州 68° · 伞：', $push->to($users['f'])[0]['title']);
    }
}
