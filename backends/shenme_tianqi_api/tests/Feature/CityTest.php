<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\CityController;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CityTest extends TestCase
{
    use RefreshDatabase;

    public function test_first_city_becomes_home_and_no_five_city_limit(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');

        // 不再限制 5 个
        foreach (range(1, 8) as $i) {
            $this->postJson('/api/v1/cities', ['location_id' => "1010101$i", 'name' => "城市$i"])->assertCreated();
        }

        $cities = $this->getJson('/api/v1/cities')->json('data');
        $this->assertCount(8, $cities);
        $this->assertTrue($cities[0]['is_home']);
        $this->assertNull($cities[0]['expires_at']);
        $this->assertSame(1, collect($cities)->where('is_home', true)->count());
    }

    public function test_hidden_anti_abuse_cap(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');
        foreach (range(1, CityController::MAX_CITIES) as $i) {
            $user->cities()->create(['location_id' => "1$i", 'name' => "城市$i", 'sort' => min(255, $i)]);
        }

        $this->postJson('/api/v1/cities', ['location_id' => '999', 'name' => '多余'])
            ->assertStatus(422)
            ->assertJsonPath('errors.location_id.0', '关注的城市太多了，先删几个吧');
    }

    public function test_temporary_city_expires_and_never_becomes_home(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');
        $this->postJson('/api/v1/cities', ['location_id' => '101010100', 'name' => '北京'])->assertCreated();

        $expires = now()->startOfDay()->addDays(3)->toIso8601String();
        $trip = $this->postJson('/api/v1/cities', ['location_id' => '101280101', 'name' => '广州', 'expires_at' => $expires])
            ->assertCreated()
            ->assertJsonPath('data.is_home', false)
            ->json('data');
        $this->assertNotNull($trip['expires_at']);

        // 临时城市不能当常驻
        $this->patchJson("/api/v1/cities/{$trip['id']}", ['is_home' => true])->assertStatus(422);
        $this->postJson('/api/v1/cities', ['location_id' => '101020100', 'name' => '上海', 'is_home' => true, 'expires_at' => $expires])
            ->assertStatus(422);

        // 到期后不再返回，清理命令把它删掉
        $this->travel(4)->days();
        $this->assertSame(['北京'], collect($this->getJson('/api/v1/cities')->json('data'))->pluck('name')->all());
        $this->artisan('cities:prune')->assertSuccessful();
        $this->assertDatabaseMissing('user_cities', ['id' => $trip['id']]);
    }

    public function test_temporary_city_can_become_permanent_and_expiry_is_limited(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');
        $home = $this->postJson('/api/v1/cities', ['location_id' => '101010100', 'name' => '北京'])->json('data.id');

        // 到期时间要在未来、最多 7 天（多留一天余量）
        $this->postJson('/api/v1/cities', ['location_id' => '101280101', 'name' => '广州', 'expires_at' => now()->subHour()->toIso8601String()])
            ->assertStatus(422);
        $this->postJson('/api/v1/cities', ['location_id' => '101280101', 'name' => '广州', 'expires_at' => now()->addDays(10)->toIso8601String()])
            ->assertStatus(422);

        $trip = $this->postJson('/api/v1/cities', ['location_id' => '101280101', 'name' => '广州', 'expires_at' => now()->addDays(2)->toIso8601String()])
            ->json('data.id');
        $this->patchJson("/api/v1/cities/$trip", ['expires_at' => null])->assertJsonPath('data.expires_at', null);
        $this->patchJson("/api/v1/cities/$trip", ['is_home' => true])->assertJsonPath('data.is_home', true);

        // 常驻城市不能改成临时的
        $this->patchJson("/api/v1/cities/$trip", ['expires_at' => now()->addDay()->toIso8601String()])->assertStatus(422);
        $this->assertDatabaseHas('user_cities', ['id' => $home, 'is_home' => false]);
    }

    public function test_deleting_home_skips_temporary_cities(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');
        $home = $this->postJson('/api/v1/cities', ['location_id' => '101010100', 'name' => '北京'])->json('data.id');
        $this->postJson('/api/v1/cities', ['location_id' => '101280101', 'name' => '广州', 'expires_at' => now()->addDays(2)->toIso8601String()]);
        $sh = $this->postJson('/api/v1/cities', ['location_id' => '101020100', 'name' => '上海'])->json('data.id');

        $this->deleteJson("/api/v1/cities/$home")->assertOk();
        $this->assertDatabaseHas('user_cities', ['id' => $sh, 'is_home' => true]);
    }

    public function test_switch_home_and_delete_home_reassigns(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');

        $a = $this->postJson('/api/v1/cities', ['location_id' => '101010100', 'name' => '北京'])->json('data.id');
        $b = $this->postJson('/api/v1/cities', ['location_id' => '101020100', 'name' => '上海'])->json('data.id');

        $this->patchJson("/api/v1/cities/$b", ['is_home' => true])->assertJsonPath('data.is_home', true);
        $this->assertDatabaseHas('user_cities', ['id' => $a, 'is_home' => false]);

        $this->deleteJson("/api/v1/cities/$b")->assertOk();
        $this->assertDatabaseHas('user_cities', ['id' => $a, 'is_home' => true]);
    }

    public function test_cannot_touch_other_users_city(): void
    {
        $owner = User::factory()->create();
        $id = $this->actingAs($owner, 'sanctum')
            ->postJson('/api/v1/cities', ['location_id' => '101010100', 'name' => '北京'])->json('data.id');

        $this->actingAs(User::factory()->create(), 'sanctum')
            ->deleteJson("/api/v1/cities/$id")->assertNotFound();
    }
}
