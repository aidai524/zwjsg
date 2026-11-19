<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** 狗后端也按 SMS_DRIVER 选短信发送器（实现在 series-auth 包里，完整的测试在天气后端的 SmsTest） */
class SmsTest extends TestCase
{
    use RefreshDatabase;

    public function test_aliyun_driver_sends_with_this_apps_own_signature(): void
    {
        config(['services.sms' => [
            'driver' => 'aliyun',
            'aliyun' => [
                'access_key_id' => 'gou-key-id',
                'access_key_secret' => 'gou-key-secret',
                'sign_name' => '再玩我是狗',
                'template_code' => 'SMS_000002',
            ],
        ]]);
        Http::fake(['dysmsapi.aliyuncs.com/*' => Http::response(['Code' => 'OK', 'Message' => 'OK'])]);

        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13900009000'])->assertOk();

        Http::assertSent(function (Request $request) {
            parse_str(parse_url($request->url(), PHP_URL_QUERY), $query);

            return $query['SignName'] === '再玩我是狗'
                && $query['TemplateCode'] === 'SMS_000002'
                && str_starts_with($request->header('Authorization')[0], 'ACS3-HMAC-SHA256 Credential=gou-key-id,');
        });
    }

    public function test_log_driver_is_the_dev_default_and_sends_nothing(): void
    {
        Http::fake();
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13900009001'])->assertOk();
        Http::assertNothingSent();
    }
}
