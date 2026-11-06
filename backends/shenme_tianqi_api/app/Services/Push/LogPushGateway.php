<?php

namespace App\Services\Push;

use App\Models\User;
use Illuminate\Support\Facades\Log;

/** 开发用：推送只写日志。上线前换成统一推送联盟 / 厂商通道 / APNs 实现。 */
class LogPushGateway implements PushGateway
{
    public function send(User $user, string $title, string $body, array $data = []): void
    {
        Log::info('[push]', ['user' => $user->id, 'title' => $title, 'body' => $body, 'data' => $data]);
    }
}
