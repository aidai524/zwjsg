<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\UserCity */
class CityResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'location_id' => $this->location_id,
            'name' => $this->name,
            'adm' => $this->adm,
            'is_home' => $this->is_home,
            'sort' => $this->sort,
            // 临时城市到期的时间（App 本地日期某天的 0 点）；长期关注的是 null
            'expires_at' => $this->expires_at?->toIso8601String(),
        ];
    }
}
