<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'name',
        'email',
        'password',
        'public_identity_key',
        'public_signed_prekey',
        'encrypted_key_backup',
        'is_online',
        'last_seen_at',
        'show_last_seen',
        'fcm_token',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_online' => 'boolean',
            'last_seen_at' => 'datetime',
            'show_last_seen' => 'boolean',
        ];
    }

    /**
     * Dynamic presence: User is only online if flag is true AND heartbeat is within last 90 seconds.
     */
    public function getIsOnlineAttribute(): bool
    {
        if (! ($this->attributes['is_online'] ?? false)) {
            return false;
        }

        if (! $this->last_seen_at) {
            return false;
        }

        return $this->last_seen_at->gte(now()->subSeconds(90));
    }
}
