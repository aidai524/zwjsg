<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UserBreed extends Model
{
    protected $fillable = ['user_id', 'breed_key', 'first_unlocked_on'];

    protected function casts(): array
    {
        return ['first_unlocked_on' => 'date:Y-m-d'];
    }

    /** 只存 Y-m-d，原因同 DailyRecord::date() */
    protected function firstUnlockedOn(): Attribute
    {
        return Attribute::make(set: fn ($value) => $value === null ? null : $this->asDateTime($value)->toDateString());
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
