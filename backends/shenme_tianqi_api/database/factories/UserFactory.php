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
            'snark_level' => 1,
        ];
    }
}
