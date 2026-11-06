<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CareGroup;
use App\Models\Reminder;
use App\Models\User;
use App\Services\CareService;
use App\Services\WeatherInterpreter;
use App\Services\WeatherService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CareGroupController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $groups = $request->user()->careGroups()->withCount('members')->get()
            ->map(fn (CareGroup $g) => [
                'id' => $g->id,
                'name' => $g->name,
                'members_count' => $g->members_count,
                'is_owner' => $g->owner_id === $request->user()->id,
            ]);

        return response()->json(['data' => $groups]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate(['name' => ['required', 'string', 'max:16']]);
        $user = $request->user();
        $this->ensureGroupLimit($user);

        $group = DB::transaction(function () use ($data, $user) {
            $group = CareGroup::create([
                'name' => $data['name'],
                'invite_code' => CareGroup::newInviteCode(),
                'owner_id' => $user->id,
            ]);
            $group->members()->attach($user->id);

            return $group;
        });

        return response()->json(['data' => $this->groupPayload($group, $user)], 201);
    }

    /** 用邀请码加入。邀请码由群主分享（微信），口头念也行 */
    public function join(Request $request): JsonResponse
    {
        $data = $request->validate(['invite_code' => ['required', 'string', 'max:12']]);
        $user = $request->user();

        $group = CareGroup::where('invite_code', strtoupper(trim($data['invite_code'])))->first()
            ?? throw ValidationException::withMessages(['invite_code' => '邀请码不对']);

        if (! $group->hasMember($user)) {
            $this->ensureGroupLimit($user);
            DB::transaction(function () use ($group, $user) {
                // 锁住群，防止并发加入超过人数上限
                CareGroup::whereKey($group->id)->lockForUpdate()->first();
                if ($group->members()->count() >= config('weather.care.max_members')) {
                    throw ValidationException::withMessages(['invite_code' => '这个群满了（最多 '.config('weather.care.max_members').' 人）']);
                }
                $group->members()->attach($user->id);
            });
        }

        return response()->json(['data' => $this->groupPayload($group, $user)]);
    }

    public function show(Request $request, CareGroup $careGroup): JsonResponse
    {
        abort_unless($careGroup->hasMember($request->user()), 404);

        return response()->json(['data' => $this->groupPayload($careGroup, $request->user(), withWeather: true)]);
    }

    public function update(Request $request, CareGroup $careGroup): JsonResponse
    {
        abort_unless($careGroup->owner_id === $request->user()->id, 403, '只有群主能改群名');
        $careGroup->update($request->validate(['name' => ['required', 'string', 'max:16']]));

        return response()->json(['data' => $this->groupPayload($careGroup, $request->user())]);
    }

    /** 退群；群主退出时转给最早加入的人，没人了就解散 */
    public function leave(Request $request, CareGroup $careGroup): JsonResponse
    {
        $user = $request->user();
        abort_unless($careGroup->hasMember($user), 404);

        DB::transaction(function () use ($careGroup, $user) {
            $careGroup->members()->detach($user->id);
            $next = $careGroup->members()->orderBy('care_group_members.id')->first();

            if (! $next) {
                $careGroup->delete();
            } elseif ($careGroup->owner_id === $user->id) {
                $careGroup->update(['owner_id' => $next->id]);
            }
        });

        return response()->json(['left' => true]);
    }

    private function ensureGroupLimit(User $user): void
    {
        $max = config('weather.care.max_groups_per_user');
        if ($user->careGroups()->count() >= $max) {
            throw ValidationException::withMessages(['group' => "最多加入 {$max} 个关心群"]);
        }
    }

    private function groupPayload(CareGroup $group, User $me, bool $withWeather = false): array
    {
        $care = app(CareService::class);
        $members = $group->members()->with('homeCity')->orderBy('care_group_members.id')->get();

        $payload = [
            'id' => $group->id,
            'name' => $group->name,
            'invite_code' => $group->invite_code,
            'is_owner' => $group->owner_id === $me->id,
            'max_members' => config('weather.care.max_members'),
        ];

        $payload['members'] = $members->map(function (User $m) use ($me, $care, $withWeather) {
            $row = [
                'id' => $m->id,
                'nickname' => $m->displayName(),
                'avatar_url' => $m->avatarUrl(),
                'is_me' => $m->is($me),
                // 只给城市名，不给更细的位置
                'city' => $m->homeCity?->name,
                'remaining_today' => $m->is($me) ? null : $care->remainingToday($me, $m),
                // TA 最近一次对我的提醒点了“收到”（静音的不算）
                'last_ack_at' => $m->is($me) ? null : Reminder::where('sender_id', $me->id)
                    ->where('recipient_id', $m->id)->where('suppressed', false)
                    ->whereNotNull('acked_at')->latest('acked_at')->value('acked_at'),
            ];
            if ($withWeather) {
                $row['weather'] = $this->memberWeather($m);
            }

            return $row;
        })->all();

        if ($withWeather) {
            // 我今天在这个群发出的提醒和状态
            $payload['sent_today'] = Reminder::where('care_group_id', $group->id)
                ->where('sender_id', $me->id)
                ->where('created_at', '>=', now()->subDay())
                ->latest('id')->get()
                ->map(fn (Reminder $r) => [
                    'id' => $r->id,
                    'recipient_id' => $r->recipient_id,
                    'text' => $r->text,
                    'status' => CareService::senderStatus($r),
                    'deliver_at' => $r->deliver_at->toIso8601String(),
                ])->all();
        }

        return $payload;
    }

    private function memberWeather(User $m): ?array
    {
        if (! $m->homeCity) {
            return null;
        }

        try {
            $snap = app(WeatherService::class)->snapshot($m->homeCity->location_id);
        } catch (\RuntimeException) {
            return null;
        }
        $view = app(WeatherInterpreter::class)->interpret($snap, $m->homeCity->adm);

        return WeatherController::summary($snap, $view);
    }
}
