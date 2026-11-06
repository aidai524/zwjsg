<?php

namespace Series\Auth;

use Series\Auth\Sms\SmsSender;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;

class SmsCodeService
{
    private const TTL_SECONDS = 300;

    private const MAX_ATTEMPTS = 5;

    public function __construct(private SmsSender $sender) {}

    public function send(string $phone): void
    {
        $code = (string) random_int(100000, 999999);

        Cache::put($this->key($phone), [
            'hash' => Hash::make($code),
            'attempts' => 0,
        ], self::TTL_SECONDS);

        $this->sender->sendCode($phone, $code);
    }

    /** 校验成功后验证码立即作废 */
    public function verify(string $phone, string $code): bool
    {
        $entry = Cache::get($this->key($phone));
        if (! $entry || $entry['attempts'] >= self::MAX_ATTEMPTS) {
            return false;
        }

        if (! Hash::check($code, $entry['hash'])) {
            $entry['attempts']++;
            Cache::put($this->key($phone), $entry, self::TTL_SECONDS);

            return false;
        }

        Cache::forget($this->key($phone));

        return true;
    }

    private function key(string $phone): string
    {
        return 'sms_code:'.$phone;
    }
}
