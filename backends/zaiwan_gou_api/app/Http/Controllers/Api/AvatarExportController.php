<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

/**
 * 把卡通形象一次性导出给系列里的其他 App（目前是“什么鬼天气”）。两个后端账号不互通，只复制一次图片：
 * 1. 用户在本 App 生成导出码：8 位，10 分钟内有效，只能用一次；
 * 2. 用户把码填进天气 App，天气的后端带着系列密钥来取图（redeem）。
 * 码只记着是谁的形象，取图时读那一刻的形象文件；取过一次就作废。只给卡通形象，不会有照片。
 */
class AvatarExportController extends Controller
{
    /** 去掉了容易看错的 0 1 I L O */
    public const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

    public const LENGTH = 8;

    public const TTL_MINUTES = 10;

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if (! $user->avatar_path) {
            throw ValidationException::withMessages(['avatar' => '还没有拍照形象，先在“我的 › 形象”里做一个']);
        }

        do {
            $code = self::newCode();
        } while (Cache::has(self::cacheKey($code)));
        $expiresAt = now()->addMinutes(self::TTL_MINUTES);
        Cache::put(self::cacheKey($code), $user->id, $expiresAt);

        return response()->json(['data' => ['code' => $code, 'expires_at' => $expiresAt->toIso8601String()]], 201);
    }

    /** 给系列里其他 App 的后端调：请求头带 X-Series-Key，用导出码换一次形象图片 */
    public function redeem(Request $request): Response|JsonResponse
    {
        $secret = (string) config('services.series.export_key');
        abort_if($secret === '', 503, '导出还没开通');
        abort_unless(hash_equals($secret, (string) $request->header('X-Series-Key')), 403);

        $code = self::normalize((string) $request->input('code'));
        $userId = $code === null ? null : Cache::pull(self::cacheKey($code));
        $user = $userId ? User::find($userId) : null;
        $disk = Storage::disk(config('filesystems.avatar_disk'));
        if (! $user?->avatar_path || ! $disk->exists($user->avatar_path)) {
            return response()->json(['message' => '导出码不对或已经过期'], 404);
        }

        return response($disk->get($user->avatar_path), 200, [
            'Content-Type' => $disk->mimeType($user->avatar_path) ?: 'image/png',
            'Cache-Control' => 'no-store',
        ]);
    }

    public static function newCode(): string
    {
        $code = '';
        for ($i = 0; $i < self::LENGTH; $i++) {
            $code .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
        }

        return $code;
    }

    /** 不管大小写、空格和连字符；格式不对返回 null */
    public static function normalize(string $input): ?string
    {
        $code = strtoupper((string) preg_replace('/[\s\-]/', '', $input));

        return preg_match('/^['.self::ALPHABET.']{'.self::LENGTH.'}$/', $code) === 1 ? $code : null;
    }

    private static function cacheKey(string $code): string
    {
        return 'avatar-export:'.$code;
    }
}
