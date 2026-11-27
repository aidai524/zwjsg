<?php

namespace Tests\Feature;

use App\Models\DailyRecord;
use App\Models\DogGroup;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** 预设形象（2026-11-27：不做捏脸，预设几张捏好的脸给用户挑） */
class AvatarPresetTest extends TestCase
{
    use RefreshDatabase;

    /** 1x1 的 PNG */
    private const PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake(config('filesystems.avatar_disk'));
    }

    private function withPhoto(User $user): User
    {
        $path = "avatars/{$user->id}/sticker.png";
        Storage::disk(config('filesystems.avatar_disk'))->put($path, base64_decode(self::PNG_BASE64));
        $user->forceFill(['avatar_path' => $path])->save();

        return $user;
    }

    public function test_preset_is_one_of_the_known_names_and_null_switches_back_to_the_photo(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/me')->assertOk()->assertJsonPath('data.avatar_preset', null);
        $this->patchJson('/api/v1/me/settings', ['avatar_preset' => 'curly'])
            ->assertOk()
            ->assertJsonPath('data.avatar_preset', 'curly');
        $this->patchJson('/api/v1/me/settings', ['avatar_preset' => 'mohawk'])->assertStatus(422);
        $this->patchJson('/api/v1/me/settings', ['avatar_preset' => 'curly; drop table users'])->assertStatus(422);
        $this->getJson('/api/v1/me')->assertJsonPath('data.avatar_preset', 'curly');

        $this->patchJson('/api/v1/me/settings', ['avatar_preset' => null])
            ->assertOk()
            ->assertJsonPath('data.avatar_preset', null);
    }

    public function test_uploading_a_new_photo_avatar_switches_back_to_it(): void
    {
        $user = $this->withPhoto(User::factory()->create(['avatar_preset' => 'bun']));
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/me')
            ->assertJsonPath('data.avatar_preset', 'bun')
            // 自己的拍照形象照样给：换手机后还能换回来
            ->assertJsonPath('data.avatar_url', fn ($url) => is_string($url) && $url !== '');

        $png = UploadedFile::fake()->createWithContent('sticker.png', base64_decode(self::PNG_BASE64));
        $this->post('/api/v1/me/avatar', ['avatar' => $png], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('data.avatar_preset', null);
        $this->assertNull($user->fresh()->avatar_preset);
    }

    public function test_group_shows_the_preset_and_hides_the_photo_of_members_using_one(): void
    {
        $me = User::factory()->create(['nickname' => '我']);
        $preset = $this->withPhoto(User::factory()->create(['nickname' => '用预设的', 'avatar_preset' => 'bob']));
        $photo = $this->withPhoto(User::factory()->create(['nickname' => '用照片的']));
        $group = DogGroup::create(['name' => '宿舍狗窝', 'invite_code' => DogGroup::newInviteCode(), 'owner_id' => $me->id]);
        foreach ([$me, $preset, $photo] as $u) {
            $group->members()->attach($u->id);
        }
        // 昨天的狗王是用预设形象的那位
        $yesterday = CarbonImmutable::parse($me->localToday())->subDay()->toDateString();
        DailyRecord::create(['user_id' => $preset->id, 'date' => $yesterday, 'dog_percent' => 140, 'stage' => 4, 'minutes_used' => 250]);

        Sanctum::actingAs($me);
        $res = $this->getJson("/api/v1/groups/{$group->id}")->assertOk();
        $members = collect($res->json('data.members'))->keyBy('nickname');
        $this->assertSame('bob', $members['用预设的']['avatar_preset']);
        $this->assertNull($members['用预设的']['avatar_url']);
        $this->assertNull($members['用照片的']['avatar_preset']);
        $this->assertNotEmpty($members['用照片的']['avatar_url']);
        $this->assertNull($members['我']['avatar_preset']);
        $this->assertNull($members['我']['avatar_url']);
        $res->assertJsonPath('data.king_yesterday.nickname', '用预设的')
            ->assertJsonPath('data.king_yesterday.avatar_preset', 'bob')
            ->assertJsonPath('data.king_yesterday.avatar_url', null);
    }
}
