<?php

namespace App\Services\Sms;

use Illuminate\Support\Facades\Log;

/**
 * 开发用：验证码只写进日志，不真的发短信。
 * 上线时新增阿里云或腾讯云短信的实现，并在 AppServiceProvider 里按 SMS_DRIVER 切换。
 */
class LogSmsSender implements SmsSender
{
    public function sendCode(string $phone, string $code): void
    {
        Log::info('[sms] 验证码', ['phone' => $phone, 'code' => $code]);
    }
}
