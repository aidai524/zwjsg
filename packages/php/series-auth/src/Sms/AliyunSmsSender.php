<?php

namespace Series\Auth\Sms;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * 阿里云短信：Dysmsapi 的 SendSms 接口（API 版本 2017-05-25），V3 签名（ACS3-HMAC-SHA256）。
 * 不引入阿里云 SDK：签名按官方文档自己算（测试里对过文档的示例），请求用 Laravel 的 HTTP 客户端。
 * 日志里手机号打码，不记验证码。AccessKey 只从服务器的 .env 读。
 */
class AliyunSmsSender implements SmsSender
{
    public const VERSION = '2017-05-25';

    private const ALGORITHM = 'ACS3-HMAC-SHA256';

    /** 阿里云的错误码 → 给用户看的话和状态码；没列出来的都算“短信服务暂时不可用” */
    private const USER_ERRORS = [
        'isv.BUSINESS_LIMIT_CONTROL' => ['发得太频繁了，过一会儿再试', 429],
        'isv.DAY_LIMIT_CONTROL' => ['今天发的验证码太多了，明天再试', 429],
        'isv.MOBILE_NUMBER_ILLEGAL' => ['手机号不对，检查一下', 422],
        'isv.MOBILE_COUNT_OVER_LIMIT' => ['手机号不对，检查一下', 422],
    ];

    public function __construct(
        private ?string $accessKeyId,
        private ?string $accessKeySecret,
        private ?string $signName,
        private ?string $templateCode,
        private string $templateParam = 'code',
        private string $endpoint = 'dysmsapi.aliyuncs.com',
        private int $timeoutSeconds = 5,
    ) {}

    public function sendCode(string $phone, string $code): void
    {
        if (blank($this->accessKeyId) || blank($this->accessKeySecret) || blank($this->signName) || blank($this->templateCode)) {
            Log::error('[sms] 阿里云短信缺配置：ALIYUN_SMS_ACCESS_KEY_ID / SECRET / SIGN_NAME / TEMPLATE_CODE');
            throw new SmsSendException('短信服务还没配置好，暂时登录不了', 503);
        }

        $query = [
            'PhoneNumbers' => $phone,
            'SignName' => $this->signName,
            'TemplateCode' => $this->templateCode,
            'TemplateParam' => json_encode([$this->templateParam => $code], JSON_UNESCAPED_UNICODE),
        ];
        $headers = self::sign(
            'POST', $this->endpoint, 'SendSms', self::VERSION, $query, '',
            $this->accessKeyId, $this->accessKeySecret, gmdate('Y-m-d\TH:i:s\Z'), bin2hex(random_bytes(16)),
        );
        unset($headers['host']); // 由 HTTP 客户端按网址带上，和签名里的一样

        try {
            $response = Http::withHeaders($headers)
                ->timeout($this->timeoutSeconds)
                ->send('POST', "https://{$this->endpoint}/?".self::canonicalQuery($query));
        } catch (ConnectionException $e) {
            Log::warning('[sms] 连不上阿里云', ['phone' => self::mask($phone), 'error' => $e->getMessage()]);
            throw new SmsSendException('短信发不出去，稍后再试', 503);
        }

        $body = $response->json() ?? [];
        $result = $body['Code'] ?? 'HTTP '.$response->status();
        if ($response->successful() && $result === 'OK') {
            Log::info('[sms] 验证码已发出', ['phone' => self::mask($phone), 'biz_id' => $body['BizId'] ?? null]);

            return;
        }

        Log::warning('[sms] 阿里云没发出去', [
            'phone' => self::mask($phone),
            'code' => $result,
            'message' => $body['Message'] ?? null,
            'request_id' => $body['RequestId'] ?? null,
        ]);
        [$message, $status] = self::USER_ERRORS[$result] ?? ['短信服务暂时不可用，稍后再试', 503];
        throw new SmsSendException($message, $status);
    }

    /**
     * 按阿里云 V3 签名算出要带的请求头（含 Authorization）。
     * 规范请求 = 方法、URI、排好序的查询参数、排好序的请求头、签名头列表、请求体的 SHA256，用换行连起来；
     * 待签字符串 = 算法名 + 换行 + 规范请求的 SHA256；签名 = 用 AccessKeySecret 做 HMAC-SHA256。
     */
    public static function sign(
        string $method, string $host, string $action, string $version, array $query, string $body,
        string $keyId, string $secret, string $date, string $nonce,
    ): array {
        $headers = [
            'host' => $host,
            'x-acs-action' => $action,
            'x-acs-content-sha256' => hash('sha256', $body),
            'x-acs-date' => $date,
            'x-acs-signature-nonce' => $nonce,
            'x-acs-version' => $version,
        ];
        ksort($headers, SORT_STRING);
        $canonicalHeaders = '';
        foreach ($headers as $name => $value) {
            $canonicalHeaders .= $name.':'.trim($value)."\n";
        }
        $signedHeaders = implode(';', array_keys($headers));
        $canonical = implode("\n", [
            strtoupper($method), '/', self::canonicalQuery($query), $canonicalHeaders, $signedHeaders, $headers['x-acs-content-sha256'],
        ]);
        $signature = hash_hmac('sha256', self::ALGORITHM."\n".hash('sha256', $canonical), $secret);
        $headers['Authorization'] = self::ALGORITHM." Credential={$keyId},SignedHeaders={$signedHeaders},Signature={$signature}";

        return $headers;
    }

    /** 查询参数按名字排序，名字和值都按 RFC 3986 编码（空格是 %20） */
    public static function canonicalQuery(array $query): string
    {
        ksort($query, SORT_STRING);

        return implode('&', array_map(
            fn ($name, $value) => rawurlencode((string) $name).'='.rawurlencode((string) $value),
            array_keys($query),
            $query,
        ));
    }

    /** 13812345678 → 138****5678 */
    public static function mask(string $phone): string
    {
        return strlen($phone) >= 7 ? substr($phone, 0, 3).'****'.substr($phone, -4) : '***';
    }
}
