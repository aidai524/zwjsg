<?php

namespace Database\Factories;

use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    public function definition(): array
    {
        return [
            'phone' => '13'.fake()->unique()->numerify('#########'),
            'nickname' => fake()->firstName(),
            'timezone' => 'Asia/Shanghai',
            'daily_goal_minutes' => 180,
            'remind_at' => '22:00:00',
            'avatar_regen_left' => 3,
        ];
    }
}
