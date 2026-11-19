<?php

namespace Series\Auth\Sms;

/**
 * 验证码没发出去。message 是给用户看的话（App 会直接显示），status 是返回给 App 的 HTTP 状态码。
 * 具体原因（服务商的错误码等）只记日志。
 */
class SmsSendException extends \RuntimeException
{
    public function __construct(string $message, private int $status = 503)
    {
        parent::__construct($message);
    }

    public function status(): int
    {
        return $this->status;
    }

    /** Laravel 遇到没接住的异常时调用：把这句话原样返回给 App */
    public function render()
    {
        return response()->json(['message' => $this->getMessage()], $this->status);
    }
}
