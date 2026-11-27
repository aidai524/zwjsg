<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\GroupService;
use App\Http\Resources\UserResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class MeController extends Controller
{
    public function show(Request $request): UserResource
    {
        return new UserResource($request->user());
    }

    public function updateSettings(Request $request): UserResource
    {
        $tiers = implode(',', config('dog.goal_tiers'));
        $presets = implode(',', config('dog.avatar_presets'));

        $data = $request->validate([
            'nickname' => ['sometimes', 'nullable', 'string', 'max:16'],
            'timezone' => ['sometimes', 'timezone:all'],
            // 目标只能是三档之一
            'daily_goal_minutes' => ['sometimes', 'integer', "in:{$tiers}"],
            'remind_at' => ['sometimes', 'date_format:H:i'],
            // 挑了哪张预设形象；null 是换回拍照形象
            'avatar_preset' => ['sometimes', 'nullable', 'string', "in:{$presets}"],
        ]);

        $request->user()->update($data);

        return new UserResource($request->user()->fresh());
    }

    /** 注销：删除账号、所有记录和卡通形象文件 */
    public function destroy(Request $request): JsonResponse
    {
        $user = $request->user();

        DB::transaction(function () use ($user) {
            // 先退出所有群组：自己是群主的转给下一个人，没人了就解散
            $groups = app(GroupService::class);
            foreach ($user->dogGroups()->get() as $group) {
                $groups->leave($group, $user);
            }
            if ($user->avatar_path) {
                Storage::disk(config('filesystems.avatar_disk'))->delete($user->avatar_path);
            }
            $user->tokens()->delete();
            $user->delete(); // daily_records、user_breeds 级联删除
        });

        return response()->json(['deleted' => true]);
    }
}
