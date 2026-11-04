<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\User */
class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'nickname' => $this->nickname,
            'phone_masked' => $this->phone ? substr($this->phone, 0, 3).'****'.substr($this->phone, -4) : null,
            'timezone' => $this->timezone,
            'daily_goal_minutes' => $this->daily_goal_minutes,
            'remind_at' => substr((string) $this->remind_at, 0, 5),
            'avatar_url' => $this->avatarUrl(),
            'avatar_regen_left' => $this->avatar_regen_left,
            'today' => $this->localToday(),
        ];
    }
}
