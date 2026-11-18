<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * 只接收卡通形象，不接收原始照片。形象从“再玩我是狗”一次性导入：
 * 狗 App 生成导出码 → 用户填进本 App → import() 凭码向狗后端取一次图，原样交给 App →
 * App 存在手机上，登录后用 store() 传上来（关心群里的家人能看到）。两个后端账号独立，导入只复制图片，不关联账号。
 */
class AvatarController extends Controller
{
    /** 和狗后端 AvatarExportController 的导出码一样：8 位，去掉了容易看错的 0 1 I L O */
    private const CODE = '/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/';

    private const UNREACHABLE = '暂时连不上“再玩我是狗”，稍后再试';

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

    /** 用回默认形象：删掉服务端存的卡通形象 */
    public function destroy(Request $request): UserResource
    {
        $user = $request->user();
        if ($user->avatar_path) {
            Storage::disk(config('filesystems.avatar_disk'))->delete($user->avatar_path);
            $user->avatar_path = null;
            $user->save();
        }

        return new UserResource($user);
    }

    /** 凭“再玩我是狗”的导出码取一次卡通形象（PNG，base64），不登录也能用；这里不保存 */
    public function import(Request $request): JsonResponse
    {
        $request->validate(['code' => ['required', 'string', 'max:32']]);
        $code = strtoupper((string) preg_replace('/[\s\-]/', '', $request->input('code')));
        if (preg_match(self::CODE, $code) !== 1) {
            throw ValidationException::withMessages(['code' => '导出码是 8 位字母和数字，再核对一下']);
        }

        $base = rtrim((string) config('services.gou.api_base'), '/');
        $key = (string) config('services.series.export_key');
        abort_if($base === '' || $key === '', 503, '导入还没开通');

        try {
            $res = Http::withHeaders(['X-Series-Key' => $key])
                ->acceptJson()
                ->timeout(config('services.gou.timeout'))
                ->post($base.'/avatar-exports/redeem', ['code' => $code]);
        } catch (ConnectionException) {
            abort(503, self::UNREACHABLE);
        }

        if ($res->notFound()) {
            throw ValidationException::withMessages(['code' => '导出码不对或已经过期，回“再玩我是狗”重新生成一个']);
        }
        abort_unless($res->successful(), 503, self::UNREACHABLE);

        // 只认 1MB、1024 像素以内的 PNG，和 store() 收的一样
        $png = $res->body();
        $info = strlen($png) <= 1024 * 1024 ? @getimagesizefromstring($png) : false;
        abort_unless(
            $info !== false && $info[2] === IMAGETYPE_PNG && $info[0] <= 1024 && $info[1] <= 1024,
            502,
            '“再玩我是狗”给的形象格式不对',
        );

        return response()->json(['data' => ['png' => base64_encode($png)]]);
    }
}
