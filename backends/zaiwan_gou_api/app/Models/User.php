<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
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
        'avatar_preset',
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

    /** 加入的群组 */
    public function dogGroups(): BelongsToMany
    {
        return $this->belongsToMany(DogGroup::class, 'dog_group_members')
            ->withPivot(['hide_status', 'mute_nudges'])
            ->withTimestamps();
    }

    /** 群里显示的名字。没起名字的不用手机号顶替 */
    public function displayName(): string
    {
        return $this->nickname ?: '没起名的狗友';
    }

    public function avatarUrl(): ?string
    {
        return $this->avatar_path ? Storage::disk(config('filesystems.avatar_disk'))->url($this->avatar_path) : null;
    }

    /**
     * 给群里别人看的形象：用着预设形象（avatar_preset 不为空）时只给预设形象的名字，不给拍照形象的地址；
     * 不然给拍照形象（没有就都是 null，App 画默认的那张）
     */
    public function sharedAvatar(): array
    {
        return [
            'avatar_url' => $this->avatar_preset ? null : $this->avatarUrl(),
            'avatar_preset' => $this->avatar_preset,
        ];
    }

    /** 用户本地的“今天” */
    public function localToday(): string
    {
        return now($this->timezone)->toDateString();
    }
}
