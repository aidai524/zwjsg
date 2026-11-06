<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class UserCity extends Model
{
    protected $fillable = ['user_id', 'location_id', 'name', 'adm', 'is_home', 'sort'];

    protected function casts(): array
    {
        return ['is_home' => 'boolean', 'sort' => 'integer'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
