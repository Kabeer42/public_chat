<?php

namespace App\Services;

use App\Events\CallAnswerEvent;
use App\Events\CallEndedEvent;
use App\Events\CallOfferEvent;
use App\Events\IceCandidateEvent;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

class CallSignalingService
{
    /**
     * Send WebRTC SDP offer to recipient.
     */
    public function sendOffer(User $caller, array $data): array
    {
        $receiver = User::findOrFail($data['receiver_id']);

        // 1. Reachability check: verify recipient is online or reachable via push notification
        if (! $receiver->is_online && empty($receiver->fcm_token)) {
            return [
                'status' => 'offline',
                'message' => 'Recipient is currently away.',
                'call_id' => null,
            ];
        }

        // 2. Busy check: verify recipient is not already in an active call
        if (Cache::has("user_in_call_{$receiver->id}")) {
            return [
                'status' => 'busy',
                'message' => 'Recipient is currently on another call.',
                'call_id' => null,
            ];
        }

        $callId = $data['call_id'] ?? (string) Str::uuid();
        $sdp = $data['sdp'] ?? $data['sdp_offer'] ?? '';

        // Mark caller as initiating a call (short 60s TTL until answered or ended)
        Cache::put("user_in_call_{$caller->id}", $callId, now()->addSeconds(60));
        Cache::put("call_meta_{$callId}", [
            'caller_id' => $caller->id,
            'caller_name' => $caller->name,
            'receiver_id' => $receiver->id,
            'call_type' => $data['call_type'],
            'sdp' => $sdp,
        ], now()->addMinutes(15));

        // 3. Broadcast CallOfferEvent over WebSockets (safely caught so Reverb down doesn't crash 500)
        try {
            event(new CallOfferEvent(
                callId: $callId,
                caller: $caller,
                receiverId: $receiver->id,
                callType: $data['call_type'],
                sdp: $sdp,
            ));
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Call offer broadcast failed: ' . $e->getMessage());
        }

        // 4. Send high-priority background incoming call push via FCM
        if (!empty($receiver->fcm_token)) {
            try {
                FcmService::sendIncomingCall(
                    $receiver->fcm_token,
                    $callId,
                    $caller->id,
                    $caller->name,
                    $data['call_type'],
                    $sdp
                );
            } catch (\Throwable $e) {
                \Illuminate\Support\Facades\Log::warning('FCM call push failed: ' . $e->getMessage());
            }
        }

        return [
            'status' => 'ringing',
            'message' => 'Call offer broadcasted successfully.',
            'call_id' => $callId,
        ];
    }

    /**
     * Send WebRTC SDP answer back to caller.
     */
    public function sendAnswer(User $callee, array $data): array
    {
        $callId = $data['call_id'] ?? (string) Str::uuid();
        $receiverId = (int) ($data['receiver_id'] ?? $data['caller_id']);
        $sdp = $data['sdp'] ?? $data['sdp_answer'] ?? '';

        // Mark callee and caller as connected in this call
        Cache::put("user_in_call_{$callee->id}", $callId, now()->addMinutes(15));
        Cache::put("user_in_call_{$receiverId}", $callId, now()->addMinutes(15));

        try {
            event(new CallAnswerEvent(
                callId: $callId,
                callee: $callee,
                receiverId: $receiverId,
                sdp: $sdp,
            ));
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Call answer broadcast failed: ' . $e->getMessage());
        }


        return [
            'status' => 'connected',
            'message' => 'Call answer broadcasted successfully.',
            'call_id' => $callId,
        ];
    }

    /**
     * Relay ICE candidate between peers.
     */
    public function relayIceCandidate(User $sender, array $data): array
    {
        try {
            event(new IceCandidateEvent(
                callId: $data['call_id'] ?? '',
                senderId: $sender->id,
                receiverId: (int) $data['receiver_id'],
                candidate: $data['candidate'],
            ));
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('ICE candidate relay failed: ' . $e->getMessage());
        }

        return [
            'status' => 'success',
            'message' => 'ICE candidate relayed successfully.',
        ];
    }

    /**
     * End, reject, or hang up an ongoing or incoming call.
     */
    public function endCall(User $sender, array $data): array
    {
        $callId = $data['call_id'] ?? null;
        $receiverId = (int) $data['receiver_id'];
        $reason = $data['reason'] ?? 'hung_up';

        // Clear active call state for both peers
        Cache::forget("user_in_call_{$sender->id}");
        Cache::forget("user_in_call_{$receiverId}");
        if ($callId) {
            Cache::forget("call_meta_{$callId}");
        }

        try {
            event(new CallEndedEvent(
                callId: $callId,
                senderId: $sender->id,
                receiverId: $receiverId,
                reason: $reason,
            ));
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('Call ended broadcast failed: ' . $e->getMessage());
        }

        // Dismiss ringing notification on receiver device if callId is available
        $receiver = User::find($receiverId);
        if ($receiver && !empty($receiver->fcm_token) && $callId) {
            FcmService::sendCallEnded($receiver->fcm_token, $callId);
        }

        return [
            'status' => 'ended',
            'message' => 'Call ended successfully.',
            'reason' => $reason,
        ];
    }

    /**
     * Retrieve active call metadata and SDP offer by call ID.
     */
    public function getCallMeta(string $callId): ?array
    {
        return Cache::get("call_meta_{$callId}");
    }
}
