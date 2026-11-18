<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SettingsTest extends TestCase
{
    use RefreshDatabase;

    public function test_temp_unit_defaults_to_celsius_and_can_be_changed(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user, 'sanctum')->getJson('/api/v1/me')->assertOk()
            ->assertJsonPath('data.temp_unit', 'c');
        $this->actingAs($user, 'sanctum')->patchJson('/api/v1/me/settings', ['temp_unit' => 'f'])->assertOk()
            ->assertJsonPath('data.temp_unit', 'f');
        $this->assertSame('f', $user->fresh()->temp_unit);
    }

    public function test_unknown_temp_unit_is_rejected(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user, 'sanctum')->patchJson('/api/v1/me/settings', ['temp_unit' => 'k'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('temp_unit');
        $this->assertSame('c', $user->fresh()->temp_unit);
    }
}
