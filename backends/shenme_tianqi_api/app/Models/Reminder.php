<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Reminder extends Model
{
    protected $fillable = [
        'care_group_id', 'sender_id', 'recipient_id', 'topic', 'phrase_key', 'text',
        'recipient_date', 'deliver_at', 'delivered_at', 'acked_at', 'merged_into_id', 'suppressed',
    ];

    protected function casts(): array
    {
        return [
            'deliver_at' => 'datetime',
            'delivered_at' => 'datetime',
            'acked_at' => 'datetime',
            'suppressed' => 'boolean',
        ];
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function recipient(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recipient_id');
    }

    public function group(): BelongsTo
    {
        return $this->belongsTo(CareGroup::class, 'care_group_id');
    }
}
