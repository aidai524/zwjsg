<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DailyRecord extends Model
{
    protected $fillable = ['user_id', 'date', 'dog_percent', 'stage', 'minutes_used', 'breed_key'];

    protected function casts(): array
    {
        return [
            'date' => 'date:Y-m-d',
            'dog_percent' => 'integer',
            'stage' => 'integer',
            'minutes_used' => 'integer',
        ];
    }

    /** 只存 Y-m-d：date 类型转换默认会带上 00:00:00，在 SQLite 上会导致按日期查询对不上 */
    protected function date(): Attribute
    {
        return Attribute::make(set: fn ($value) => $value === null ? null : $this->asDateTime($value)->toDateString());
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
