<?php

namespace App\Services\Sms;

interface SmsSender
{
    public function sendCode(string $phone, string $code): void;
}
