<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * 只接收手机端已经生成好的卡通形象，不接收原始照片。
 */
class AvatarController extends Controller
{
    public function store(Request $request): UserResource
    {
        $request->validate([
            'avatar' => ['required', 'image', 'mimes:png,webp', 'max:1024', 'dimensions:max_width=1024,max_height=1024'],
        ]);

        $user = $request->user();
        $isReplace = (bool) $user->avatar_path;

        if ($isReplace && $user->avatar_regen_left <= 0) {
            throw ValidationException::withMessages(['avatar' => '重新生成次数用完了']);
        }

        $disk = Storage::disk(config('filesystems.avatar_disk'));
        $path = $request->file('avatar')->store('avatars/'.$user->id, ['disk' => config('filesystems.avatar_disk')]);

        if ($isReplace) {
            $disk->delete($user->avatar_path);
            $user->avatar_regen_left--;
        }

        $user->avatar_path = $path;
        $user->save();

        return new UserResource($user);
    }
}
