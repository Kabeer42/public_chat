<?php

namespace App\Http\Controllers\Api\v1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Key\PublishKeyRequest;
use App\Http\Resources\UserResource;
use App\Services\UserService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UserController extends Controller
{
    public function __construct(
        protected UserService $userService
    ) {}

    public function index(Request $request): JsonResponse
    {
        $users = $this->userService->getAllUsersExcept($request->user()->id);

        return response()->json([
            'users' => UserResource::collection($users),
        ]);
    }

    public function publishKey(PublishKeyRequest $request): JsonResponse
    {
        $this->userService->publishPublicKey(
            $request->user()->id,
            $request->validated('public_identity_key'),
            $request->validated('public_signed_prekey')
        );

        return response()->json([
            'message' => 'Public keys updated successfully',
        ]);
    }

    public function getKeyBackup(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated'], 401);
        }

        return response()->json([
            'has_backup' => !empty($user->encrypted_key_backup),
            'backup_data' => $user->encrypted_key_backup,
        ]);
    }

    public function saveKeyBackup(Request $request): JsonResponse
    {
        try {
            $request->validate([
                'backup_data' => 'required',
            ]);

            $backupData = $request->input('backup_data');
            if (is_array($backupData)) {
                $backupData = json_encode($backupData);
            }

            $user = $request->user();
            if (!$user) {
                return response()->json(['message' => 'Unauthenticated'], 401);
            }

            $user->update([
                'encrypted_key_backup' => (string) $backupData,
            ]);

            return response()->json([
                'message' => 'Key backup saved successfully',
                'has_backup' => true,
            ]);
        } catch (\Throwable $e) {
            \Log::error('saveKeyBackup error: ' . $e->getMessage());
            return response()->json([
                'message' => 'Failed to save key backup: ' . $e->getMessage(),
            ], 500);
        }
    }

    public function resetKeys(Request $request): JsonResponse
    {
        $request->user()->update([
            'public_identity_key' => null,
            'public_signed_prekey' => null,
            'encrypted_key_backup' => null,
        ]);

        return response()->json([
            'message' => 'Keys reset successfully',
        ]);
    }

    public function getPublicKey(int $userId): JsonResponse
    {
        $keys = $this->userService->getUserPublicKey($userId);

        if (!$keys) {
            return response()->json([
                'message' => 'User not found',
            ], 404);
        }

        return response()->json($keys);
    }

    public function updateFcmToken(Request $request): JsonResponse
    {
        $request->validate([
            'fcm_token' => 'required|string',
        ]);

        $request->user()->update([
            'fcm_token' => $request->input('fcm_token'),
        ]);

        return response()->json(['message' => 'FCM token updated successfully']);
    }

    /**
     * Periodic heartbeat / presence updater.
     */
    public function heartbeat(Request $request): JsonResponse
    {
        $isOnline = $request->boolean('is_online', true);
        $request->user()->update([
            'is_online' => $isOnline,
            'last_seen_at' => now(),
        ]);

        return response()->json([
            'status' => 'ok',
            'is_online' => (bool) $request->user()->is_online,
            'last_seen_at' => $request->user()->last_seen_at?->toIso8601String(),
        ]);
    }
}
