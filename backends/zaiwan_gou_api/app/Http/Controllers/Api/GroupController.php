<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DogGroup;
use App\Models\User;
use App\Services\GroupService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** 群组（原“狗群”）：建群、用邀请码加入、看群里每个人今天多狗、改群名、隐藏自己、退群 */
class GroupController extends Controller
{
    public function __construct(private GroupService $groups) {}

    public function index(Request $request): JsonResponse
    {
        $me = $request->user();
        $data = $me->dogGroups()->orderBy('dog_group_members.id')->get()
            ->map(fn (DogGroup $g) => $this->groups->payload($g, $me));

        return response()->json(['data' => $data]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate(['name' => ['required', 'string', 'max:16']]);
        $user = $request->user();
        $this->ensureGroupLimit($user);

        $group = DB::transaction(function () use ($data, $user) {
            $group = DogGroup::create([
                'name' => trim($data['name']),
                'invite_code' => DogGroup::newInviteCode(),
                'owner_id' => $user->id,
            ]);
            $group->members()->attach($user->id);

            return $group;
        });

        return response()->json(['data' => $this->groups->payload($group, $user)], 201);
    }

    /** 用邀请码加入。邀请码由群里的人用系统分享发出去，口头念也行 */
    public function join(Request $request): JsonResponse
    {
        $data = $request->validate(['invite_code' => ['required', 'string', 'max:12']]);
        $user = $request->user();

        $group = DogGroup::where('invite_code', strtoupper(trim($data['invite_code'])))->first()
            ?? throw ValidationException::withMessages(['invite_code' => '邀请码不对']);

        if (! $group->hasMember($user)) {
            $this->ensureGroupLimit($user);
            DB::transaction(function () use ($group, $user) {
                // 锁住群，防止并发加入超过人数上限
                DogGroup::whereKey($group->id)->lockForUpdate()->first();
                $max = config('dog.groups.max_members');
                if ($group->members()->count() >= $max) {
                    throw ValidationException::withMessages(['invite_code' => "这个群满了（最多 {$max} 人）"]);
                }
                $group->members()->attach($user->id);
            });
        }

        return response()->json(['data' => $this->groups->payload($group, $user)]);
    }

    public function show(Request $request, DogGroup $dogGroup): JsonResponse
    {
        abort_unless($dogGroup->hasMember($request->user()), 404);

        return response()->json(['data' => $this->groups->payload($dogGroup, $request->user())]);
    }

    public function update(Request $request, DogGroup $dogGroup): JsonResponse
    {
        abort_unless($dogGroup->hasMember($request->user()), 404);
        abort_unless($dogGroup->owner_id === $request->user()->id, 403, '只有群主能改群名');
        $data = $request->validate(['name' => ['required', 'string', 'max:16']]);
        $dogGroup->update(['name' => trim($data['name'])]);

        return response()->json(['data' => $this->groups->payload($dogGroup, $request->user())]);
    }

    /** 我在这个群里的设置：隐藏自己的狗度、关掉汪一下 */
    public function updateMe(Request $request, DogGroup $dogGroup): JsonResponse
    {
        $user = $request->user();
        abort_unless($dogGroup->hasMember($user), 404);
        $data = $request->validate([
            'hide_status' => ['sometimes', 'boolean'],
            'mute_nudges' => ['sometimes', 'boolean'],
        ]);
        if ($data !== []) {
            $dogGroup->members()->updateExistingPivot($user->id, $data);
        }

        return response()->json(['data' => $this->groups->payload($dogGroup, $user)]);
    }

    public function leave(Request $request, DogGroup $dogGroup): JsonResponse
    {
        abort_unless($dogGroup->hasMember($request->user()), 404);
        $this->groups->leave($dogGroup, $request->user());

        return response()->json(['left' => true]);
    }

    private function ensureGroupLimit(User $user): void
    {
        $max = config('dog.groups.max_groups_per_user');
        if ($user->dogGroups()->count() >= $max) {
            throw ValidationException::withMessages(['group' => "最多加入 {$max} 个群组"]);
        }
    }
}
