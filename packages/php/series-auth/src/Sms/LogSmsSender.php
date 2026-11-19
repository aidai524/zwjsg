<?php

namespace Series\Auth\Sms;

use Illuminate\Support\Facades\Log;

/**
 * 开发用：验证码只写进日志，不真的发短信。
 * 生产环境（或者驱动名写错了）时 [refuse] 为 true：不写日志、直接报“短信服务还没配置好”，
 * 免得上线后验证码躺在日志里、用户却收不到。上线用阿里云：SMS_DRIVER=aliyun，见 README。
 */
class LogSmsSender implements SmsSender
{
    public function __construct(private bool $refuse = false) {}

    public function sendCode(string $phone, string $code): void
    {
        if ($this->refuse) {
            Log::error('[sms] 生产环境还在用 log 驱动（或驱动名写错了），验证码没发。设置 SMS_DRIVER=aliyun 并填好阿里云配置');
            throw new SmsSendException('短信服务还没配置好，暂时登录不了', 503);
        }
        Log::info('[sms] 验证码', ['phone' => $phone, 'code' => $code]);
    }
}
