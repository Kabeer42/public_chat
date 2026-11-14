<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class FcmService
{
    /**
     * Send an incoming call push notification (High Priority Data-Only).
     */
    public static function sendIncomingCall(
        string $fcmToken,
        string $callId,
        int $callerId,
        string $callerName,
        string $callType = 'audio',
        string $sdp = ''
    ): bool {
        $data = [
            'type' => 'incoming_call',
            'call_id' => $callId,
            'caller_id' => (string) $callerId,
            'caller_name' => $callerName,
            'call_type' => $callType,
        ];
        if (!empty($sdp) && strlen($sdp) < 3000) {
            $data['sdp'] = $sdp;
        }

        return self::sendMessage($fcmToken, [
            'data' => $data,
            'android' => [
                'priority' => 'high',
                'ttl' => '45s',
            ],
        ]);
    }

    /**
     * Send call missed / call ended push to dismiss ringing CallKit UI.
     */
    public static function sendCallEnded(string $fcmToken, string $callId): bool
    {
        return self::sendMessage($fcmToken, [
            'data' => [
                'type' => 'call_ended',
                'call_id' => $callId,
            ],
            'android' => [
                'priority' => 'high',
                'ttl' => '10s',
            ],
        ]);
    }

    /**
     * Send a standard message push notification.
     */
    public static function sendChatMessage(
        string $fcmToken,
        string $senderName,
        int $senderId,
        string $preview = 'Sent you a new encrypted message'
    ): bool {
        return self::sendMessage($fcmToken, [
            'notification' => [
                'title' => $senderName,
                'body' => $preview,
            ],
            'data' => [
                'type' => 'chat_message',
                'sender_id' => (string) $senderId,
                'sender_name' => $senderName,
            ],
            'android' => [
                'priority' => 'high',
                'notification' => [
                    'channel_id' => 'chat_messages',
                    'default_sound' => true,
                    'default_vibrate_timings' => true,
                    'priority' => 'high',
                ],
            ],
        ]);
    }

    /**
     * Send payload via FCM v1 HTTP API using Google Service Account JWT.
     */
    public static function sendMessage(string $deviceToken, array $payload): bool
    {
        $credentials = self::getCredentials();
        if (!$credentials) {
            Log::debug('FCM skipped: service account credentials not configured in storage/app/firebase/service-account.json');
            return false;
        }

        $accessToken = self::getAccessToken($credentials);
        if (!$accessToken) {
            return false;
        }

        $projectId = $credentials['project_id'] ?? null;
        if (!$projectId) {
            Log::error('FCM error: project_id missing in service account credentials');
            return false;
        }

        $messagePayload = array_merge([
            'token' => $deviceToken,
        ], $payload);

        try {
            $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";
            $response = Http::withToken($accessToken)
                ->connectTimeout(5)
                ->timeout(10)
                ->post($url, ['message' => $messagePayload]);

            if ($response->successful()) {
                return true;
            }

            Log::warning('FCM send failed', [
                'status' => $response->status(),
                'body' => $response->json(),
            ]);
            return false;
        } catch (\Throwable $e) {
            Log::warning('FCM exception (non-fatal): ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Load Google Service Account JSON.
     */
    protected static function getCredentials(): ?array
    {
        $path = env('FIREBASE_CREDENTIALS', storage_path('app/firebase/service-account.json'));
        if (!file_exists($path)) {
            return null;
        }

        $content = file_get_contents($path);
        return json_decode($content, true);
    }

    /**
     * Generate or fetch cached OAuth2 Bearer token using Service Account RS256 JWT.
     */
    protected static function getAccessToken(array $credentials): ?string
    {
        return Cache::remember('fcm_v1_access_token', 3000, function () use ($credentials) {
            $clientEmail = $credentials['client_email'] ?? null;
            $privateKey = $credentials['private_key'] ?? null;

            if (!$clientEmail || !$privateKey) {
                Log::error('FCM credentials missing client_email or private_key');
                return null;
            }

            $now = time();
            $header = self::base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
            $claim = self::base64UrlEncode(json_encode([
                'iss' => $clientEmail,
                'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
                'aud' => 'https://oauth2.googleapis.com/token',
                'exp' => $now + 3600,
                'iat' => $now,
            ]));

            $signingInput = "{$header}.{$claim}";
            $signature = '';

            if (!openssl_sign($signingInput, $signature, $privateKey, 'SHA256')) {
                Log::error('FCM failed to sign JWT using openssl');
                return null;
            }

            $jwt = "{$signingInput}." . self::base64UrlEncode($signature);

            try {
                $response = Http::asForm()
                    ->connectTimeout(5)
                    ->timeout(10)
                    ->post('https://oauth2.googleapis.com/token', [
                        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                        'assertion' => $jwt,
                    ]);

                if ($response->successful()) {
                    return $response->json('access_token');
                }

                Log::error('FCM OAuth2 token request failed: ' . $response->body());
                return null;
            } catch (\Throwable $e) {
                Log::warning('FCM OAuth2 exception: ' . $e->getMessage());
                return null;
            }
        });
    }

    protected static function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}
