<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use Series\Auth\SmsCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    private const PHONE_RULE = ['required', 'string', 'regex:/^1[3-9]\d{9}$/'];

    public function __construct(private SmsCodeService $codes) {}

    public function sendSms(Request $request): JsonResponse
    {
        $data = $request->validate(['phone' => self::PHONE_RULE]);

        $this->codes->send($data['phone']);

        return response()->json(['sent' => true]);
    }

    public function smsLogin(Request $request): JsonResponse
    {
        $data = $request->validate([
            'phone' => self::PHONE_RULE,
            'code' => ['required', 'digits:6'],
            'timezone' => ['nullable', 'timezone:all'],
            'device_name' => ['nullable', 'string', 'max:64'],
        ]);

        if (! $this->codes->verify($data['phone'], $data['code'])) {
            throw ValidationException::withMessages(['code' => '验证码不对或已过期']);
        }

        $user = User::firstOrCreate(
            ['phone' => $data['phone']],
            [
                'timezone' => $data['timezone'] ?? 'Asia/Shanghai',
                'avatar_regen_left' => config('dog.avatar_regen_default'),
            ],
        );

        if ($user->wasRecentlyCreated) {
            $user->refresh(); // 读回数据库默认值（每日目标、提醒时间等）
        }

        $token = $user->createToken($data['device_name'] ?? 'app')->plainTextToken;

        return response()->json([
            'token' => $token,
            'is_new' => $user->wasRecentlyCreated,
            'user' => new UserResource($user),
        ]);
    }

    /** 微信登录：需要在开放平台申请移动应用并配置 AppID/AppSecret 后实现 */
    public function wechatLogin(): JsonResponse
    {
        return response()->json(['message' => '微信登录尚未配置'], 501);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['ok' => true]);
    }
}
