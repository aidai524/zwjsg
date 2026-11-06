<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\CareGroup;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class MeController extends Controller
{
    public function show(Request $request): UserResource
    {
        return new UserResource($request->user()->load('homeCity'));
    }

    public function updateSettings(Request $request): UserResource
    {
        $data = $request->validate([
            'nickname' => ['sometimes', 'nullable', 'string', 'max:16'],
            'timezone' => ['sometimes', 'timezone:all'],
            'snark_level' => ['sometimes', 'integer', 'in:0,1,2'],
            'morning_push_on' => ['sometimes', 'boolean'],
            'morning_push_weekday' => ['sometimes', 'date_format:H:i'],
            'morning_push_weekend' => ['sometimes', 'date_format:H:i'],
            'alert_push_on' => ['sometimes', 'boolean'],
            'push_token' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $request->user()->update($data);

        return new UserResource($request->user()->fresh()->load('homeCity'));
    }

    /** 注销：删除账号、城市、群成员关系、提醒记录和卡通形象文件 */
    public function destroy(Request $request): JsonResponse
    {
        $user = $request->user();

        DB::transaction(function () use ($user) {
            if ($user->avatar_path) {
                Storage::disk(config('filesystems.avatar_disk'))->delete($user->avatar_path);
            }
            // 自己建的群：转给最早加入的成员，没人了才解散，不连累其他人
            foreach (CareGroup::where('owner_id', $user->id)->get() as $group) {
                $next = $group->members()->whereKeyNot($user->id)->orderBy('care_group_members.id')->first();
                $next ? $group->update(['owner_id' => $next->id]) : $group->delete();
            }
            $user->tokens()->delete();
            $user->delete(); // user_cities、care_group_members、reminders、mutes 级联删除
        });

        return response()->json(['deleted' => true]);
    }
}
