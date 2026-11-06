<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CityTest extends TestCase
{
    use RefreshDatabase;

    public function test_first_city_becomes_home_and_limit_is_five(): void
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');

        foreach (range(1, 5) as $i) {
            $this->postJson('/api/v1/cities', ['location_id' => "10101010$i", 'name' => "城市$i"])->assertCreated();
        }
        $this->postJson('/api/v1/cities', ['location_id' => '101010109', 'name' => '多余'])->assertStatus(422);

        $cities = $this->getJson('/api/v1/cities')->json('data');
        $this->assertCount(5, $cities);
        $this->assertTrue($cities[0]['is_home']);
        $this->assertSame(1, collect($cities)->where('is_home', true)->count());
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
