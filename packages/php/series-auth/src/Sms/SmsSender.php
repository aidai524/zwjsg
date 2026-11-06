<?php

namespace Series\Auth\Sms;

interface SmsSender
{
    public function sendCode(string $phone, string $code): void;
}
