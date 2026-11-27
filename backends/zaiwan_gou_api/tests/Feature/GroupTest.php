<?php

namespace Tests\Feature;

use App\Models\DailyRecord;
use App\Models\DogGroup;
use App\Models\Nudge;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class GroupTest extends TestCase
{
    use RefreshDatabase;

    private function record(User $user, string $date, int $percent, ?string $breed = null): void
    {
        $stage = collect(config('dog.stage_thresholds'))->filter(fn ($t) => $percent >= $t)->count();
        DailyRecord::create([
            'user_id' => $user->id,
            'date' => $date,
            'dog_percent' => $percent,
            'stage' => $stage,
            'minutes_used' => (int) round($percent * 1.8),
            'breed_key' => $breed,
        ]);
    }

    /** 建一个群，owner 是群主，others 依次加入（进群时间放在 $joinedAt） */
    private function group(User $owner, array $others = [], ?string $joinedAt = null): DogGroup
    {
        $group = DogGroup::create(['name' => '宿舍狗窝', 'invite_code' => DogGroup::newInviteCode(), 'owner_id' => $owner->id]);
        $at = $joinedAt ? CarbonImmutable::parse($joinedAt) : now();
        $group->members()->attach($owner->id, ['created_at' => $at, 'updated_at' => $at]);
        foreach ($others as $u) {
            $group->members()->attach($u->id, ['created_at' => $at, 'updated_at' => $at]);
        }

        return $group;
    }

    private function day(User $user, int $daysAgo): string
    {
        return CarbonImmutable::parse($user->localToday())->subDays($daysAgo)->toDateString();
    }

    public function test_create_group_and_join_with_invite_code(): void
    {
        $owner = User::factory()->create(['nickname' => '阿强']);
        Sanctum::actingAs($owner);
        $res = $this->postJson('/api/v1/groups', ['name' => '  宿舍狗窝 '])->assertCreated();
        $res->assertJsonPath('data.name', '宿舍狗窝')
            ->assertJsonPath('data.is_owner', true)
            ->assertJsonPath('data.members.0.nickname', '阿强')
            ->assertJsonPath('data.members.0.is_me', true);
        $code = $res->json('data.invite_code');
        $this->assertSame(8, strlen($code));

        $friend = User::factory()->create(['nickname' => null]);
        Sanctum::actingAs($friend);
        $this->postJson('/api/v1/groups/join', ['invite_code' => 'nope'])->assertUnprocessable();
        $this->postJson('/api/v1/groups/join', ['invite_code' => strtolower($code)])
            ->assertOk()
            ->assertJsonPath('data.is_owner', false)
            ->assertJsonCount(2, 'data.members');
        // 再加一次不会重复
        $this->postJson('/api/v1/groups/join', ['invite_code' => $code])->assertOk()->assertJsonCount(2, 'data.members');

        Sanctum::actingAs($owner);
        $this->getJson('/api/v1/groups')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonFragment(['nickname' => '没起名的狗友']);
    }

    public function test_group_size_and_groups_per_user_are_limited(): void
    {
        $owner = User::factory()->create();
        $group = $this->group($owner, User::factory()->count(9)->create()->all());

        Sanctum::actingAs(User::factory()->create());
        $this->postJson('/api/v1/groups/join', ['invite_code' => $group->invite_code])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['invite_code']);

        $busy = User::factory()->create();
        Sanctum::actingAs($busy);
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/groups', ['name' => "群 $i"])->assertCreated();
        }
        $this->postJson('/api/v1/groups', ['name' => '第六个'])->assertUnprocessable()->assertJsonValidationErrors(['group']);
    }

    public function test_members_today_sorted_by_dog_percent_hidden_ones_last(): void
    {
        $me = User::factory()->create(['nickname' => '我']);
        $dog = User::factory()->create(['nickname' => '狗王候选']);
        $human = User::factory()->create(['nickname' => '还是人']);
        $shy = User::factory()->create(['nickname' => '害羞的']);
        $iphone = User::factory()->create(['nickname' => '用苹果的']);
        $group = $this->group($me, [$iphone, $human, $shy, $dog]);
        $group->members()->updateExistingPivot($shy->id, ['hide_status' => true]);

        $this->record($me, $me->localToday(), 72, 'corgi');
        $this->record($dog, $dog->localToday(), 140, 'husky');
        $this->record($human, $human->localToday(), 12);
        $this->record($shy, $shy->localToday(), 200, 'collie');

        Sanctum::actingAs($me);
        $res = $this->getJson("/api/v1/groups/{$group->id}")->assertOk();
        $this->assertSame(['狗王候选', '我', '还是人', '用苹果的', '害羞的'], array_column($res->json('data.members'), 'nickname'));
        $res->assertJsonPath('data.members.0.today', ['dog_percent' => 140, 'stage' => 4, 'breed_key' => 'husky'])
            ->assertJsonPath('data.members.3.today', null)
            ->assertJsonPath('data.members.4.hidden', true)
            ->assertJsonPath('data.members.4.today', null)
            ->assertJsonPath('data.team.today', ['human' => 1, 'dog' => 2, 'unknown' => 2]);

        // 隐藏了的自己看得到自己
        Sanctum::actingAs($shy);
        $mine = collect($this->getJson("/api/v1/groups/{$group->id}")->json('data.members'))->firstWhere('is_me', true);
        $this->assertSame(200, $mine['today']['dog_percent']);
    }

    public function test_group_payload_never_contains_phone_minutes_or_app_details(): void
    {
        $me = User::factory()->create();
        $friend = User::factory()->create(['phone' => '13800001234']);
        $group = $this->group($me, [$friend]);
        $this->record($friend, $friend->localToday(), 90);

        Sanctum::actingAs($me);
        $body = $this->getJson("/api/v1/groups/{$group->id}")->assertOk()->getContent();
        $this->assertStringNotContainsString('13800001234', $body);
        $this->assertStringNotContainsString('minutes_used', $body);
        $this->assertStringNotContainsString('phone', $body);
    }

    public function test_outsiders_cannot_see_group_and_only_owner_can_rename(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create();
        $group = $this->group($owner, [$member]);

        Sanctum::actingAs(User::factory()->create());
        $this->getJson("/api/v1/groups/{$group->id}")->assertNotFound();

        Sanctum::actingAs($member);
        $this->patchJson("/api/v1/groups/{$group->id}", ['name' => '改个名'])->assertForbidden();
        Sanctum::actingAs($owner);
        $this->patchJson("/api/v1/groups/{$group->id}", ['name' => '打工狗互助会'])->assertOk()->assertJsonPath('data.name', '打工狗互助会');
    }

    public function test_king_of_yesterday_skips_hidden_members_and_needs_someone_to_be_a_dog(): void
    {
        $me = User::factory()->create(['nickname' => '我']);
        $a = User::factory()->create(['nickname' => '阿狗']);
        $shy = User::factory()->create(['nickname' => '害羞的']);
        $group = $this->group($me, [$a, $shy]);
        $group->members()->updateExistingPivot($shy->id, ['hide_status' => true]);

        $this->record($me, $this->day($me, 1), 20);
        $this->record($a, $this->day($me, 1), 95, 'corgi');
        $this->record($shy, $this->day($me, 1), 160);

        Sanctum::actingAs($me);
        $this->getJson("/api/v1/groups/{$group->id}")
            ->assertJsonPath('data.king_yesterday.nickname', '阿狗')
            ->assertJsonPath('data.king_yesterday.dog_percent', 95)
            ->assertJsonPath('data.king_yesterday.breed_key', 'corgi')
            ->assertJsonPath('data.king_yesterday.date', $this->day($me, 1));

        // 前天大家都是人：没有狗王
        DailyRecord::query()->delete();
        $this->record($me, $this->day($me, 1), 20);
        $this->record($a, $this->day($me, 1), 10);
        $this->getJson("/api/v1/groups/{$group->id}")->assertJsonPath('data.king_yesterday', null);
    }

    public function test_team_streak_counts_days_everyone_sharing_stayed_human(): void
    {
        $me = User::factory()->create();
        $a = User::factory()->create();
        $iphone = User::factory()->create();
        $group = $this->group($me, [$a, $iphone], now()->subDays(20)->toDateTimeString());

        // 最近 3 天两人都是人，第 4 天 a 变狗；用 iPhone 的从来没上报，不算
        foreach ([1, 2, 3] as $d) {
            $this->record($me, $this->day($me, $d), 10);
            $this->record($a, $this->day($me, $d), 25);
        }
        $this->record($me, $this->day($me, 4), 10);
        $this->record($a, $this->day($me, 4), 80);

        Sanctum::actingAs($me);
        $this->getJson("/api/v1/groups/{$group->id}")
            ->assertJsonPath('data.team.streak', 3)
            ->assertJsonPath('data.team.best', 3)
            ->assertJsonPath('data.team.goal', 7);
        $this->assertSame(3, $group->fresh()->best_streak);

        // 昨天 a 没有记录：断了，但最好成绩还在
        DailyRecord::where('user_id', $a->id)->where('date', $this->day($me, 1))->delete();
        $this->getJson("/api/v1/groups/{$group->id}")
            ->assertJsonPath('data.team.streak', 0)
            ->assertJsonPath('data.team.best', 3);
    }

    public function test_new_member_only_counts_from_the_day_they_joined(): void
    {
        $me = User::factory()->create();
        $group = $this->group($me, [], now()->subDays(20)->toDateTimeString());
        foreach ([1, 2, 3] as $d) {
            $this->record($me, $this->day($me, $d), 10);
        }
        $late = User::factory()->create();
        $joined = CarbonImmutable::parse($this->day($me, 1).' 12:00:00', 'Asia/Shanghai')->utc();
        $group->members()->attach($late->id, ['created_at' => $joined, 'updated_at' => $joined]);
        $this->record($late, $this->day($me, 1), 20);

        Sanctum::actingAs($me);
        $this->getJson("/api/v1/groups/{$group->id}")->assertJsonPath('data.team.streak', 3);
    }

    public function test_hide_and_mute_settings_and_leaving(): void
    {
        $owner = User::factory()->create();
        $a = User::factory()->create();
        $b = User::factory()->create();
        $group = $this->group($owner, [$a, $b]);

        Sanctum::actingAs($a);
        $this->patchJson("/api/v1/groups/{$group->id}/me", ['hide_status' => true, 'mute_nudges' => true])
            ->assertOk()
            ->assertJsonPath('data.me', ['hide_status' => true, 'mute_nudges' => true]);

        // 群主退群：转给下一个进群的人
        Sanctum::actingAs($owner);
        $this->postJson("/api/v1/groups/{$group->id}/leave")->assertOk();
        $this->assertSame($a->id, $group->fresh()->owner_id);
        $this->getJson("/api/v1/groups/{$group->id}")->assertNotFound();

        Sanctum::actingAs($a);
        $this->postJson("/api/v1/groups/{$group->id}/leave")->assertOk();
        Sanctum::actingAs($b);
        $this->postJson("/api/v1/groups/{$group->id}/leave")->assertOk();
        $this->assertDatabaseMissing('dog_groups', ['id' => $group->id]);
    }

    public function test_nudge_twice_a_day_per_person_and_muted_ones_are_silent(): void
    {
        $me = User::factory()->create(['nickname' => '我']);
        $a = User::factory()->create();
        $muted = User::factory()->create();
        $group = $this->group($me, [$a, $muted]);
        $group->members()->updateExistingPivot($muted->id, ['mute_nudges' => true]);

        Sanctum::actingAs($me);
        $this->postJson("/api/v1/groups/{$group->id}/nudges", ['recipient_id' => $a->id])
            ->assertCreated()->assertJsonPath('nudges_left', 1);
        $this->postJson("/api/v1/groups/{$group->id}/nudges", ['recipient_id' => $a->id])
            ->assertCreated()->assertJsonPath('nudges_left', 0);
        $this->postJson("/api/v1/groups/{$group->id}/nudges", ['recipient_id' => $a->id])
            ->assertStatus(429)->assertJsonPath('message', '今天已经汪过 TA 2 次了，明天再说');
        $member = collect($this->getJson("/api/v1/groups/{$group->id}")->json('data.members'))->firstWhere('id', $a->id);
        $this->assertSame(0, $member['nudges_left']);

        // 对方关了汪一下：发的人看不出区别
        $this->postJson("/api/v1/groups/{$group->id}/nudges", ['recipient_id' => $muted->id])->assertCreated();
        $this->postJson("/api/v1/groups/{$group->id}/nudges", ['recipient_id' => $me->id])->assertUnprocessable();
        $this->postJson("/api/v1/groups/{$group->id}/nudges", ['recipient_id' => User::factory()->create()->id])
            ->assertUnprocessable();

        Sanctum::actingAs($muted);
        $this->getJson('/api/v1/nudges/inbox')->assertOk()->assertJsonCount(0, 'data');

        Sanctum::actingAs($a);
        $inbox = $this->getJson('/api/v1/nudges/inbox')->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.sender_nickname', '我')
            ->assertJsonPath('data.0.group_name', '宿舍狗窝');
        $this->postJson('/api/v1/nudges/seen', ['ids' => array_column($inbox->json('data'), 'id')])
            ->assertOk()->assertJsonPath('seen', 2);
        $this->getJson('/api/v1/nudges/inbox')->assertJsonCount(0, 'data');
    }

    public function test_old_nudges_are_pruned_after_30_days(): void
    {
        $me = User::factory()->create();
        $a = User::factory()->create();
        $group = $this->group($me, [$a]);
        $old = Nudge::create(['dog_group_id' => $group->id, 'sender_id' => $me->id, 'recipient_id' => $a->id]);
        $old->forceFill(['created_at' => now()->subDays(31)])->save();
        Nudge::create(['dog_group_id' => $group->id, 'sender_id' => $me->id, 'recipient_id' => $a->id]);

        $this->artisan('nudges:prune')->assertSuccessful();
        $this->assertDatabaseCount('nudges', 1);
    }

    public function test_deleting_account_leaves_groups_and_hands_over_ownership(): void
    {
        $owner = User::factory()->create();
        $a = User::factory()->create();
        $group = $this->group($owner, [$a]);
        $solo = $this->group($owner);

        Sanctum::actingAs($owner);
        $this->deleteJson('/api/v1/me')->assertOk();

        $this->assertSame($a->id, $group->fresh()->owner_id);
        $this->assertDatabaseMissing('dog_groups', ['id' => $solo->id]);
        $this->assertDatabaseMissing('dog_group_members', ['user_id' => $owner->id]);
    }
}
