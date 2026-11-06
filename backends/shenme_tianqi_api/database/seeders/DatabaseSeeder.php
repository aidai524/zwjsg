<?php

namespace Database\Seeders;

use App\Models\CareGroup;
use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        // 本地调试：两个人一个关心群，常驻城市北京和广州
        $me = User::factory()->create(['phone' => '13800000000', 'nickname' => '测试用户']);
        $mom = User::factory()->create(['phone' => '13800000001', 'nickname' => '妈妈']);
        $me->cities()->create(['location_id' => '101010100', 'name' => '北京', 'adm' => '北京市', 'is_home' => true]);
        $mom->cities()->create(['location_id' => '101280101', 'name' => '广州', 'adm' => '广东省', 'is_home' => true]);

        $group = CareGroup::create(['name' => '我们家', 'invite_code' => 'TESTHOME', 'owner_id' => $mom->id]);
        $group->members()->attach([$mom->id, $me->id]);
    }
}
