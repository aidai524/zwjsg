<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UserCity extends Model
{
    protected $fillable = ['user_id', 'location_id', 'name', 'adm', 'is_home', 'sort', 'expires_at'];

    protected function casts(): array
    {
        return ['is_home' => 'boolean', 'sort' => 'integer', 'expires_at' => 'datetime'];
    }

    /** 还没到期的（长期关注的，加上还没到点的临时城市） */
    public function scopeActive(Builder $query): void
    {
        $query->where(fn (Builder $q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', now()));
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
