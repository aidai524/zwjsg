<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Series\Auth\Sms\AliyunSmsSender;
use Tests\TestCase;

/** 登录验证码接阿里云短信（两个后端共用 series-auth 包里的实现） */
class SmsTest extends TestCase
{
    use RefreshDatabase;

    private function useAliyun(): void
    {
        config(['services.sms' => [
            'driver' => 'aliyun',
            'aliyun' => [
                'access_key_id' => 'test-key-id',
                'access_key_secret' => 'test-key-secret',
                'sign_name' => '什么鬼天气',
                'template_code' => 'SMS_000001',
                'template_param' => 'code',
                'endpoint' => 'dysmsapi.aliyuncs.com',
            ],
        ]]);
    }

    public function test_signature_matches_aliyun_doc_example(): void
    {
        // 阿里云《V3 版本请求体 & 签名机制》文档里的示例
        $headers = AliyunSmsSender::sign(
            'POST', 'ecs.cn-shanghai.aliyuncs.com', 'RunInstances', '2014-05-26',
            ['ImageId' => 'win2019_1809_x64_dtc_zh-cn_40G_alibase_20230811.vhd', 'RegionId' => 'cn-shanghai'], '',
            'YourAccessKeyId', 'YourAccessKeySecret', '2023-10-26T10:22:32Z', '3156853299f313e23d1673dc12e1703d',
        );

        $this->assertSame(
            'ACS3-HMAC-SHA256 Credential=YourAccessKeyId,'
            .'SignedHeaders=host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-signature-nonce;x-acs-version,'
            .'Signature=06563a9e1b43f5dfe96b81484da74bceab24a1d853912eee15083a6f0f3283c0',
            $headers['Authorization'],
        );
        $this->assertSame('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', $headers['x-acs-content-sha256']);
        // 空格编码成 %20，中文按 UTF-8 编码
        $this->assertSame('A=a%20b&B=%E5%A4%A9', AliyunSmsSender::canonicalQuery(['B' => '天', 'A' => 'a b']));
    }

    public function test_sends_code_through_aliyun_and_the_code_logs_in(): void
    {
        $this->useAliyun();
        Http::fake(['dysmsapi.aliyuncs.com/*' => Http::response(['Code' => 'OK', 'Message' => 'OK', 'BizId' => 'b1', 'RequestId' => 'r1'])]);

        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008000'])->assertOk()->assertJson(['sent' => true]);

        $sent = null;
        Http::assertSent(function (Request $request) use (&$sent) {
            parse_str(parse_url($request->url(), PHP_URL_QUERY), $query);
            $sent = $query;

            return $request->method() === 'POST'
                && str_starts_with($request->url(), 'https://dysmsapi.aliyuncs.com/?')
                && $request->header('x-acs-action')[0] === 'SendSms'
                && $request->header('x-acs-version')[0] === '2017-05-25'
                && str_starts_with($request->header('Authorization')[0], 'ACS3-HMAC-SHA256 Credential=test-key-id,SignedHeaders=host;x-acs-action;');
        });
        $this->assertSame('13800008000', $sent['PhoneNumbers']);
        $this->assertSame('什么鬼天气', $sent['SignName']);
        $this->assertSame('SMS_000001', $sent['TemplateCode']);
        $code = json_decode($sent['TemplateParam'], true)['code'];
        $this->assertMatchesRegularExpression('/^\d{6}$/', $code);

        $this->postJson('/api/v1/auth/sms/login', ['phone' => '13800008000', 'code' => $code])->assertOk()->assertJsonStructure(['token']);
    }

    public function test_business_errors_become_friendly_messages_and_logs_mask_the_phone(): void
    {
        $this->useAliyun();
        Log::spy();
        Http::fake(['dysmsapi.aliyuncs.com/*' => Http::response(['Code' => 'isv.BUSINESS_LIMIT_CONTROL', 'Message' => '触发分钟级流控', 'RequestId' => 'r2'])]);

        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008001'])
            ->assertStatus(429)
            ->assertJsonPath('message', '发得太频繁了，过一会儿再试');

        Log::shouldHaveReceived('warning')->withArgs(
            fn ($message, $context) => $context['phone'] === '138****8001' && $context['code'] === 'isv.BUSINESS_LIMIT_CONTROL'
                && ! str_contains(json_encode($context), '13800008001'),
        );

        // 没发出去的验证码作废：拿什么码都登不进去
        $this->postJson('/api/v1/auth/sms/login', ['phone' => '13800008001', 'code' => '123456'])->assertStatus(422);
    }

    public function test_unknown_errors_and_timeouts_say_try_later(): void
    {
        $this->useAliyun();
        Http::fake(['dysmsapi.aliyuncs.com/*' => Http::response(['Code' => 'SignatureDoesNotMatch', 'Message' => 'x'], 400)]);
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008002'])
            ->assertStatus(503)
            ->assertJsonPath('message', '短信服务暂时不可用，稍后再试');

        Http::fake(fn () => throw new ConnectionException('timed out'));
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008003'])
            ->assertStatus(503)
            ->assertJsonPath('message', '短信发不出去，稍后再试');
    }

    public function test_missing_aliyun_config_refuses_without_calling_out(): void
    {
        config(['services.sms' => ['driver' => 'aliyun', 'aliyun' => ['access_key_id' => 'k']]]);
        Http::fake();

        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008004'])
            ->assertStatus(503)
            ->assertJsonPath('message', '短信服务还没配置好，暂时登录不了');
        Http::assertNothingSent();
    }

    public function test_log_driver_only_writes_the_log_in_dev(): void
    {
        Http::fake();
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008005'])->assertOk();
        Http::assertNothingSent();
    }

    public function test_log_driver_refuses_in_production(): void
    {
        // 路由会缓存控制器（连同发送器），所以在第一个请求之前切到生产环境
        $this->app->detectEnvironment(fn () => 'production');
        $this->postJson('/api/v1/auth/sms/send', ['phone' => '13800008006'])
            ->assertStatus(503)
            ->assertJsonPath('message', '短信服务还没配置好，暂时登录不了');
    }
}
