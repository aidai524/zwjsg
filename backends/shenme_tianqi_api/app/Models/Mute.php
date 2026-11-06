<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Mute extends Model
{
    protected $fillable = ['user_id', 'muted_user_id', 'care_group_id'];

    /** $recipient 是否静音了 $sender（单独静音此人，或静音了整个群） */
    public static function isMuted(int $recipientId, int $senderId, int $groupId): bool
    {
        return static::where('user_id', $recipientId)
            ->where(fn ($q) => $q->where('muted_user_id', $senderId)->orWhere('care_group_id', $groupId))
            ->exists();
    }
}
