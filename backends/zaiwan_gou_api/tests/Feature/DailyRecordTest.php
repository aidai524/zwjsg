<?php

namespace Tests\Feature;

use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DailyRecordTest extends TestCase
{
    use RefreshDatabase;

    public function test_upsert_recomputes_stage_and_unlocks_breed(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);
        $today = $user->localToday();

        $res = $this->putJson("/api/v1/daily-records/{$today}", [
            'dog_percent' => 134,
            'minutes_used' => 241,
            'breed_key' => 'corgi',
            'stage' => 0, // 客户端传的阶段会被忽略
        ])->assertOk();

        $res->assertJsonPath('record.stage', 4)
            ->assertJsonPath('newly_unlocked', ['corgi']);

        // 同一天再报一次：覆盖，不重复解锁
        $this->putJson("/api/v1/daily-records/{$today}", [
            'dog_percent' => 150, 'minutes_used' => 270, 'breed_key' => 'corgi',
        ])->assertOk()->assertJsonPath('record.stage', 5)->assertJsonPath('newly_unlocked', []);

        $this->assertDatabaseCount('daily_records', 1);
    }

    public function test_app_details_are_never_stored(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->putJson('/api/v1/daily-records/'.$user->localToday(), [
            'dog_percent' => 50,
            'minutes_used' => 90,
            'apps' => ['com.example.video' => 80],
        ])->assertOk();

        $this->assertDatabaseHas('daily_records', ['user_id' => $user->id, 'dog_percent' => 50]);
        $this->assertArrayNotHasKey('apps', $user->dailyRecords()->first()->getAttributes());
    }

    public function test_rare_breeds_can_be_reported_and_show_in_dex(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);
        $today = CarbonImmutable::parse($user->localToday());

        $this->putJson('/api/v1/daily-records/'.$today->subDay()->toDateString(), [
            'dog_percent' => 67, 'minutes_used' => 120, 'breed_key' => 'mutt',
        ])->assertOk()->assertJsonPath('newly_unlocked', ['mutt']);
        $this->putJson('/api/v1/daily-records/'.$today->toDateString(), [
            'dog_percent' => 44, 'minutes_used' => 80, 'breed_key' => 'retriever',
        ])->assertOk()->assertJsonPath('newly_unlocked', ['retriever']);

        $this->getJson('/api/v1/breeds')->assertOk()
            ->assertJsonPath('owned', 2)
            ->assertJsonPath('total', 8)
            ->assertJsonFragment(['key' => 'mutt', 'name' => '串串', 'rarity' => 'rare', 'unlocked' => true])
            ->assertJsonFragment(['key' => 'retriever', 'name' => '金毛寻回犬', 'rarity' => 'rare', 'unlocked' => true]);

        // 定下来以前的占位 key 不认
        $this->putJson('/api/v1/daily-records/'.$today->toDateString(), [
            'dog_percent' => 44, 'minutes_used' => 80, 'breed_key' => 'rare_a',
        ])->assertStatus(422);
    }

    public function test_client_cannot_report_legend_breed(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->putJson('/api/v1/daily-records/'.$user->localToday(), [
            'dog_percent' => 10, 'minutes_used' => 18, 'breed_key' => 'wolf',
        ])->assertStatus(422);
    }

    public function test_seven_human_days_unlock_wolf(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);
        $today = CarbonImmutable::parse($user->localToday());

        // 先直接写入 6 天前到昨天的记录（超出补报窗口的部分用模型写入）
        for ($i = 6; $i >= 1; $i--) {
            $user->dailyRecords()->create([
                'date' => $today->subDays($i)->toDateString(),
                'dog_percent' => 20, 'stage' => 0, 'minutes_used' => 36,
            ]);
        }

        $this->putJson('/api/v1/daily-records/'.$today->toDateString(), [
            'dog_percent' => 15, 'minutes_used' => 27,
        ])->assertOk()->assertJsonPath('newly_unlocked', ['wolf']);

        $this->getJson('/api/v1/breeds')->assertOk()
            ->assertJsonPath('owned', 1)
            ->assertJsonFragment(['key' => 'wolf', 'unlocked' => true]);
    }

    public function test_future_and_old_dates_are_rejected(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);
        $today = CarbonImmutable::parse($user->localToday());
        $payload = ['dog_percent' => 40, 'minutes_used' => 72];

        $this->putJson('/api/v1/daily-records/'.$today->addDay()->toDateString(), $payload)->assertStatus(422);
        $this->putJson('/api/v1/daily-records/'.$today->subDays(3)->toDateString(), $payload)->assertStatus(422);
        $this->putJson('/api/v1/daily-records/'.$today->subDays(2)->toDateString(), $payload)->assertOk();
    }

    public function test_history_range(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);
        $today = $user->localToday();

        $this->putJson("/api/v1/daily-records/{$today}", ['dog_percent' => 72, 'minutes_used' => 130])->assertOk();

        $this->getJson("/api/v1/daily-records?from={$today}&to={$today}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.stage', 2);
    }

    public function test_settings_validation(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->patchJson('/api/v1/me/settings', ['daily_goal_minutes' => 30])->assertStatus(422);
        // 目标只有三档：3、5、8 小时，自己填的小时数不收
        $this->patchJson('/api/v1/me/settings', ['daily_goal_minutes' => 240])->assertStatus(422);
        $this->patchJson('/api/v1/me/settings', ['daily_goal_minutes' => 300, 'remind_at' => '21:30'])
            ->assertOk()
            ->assertJsonPath('data.daily_goal_minutes', 300)
            ->assertJsonPath('data.remind_at', '21:30');
    }

    public function test_festival_breed_only_on_its_days_and_only_when_a_dog(): void
    {
        // 元旦那天变狗：立flag犬
        $this->travelTo(CarbonImmutable::parse('2027-01-01 20:00', 'Asia/Shanghai'));
        $user = User::factory()->create();
        Sanctum::actingAs($user);
        $this->putJson('/api/v1/daily-records/2027-01-01', ['dog_percent' => 72, 'minutes_used' => 130, 'breed_key' => 'flag'])
            ->assertOk()
            ->assertJsonPath('record.breed_key', 'flag')
            ->assertJsonPath('newly_unlocked', ['flag']);

        // 第二天还报立flag犬：不收，那天不记犬种，记录照样存下
        $this->travelTo(CarbonImmutable::parse('2027-01-02 20:00', 'Asia/Shanghai'));
        $this->putJson('/api/v1/daily-records/2027-01-02', ['dog_percent' => 72, 'minutes_used' => 130, 'breed_key' => 'flag'])
            ->assertOk()
            ->assertJsonPath('record.breed_key', null)
            ->assertJsonPath('record.stage', 2);

        // 春节那几天：旺财；还是人的话不算
        $this->travelTo(CarbonImmutable::parse('2027-02-07 20:00', 'Asia/Shanghai'));
        $this->putJson('/api/v1/daily-records/2027-02-06', ['dog_percent' => 20, 'minutes_used' => 36, 'breed_key' => 'wangcai'])
            ->assertOk()
            ->assertJsonPath('record.breed_key', null)
            ->assertJsonPath('newly_unlocked', []);
        $this->putJson('/api/v1/daily-records/2027-02-07', ['dog_percent' => 95, 'minutes_used' => 171, 'breed_key' => 'wangcai'])
            ->assertOk()
            ->assertJsonPath('record.breed_key', 'wangcai')
            ->assertJsonPath('newly_unlocked', ['wangcai']);
        // 图鉴总数：没拿到的限定犬种不算
        $this->getJson('/api/v1/breeds')->assertOk()
            ->assertJsonPath('owned', 2)
            ->assertJsonPath('total', 10)
            ->assertJsonFragment(['key' => 'wangcai', 'name' => '旺财', 'rarity' => 'limited', 'unlocked' => true]);

        // 没有这种限定犬种
        $this->putJson('/api/v1/daily-records/2027-02-07', ['dog_percent' => 95, 'minutes_used' => 171, 'breed_key' => 'nianshou'])
            ->assertStatus(422);
    }
}
