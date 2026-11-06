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
            'snark_level' => $this->snark_level,
            'morning_push_on' => $this->morning_push_on,
            'morning_push_weekday' => substr((string) $this->morning_push_weekday, 0, 5),
            'morning_push_weekend' => substr((string) $this->morning_push_weekend, 0, 5),
            'alert_push_on' => $this->alert_push_on,
            'avatar_url' => $this->avatarUrl(),
            'home_city' => $this->whenLoaded('homeCity', fn () => $this->homeCity ? new CityResource($this->homeCity) : null),
            'today' => $this->localToday(),
        ];
    }
}
