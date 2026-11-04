<?php

namespace App\Providers;

use App\Services\Sms\LogSmsSender;
use App\Services\Sms\SmsSender;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // TODO 上线前：按 SMS_DRIVER 切换到阿里云或腾讯云短信实现
        $this->app->bind(SmsSender::class, LogSmsSender::class);
    }

    public function boot(): void
    {
        // 同一手机号 1 分钟 1 次、同一 IP 1 小时 20 次
        RateLimiter::for('sms', function (Request $request) {
            return [
                Limit::perMinute(1)->by('sms-phone:'.$request->input('phone')),
                Limit::perHour(20)->by('sms-ip:'.$request->ip()),
            ];
        });

        RateLimiter::for('api', function (Request $request) {
            return Limit::perMinute(120)->by($request->user()?->id ?: $request->ip());
        });
    }
}
