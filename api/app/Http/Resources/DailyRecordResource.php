<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\DailyRecord */
class DailyRecordResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'date' => $this->date->toDateString(),
            'dog_percent' => $this->dog_percent,
            'stage' => $this->stage,
            'minutes_used' => $this->minutes_used,
            'breed_key' => $this->breed_key,
        ];
    }
}
