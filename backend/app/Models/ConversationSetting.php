<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ConversationSetting extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_one_id',
        'user_two_id',
        'disappearing_duration_seconds',
    ];

    protected $casts = [
        'disappearing_duration_seconds' => 'integer',
    ];

    public function userOne(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_one_id');
    }

    public function userTwo(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_two_id');
    }

    /**
     * Retrieve the setting for a given 1-to-1 conversation pair.
     */
    public static function getSetting(int $userA, int $userB): ?self
    {
        $min = min($userA, $userB);
        $max = max($userA, $userB);

        return self::where('user_one_id', $min)
            ->where('user_two_id', $max)
            ->first();
    }

    /**
     * Set or update disappearing duration for a conversation pair.
     */
    public static function setDuration(int $userA, int $userB, int $durationSeconds): self
    {
        $min = min($userA, $userB);
        $max = max($userA, $userB);

        return self::updateOrCreate(
            ['user_one_id' => $min, 'user_two_id' => $max],
            ['disappearing_duration_seconds' => max(0, $durationSeconds)]
        );
    }
}
