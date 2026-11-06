<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * 只接收手机端已经生成好的卡通形象，不接收原始照片。
 * TODO 从“再玩我是狗”一次性导入：狗 App 生成短时导出码 → 本接口用导出码向狗后端取图。
 * 两个后端账号独立，导入只复制图片，不关联账号。
 */
class AvatarController extends Controller
{
    public function store(Request $request): UserResource
    {
        $request->validate([
            'avatar' => ['required', 'image', 'mimes:png,webp', 'max:1024', 'dimensions:max_width=1024,max_height=1024'],
        ]);

        $user = $request->user();
        $diskName = config('filesystems.avatar_disk');
        $path = $request->file('avatar')->store('avatars/'.$user->id, ['disk' => $diskName]);

        if ($user->avatar_path) {
            Storage::disk($diskName)->delete($user->avatar_path);
        }

        $user->avatar_path = $path;
        $user->save();

        return new UserResource($user);
    }
}
