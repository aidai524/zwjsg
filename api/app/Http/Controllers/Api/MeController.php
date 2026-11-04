<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
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
        $goal = config('dog.goal_minutes');

        $data = $request->validate([
            'nickname' => ['sometimes', 'nullable', 'string', 'max:16'],
            'timezone' => ['sometimes', 'timezone:all'],
            'daily_goal_minutes' => ['sometimes', 'integer', "min:{$goal['min']}", "max:{$goal['max']}"],
            'remind_at' => ['sometimes', 'date_format:H:i'],
        ]);

        $request->user()->update($data);

        return new UserResource($request->user()->fresh());
    }

    /** 注销：删除账号、所有记录和卡通形象文件 */
    public function destroy(Request $request): JsonResponse
    {
        $user = $request->user();

        DB::transaction(function () use ($user) {
            if ($user->avatar_path) {
                Storage::disk(config('filesystems.avatar_disk'))->delete($user->avatar_path);
            }
            $user->tokens()->delete();
            $user->delete(); // daily_records、user_breeds 级联删除
        });

        return response()->json(['deleted' => true]);
    }
}
