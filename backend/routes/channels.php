<?php

use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

/**
 * Private 1-to-1 User Channel for E2EE Messages & Call Notifications
 * Mobile clients subscribe to: private-user.{userId}
 */
Broadcast::channel('user.{userId}', function ($user, $userId) {
    if ((int) $user->id === (int) $userId) {
        $user->update(['is_online' => true, 'last_seen_at' => now()]);
        return true;
    }
    return false;
}, ['guards' => ['sanctum']]);

/**
 * Presence Channel for WebRTC Call Signaling (Offers, Answers, ICE Candidates)
 * Mobile clients subscribe to: presence-call.{callId}
 */
Broadcast::channel('call.{callId}', function (User $user, string $callId) {
    return [
        'id' => $user->id,
        'name' => $user->name,
        'public_identity_key' => $user->public_identity_key,
        'is_online' => true,
    ];
}, ['guards' => ['sanctum']]);

