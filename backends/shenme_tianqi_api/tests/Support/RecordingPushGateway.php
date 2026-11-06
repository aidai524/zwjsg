<?php

namespace Tests\Support;

use App\Models\User;
use App\Services\Push\PushGateway;

class RecordingPushGateway implements PushGateway
{
    /** @var list<array{user:int, title:string, body:string, data:array}> */
    public array $sent = [];

    public function send(User $user, string $title, string $body, array $data = []): void
    {
        $this->sent[] = ['user' => $user->id, 'title' => $title, 'body' => $body, 'data' => $data];
    }

    public function to(User $user): array
    {
        return array_values(array_filter($this->sent, fn ($p) => $p['user'] === $user->id));
    }
}
