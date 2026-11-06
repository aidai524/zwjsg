<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory;

    protected $fillable = [
        'phone',
        'wechat_openid',
        'nickname',
        'timezone',
        'daily_goal_minutes',
        'remind_at',
        'avatar_path',
        'avatar_regen_left',
    ];

    protected $hidden = [
        'wechat_openid',
        'avatar_path',
    ];

    protected function casts(): array
    {
        return [
            'daily_goal_minutes' => 'integer',
            'avatar_regen_left' => 'integer',
        ];
    }

    public function dailyRecords(): HasMany
    {
        return $this->hasMany(DailyRecord::class);
    }

    public function breeds(): HasMany
    {
        return $this->hasMany(UserBreed::class);
    }

    public function avatarUrl(): ?string
    {
        return $this->avatar_path ? Storage::disk(config('filesystems.avatar_disk'))->url($this->avatar_path) : null;
    }

    /** 用户本地的“今天” */
    public function localToday(): string
    {
        return now($this->timezone)->toDateString();
    }
}
