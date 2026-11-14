<?php

use App\Http\Controllers\Api\v1\AuthController;
use App\Http\Controllers\Api\v1\CallSignalingController;
use App\Http\Controllers\Api\v1\ErrorAuditController;
use App\Http\Controllers\Api\v1\MediaController;
use App\Http\Controllers\Api\v1\MessageController;
use App\Http\Controllers\Api\v1\UserController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    // Health Check
    Route::get('/health', function () {
        return response()->json([
            'status' => 'ok',
            'service' => 'ChatAPP Backend',
            'timestamp' => now()->toIso8601String(),
            'version' => '1.0.0',
            'environment' => config('app.env'),
        ]);
    });

    // Public Auth Routes
    Route::prefix('auth')->group(function () {
        Route::post('/register', [AuthController::class, 'register']);
        Route::post('/login', [AuthController::class, 'login']);
    });

    // Public or Authenticated Client Diagnostic Error Logging
    Route::post('/errors/client', [ErrorAuditController::class, 'logClientError']);

    // Protected Routes (Sanctum Token)
    Route::middleware('auth:sanctum')->group(function () {
        // Auth Session & Profile Management
        Route::prefix('auth')->group(function () {
            Route::post('/logout', [AuthController::class, 'logout']);
            Route::get('/me', [AuthController::class, 'me']);
            Route::put('/profile', [AuthController::class, 'updateProfile']);
            Route::put('/password', [AuthController::class, 'updatePassword']);
            Route::put('/privacy', [AuthController::class, 'updatePrivacy']);
        });

        // Users Directory & Presence
        Route::get('/users', [UserController::class, 'index']);
        Route::post('/user/fcm-token', [UserController::class, 'updateFcmToken']);
        Route::post('/user/heartbeat', [UserController::class, 'heartbeat']);

        // E2EE Public Keys & Key Backup
        Route::prefix('keys')->group(function () {
            Route::post('/publish', [UserController::class, 'publishKey']);
            Route::get('/backup', [UserController::class, 'getKeyBackup']);
            Route::post('/backup', [UserController::class, 'saveKeyBackup']);
            Route::post('/reset', [UserController::class, 'resetKeys']);
            Route::get('/{userId}', [UserController::class, 'getPublicKey']);
        });

        // E2EE Encrypted Messages
        Route::prefix('messages')->group(function () {
            Route::post('/send', [MessageController::class, 'send']);
            Route::get('/{peerId}', [MessageController::class, 'conversation']);
            Route::post('/{messageId}/delivered', [MessageController::class, 'markDelivered']);
            Route::post('/conversation/{peerId}/delivered', [MessageController::class, 'markConversationDelivered']);
            Route::post('/{messageId}/read', [MessageController::class, 'markRead']);
            Route::post('/conversation/{peerId}/read', [MessageController::class, 'markConversationRead']);
            Route::delete('/', [MessageController::class, 'delete']);
        });

        // Conversation Settings (Disappearing Messages)
        Route::prefix('conversations')->group(function () {
            Route::get('/{peerId}/disappearing', [MessageController::class, 'getDisappearing']);
            Route::post('/{peerId}/disappearing', [MessageController::class, 'setDisappearing']);
        });

        // Encrypted Media Blobs (Images & Videos)
        Route::prefix('media')->group(function () {
            Route::post('/upload', [MediaController::class, 'upload']);
            Route::get('/{uuid}', [MediaController::class, 'download']);
        });

        // WebRTC Real-Time Signaling (Audio & Video Calling)
        Route::prefix('call')->group(function () {
            Route::post('/offer', [CallSignalingController::class, 'offer']);
            Route::post('/answer', [CallSignalingController::class, 'answer']);
            Route::post('/ice-candidate', [CallSignalingController::class, 'iceCandidate']);
            Route::post('/end', [CallSignalingController::class, 'end']);
            Route::get('/{callId}', [CallSignalingController::class, 'show']);
        });

        // Centralized Error Auditing & Diagnostics
        Route::prefix('errors')->group(function () {
            Route::get('/{referenceCode}', [ErrorAuditController::class, 'show']);
        });

        // WebSocket Channel Authentication for Mobile Clients
        Route::post('/broadcasting/auth', function (\Illuminate\Http\Request $request) {
            return \Illuminate\Support\Facades\Broadcast::auth($request);
        });
    });
});

