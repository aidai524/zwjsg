<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Support\Str;

class CareGroup extends Model
{
    protected $fillable = ['name', 'invite_code', 'owner_id'];

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_id');
    }

    public function members(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'care_group_members')->withTimestamps();
    }

    public function hasMember(User $user): bool
    {
        return $this->members()->whereKey($user->id)->exists();
    }

    public static function newInviteCode(): string
    {
        do {
            // 去掉容易看错的字符，方便口头念
            $code = Str::upper(Str::random(8));
            $code = strtr($code, ['0' => 'X', 'O' => 'Y', '1' => 'Z', 'I' => 'W', 'L' => 'V']);
        } while (static::where('invite_code', $code)->exists());

        return $code;
    }
}
