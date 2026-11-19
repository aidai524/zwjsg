<?php

namespace Series\Auth\Sms;

use Illuminate\Support\Facades\Log;

/**
 * 按配置（两个后端的 config/services.php 里的 sms）选短信发送器：
 * - log：开发用，验证码只写进日志；生产环境（APP_ENV=production）拒绝发码，免得线上悄悄只写日志
 * - aliyun：阿里云短信
 */
final class SmsSenders
{
    public static function fromConfig(array $config, bool $production): SmsSender
    {
        $driver = $config['driver'] ?? 'log';
        if ($driver === 'aliyun') {
            $c = $config['aliyun'] ?? [];

            return new AliyunSmsSender(
                $c['access_key_id'] ?? null,
                $c['access_key_secret'] ?? null,
                $c['sign_name'] ?? null,
                $c['template_code'] ?? null,
                $c['template_param'] ?? 'code',
                $c['endpoint'] ?? 'dysmsapi.aliyuncs.com',
            );
        }
        if ($driver !== 'log') {
            Log::error("[sms] 不认识的短信驱动 {$driver}，只支持 log 和 aliyun");
        }

        return new LogSmsSender(refuse: $production || $driver !== 'log');
    }
}
