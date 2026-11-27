<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** 汪一下：群里有人叫你放下手机 */
class Nudge extends Model
{
    protected $fillable = ['dog_group_id', 'sender_id', 'recipient_id', 'suppressed', 'seen_at'];

    protected function casts(): array
    {
        return [
            'suppressed' => 'boolean',
            'seen_at' => 'datetime',
        ];
    }

    public function group(): BelongsTo
    {
        return $this->belongsTo(DogGroup::class, 'dog_group_id');
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }
}
