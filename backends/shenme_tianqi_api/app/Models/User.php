<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory;

    protected $fillable = [
        'phone', 'wechat_openid', 'nickname', 'timezone', 'snark_level',
        'morning_push_on', 'morning_push_weekday', 'morning_push_weekend', 'alert_push_on',
        'push_token', 'avatar_path',
    ];

    protected $hidden = ['wechat_openid', 'avatar_path', 'push_token'];

    protected function casts(): array
    {
        return [
            'snark_level' => 'integer',
            'morning_push_on' => 'boolean',
            'alert_push_on' => 'boolean',
        ];
    }

    public function cities(): HasMany
    {
        return $this->hasMany(UserCity::class);
    }

    public function homeCity(): HasOne
    {
        return $this->hasOne(UserCity::class)->where('is_home', true);
    }

    public function careGroups(): BelongsToMany
    {
        return $this->belongsToMany(CareGroup::class, 'care_group_members')->withTimestamps();
    }

    public function displayName(): string
    {
        return $this->nickname ?: '一位家人';
    }

    public function avatarUrl(): ?string
    {
        return $this->avatar_path ? Storage::disk(config('filesystems.avatar_disk'))->url($this->avatar_path) : null;
    }

    public function localToday(): string
    {
        return now($this->timezone)->toDateString();
    }
}
