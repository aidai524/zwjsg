<?php

namespace Tests\Feature;

use App\Models\CareGroup;
use App\Models\Reminder;
use App\Models\User;
use App\Services\CareService;
use App\Services\Push\PushGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\Support\RecordingPushGateway;
use Tests\TestCase;

class CareTest extends TestCase
{
    use RefreshDatabase;

    private RecordingPushGateway $push;

    protected function setUp(): void
    {
        parent::setUp();
        $this->push = new RecordingPushGateway;
        $this->app->instance(PushGateway::class, $this->push);
        // 北京时间下午 3 点，不在夜间免打扰时段
        Carbon::setTestNow('2026-11-06 07:00:00'); // UTC
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** @return array{0:CareGroup, 1:User, 2:User, 3:User} 妈妈建群，爸爸和我加入 */
    private function family(): array
    {
        $mom = User::factory()->create(['nickname' => '妈妈']);
        $dad = User::factory()->create(['nickname' => '爸爸']);
        $me = User::factory()->create(['nickname' => '我']);

        $group = CareGroup::create(['name' => '我们家', 'invite_code' => CareGroup::newInviteCode(), 'owner_id' => $mom->id]);
        $group->members()->attach([$mom->id, $dad->id, $me->id]);

        return [$group, $mom, $dad, $me];
    }

    private function remind(User $from, CareGroup $g, User $to, string $key = 'rain_umbrella')
    {
        return $this->actingAs($from, 'sanctum')->postJson('/api/v1/reminders', [
            'care_group_id' => $g->id, 'recipient_id' => $to->id, 'phrase_key' => $key,
        ]);
    }

    public function test_create_and_join_group_with_invite_code(): void
    {
        $owner = User::factory()->create();
        $code = $this->actingAs($owner, 'sanctum')->postJson('/api/v1/care-groups', ['name' => '我们家'])
            ->assertCreated()->json('data.invite_code');

        $other = User::factory()->create();
        $this->actingAs($other, 'sanctum')->postJson('/api/v1/care-groups/join', ['invite_code' => strtolower($code)])
            ->assertOk()->assertJsonCount(2, 'data.members');

        $this->postJson('/api/v1/care-groups/join', ['invite_code' => 'NOPE1234'])->assertStatus(422);
    }

    public function test_group_is_capped_at_eight_members(): void
    {
        $owner = User::factory()->create();
        $group = CareGroup::create(['name' => 'g', 'invite_code' => 'ABCDEFGH', 'owner_id' => $owner->id]);
        $group->members()->attach(User::factory()->count(8)->create()->pluck('id'));

        $this->actingAs(User::factory()->create(), 'sanctum')
            ->postJson('/api/v1/care-groups/join', ['invite_code' => 'ABCDEFGH'])->assertStatus(422);
    }

    public function test_reminder_is_pushed_and_capped_at_two_per_day(): void
    {
        [$g, $mom, , $me] = $this->family();

        $this->remind($mom, $g, $me, 'rain_umbrella')->assertCreated()
            ->assertJsonPath('data.status', 'delivered')
            ->assertJsonPath('data.remaining_today', 1);
        $this->assertSame('妈妈提醒你', $this->push->to($me)[0]['title']);

        $this->remind($mom, $g, $me, 'cold_coat')->assertCreated()->assertJsonPath('data.remaining_today', 0);
        $this->remind($mom, $g, $me, 'hot_water')->assertStatus(429);
        $this->assertCount(2, $this->push->to($me));
    }

    public function test_same_sender_same_topic_within_30_minutes_is_not_counted_twice(): void
    {
        [$g, $mom, , $me] = $this->family();

        $first = $this->remind($mom, $g, $me, 'rain_umbrella')->json('data.id');
        $second = $this->remind($mom, $g, $me, 'rain_early')->json('data.id');

        $this->assertSame($first, $second);
        $this->assertSame(1, Reminder::count());
        $this->assertCount(1, $this->push->to($me));
    }

    public function test_reminders_from_two_people_merge_into_one_push(): void
    {
        [$g, $mom, $dad, $me] = $this->family();
        $me->update(['timezone' => 'Asia/Shanghai']);

        // 晚上 23 点（北京时间）发，两条都延迟到早上 7 点
        Carbon::setTestNow('2026-11-06 15:00:00');
        $this->remind($mom, $g, $me)->assertJsonPath('data.status', 'scheduled');
        $this->remind($dad, $g, $me)->assertJsonPath('data.status', 'scheduled');
        $this->assertCount(0, $this->push->to($me));

        // 第二天 07:00 北京时间 = 前一天 23:00 UTC
        Carbon::setTestNow('2026-11-06 23:00:00');
        $this->artisan('care:deliver')->assertSuccessful();

        $pushes = $this->push->to($me);
        $this->assertCount(1, $pushes);
        $this->assertSame('妈妈、爸爸提醒你', $pushes[0]['title']);
        $this->assertSame(0, Reminder::whereNull('delivered_at')->count());
    }

    public function test_quiet_hours_defer_to_seven_but_alerts_go_now(): void
    {
        $care = app(CareService::class);
        $user = User::factory()->make(['timezone' => 'Asia/Shanghai']);

        $late = Carbon::parse('2026-11-06 15:30:00', 'UTC')->toImmutable(); // 北京 23:30
        $this->assertSame('2026-11-06 23:00:00', $care->deliverAt($user, 'rain', $late)->format('Y-m-d H:i:s'));

        $early = Carbon::parse('2026-11-06 20:00:00', 'UTC')->toImmutable(); // 北京 04:00
        $this->assertSame('2026-11-06 23:00:00', $care->deliverAt($user, 'rain', $early)->format('Y-m-d H:i:s'));

        $this->assertTrue($care->deliverAt($user, 'alert', $late)->eq($late));
    }

    public function test_muted_sender_sees_delivered_but_nothing_is_pushed(): void
    {
        [$g, $mom, , $me] = $this->family();
        $this->actingAs($me, 'sanctum')->postJson('/api/v1/mutes', ['muted_user_id' => $mom->id])->assertCreated();

        $this->remind($mom, $g, $me)->assertCreated()->assertJsonPath('data.status', 'delivered');
        $this->assertCount(0, $this->push->to($me));

        $this->actingAs($me, 'sanctum')->getJson('/api/v1/reminders/inbox')->assertJsonCount(0, 'data');
    }

    public function test_ack_notifies_every_merged_sender(): void
    {
        [$g, $mom, $dad, $me] = $this->family();
        Carbon::setTestNow('2026-11-06 15:00:00'); // 北京 23:00，先排队，好合并
        $id = $this->remind($mom, $g, $me)->json('data.id');
        $this->remind($dad, $g, $me);
        Carbon::setTestNow('2026-11-06 23:00:00');
        app(CareService::class)->deliverDue();

        $this->actingAs($me, 'sanctum')->postJson("/api/v1/reminders/$id/ack")->assertOk();

        $this->assertSame('我 收到了 ♥', $this->push->to($mom)[0]['title']);
        $this->assertSame('我 收到了 ♥', $this->push->to($dad)[0]['title']);
        $this->assertSame(0, Reminder::whereNull('acked_at')->count());
    }

    public function test_only_group_members_can_remind_and_only_preset_phrases(): void
    {
        [$g, $mom] = $this->family();
        $stranger = User::factory()->create();

        $this->remind($mom, $g, $stranger)->assertForbidden();
        $this->remind($stranger, $g, $mom)->assertForbidden();
        $this->remind($mom, $g, $mom)->assertStatus(422);
        $this->remind($mom, $g, User::find($g->members()->whereKeyNot($mom->id)->value('users.id')), 'free_text')->assertStatus(422);
    }

    public function test_owner_leaving_transfers_group_and_last_member_deletes_it(): void
    {
        [$g, $mom, $dad, $me] = $this->family();

        $this->actingAs($mom, 'sanctum')->postJson("/api/v1/care-groups/{$g->id}/leave")->assertOk();
        $this->assertSame($dad->id, $g->fresh()->owner_id);

        $this->actingAs($dad, 'sanctum')->postJson("/api/v1/care-groups/{$g->id}/leave")->assertOk();
        $this->actingAs($me, 'sanctum')->postJson("/api/v1/care-groups/{$g->id}/leave")->assertOk();
        $this->assertNull(CareGroup::find($g->id));
    }

    public function test_reminders_older_than_30_days_are_pruned(): void
    {
        [$g, $mom, , $me] = $this->family();
        $this->remind($mom, $g, $me);

        Carbon::setTestNow(now()->addDays(31));
        $this->artisan('care:prune')->assertSuccessful();
        $this->assertSame(0, Reminder::count());
    }
}
