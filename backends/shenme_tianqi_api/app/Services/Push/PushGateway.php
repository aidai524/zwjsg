<?php

namespace App\Services\Push;

use App\Models\User;

interface PushGateway
{
    /** @param array<string, scalar> $data */
    public function send(User $user, string $title, string $body, array $data = []): void;
}
