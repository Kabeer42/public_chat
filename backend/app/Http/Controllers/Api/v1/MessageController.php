<?php

namespace App\Http\Controllers\Api\v1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Message\SendMessageRequest;
use App\Http\Resources\MessageResource;
use App\Services\MessageService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MessageController extends Controller
{
    public function __construct(
        protected MessageService $messageService
    ) {}

    /**
     * Send an E2EE encrypted message to another user.
     */
    public function send(SendMessageRequest $request): JsonResponse
    {
        $message = $this->messageService->sendMessage(
            $request->user()->id,
            $request->validated()
        );

        return response()->json([
            'message' => new MessageResource($message),
        ], 201);
    }

    /**
     * Get paginated encrypted chat history between current user and peer.
     */
    public function conversation(Request $request, int $peerId): JsonResponse
    {
        $perPage = max(1, min(100, (int) $request->query('per_page', 30)));
        $beforeId = $request->query('before_id') ? (int) $request->query('before_id') : null;
        $page = max(1, (int) $request->query('page', 1));

        $result = $this->messageService->getConversation(
            $request->user()->id,
            $peerId,
            $perPage,
            $beforeId,
            $page
        );

        return response()->json([
            'data' => MessageResource::collection($result['messages']),
            'pagination' => [
                'has_more' => $result['has_more'],
                'oldest_id' => $result['oldest_id'],
                'per_page' => $perPage,
                'page' => $page,
            ],
        ]);
    }

    /**
     * Mark an individual encrypted message as read.
     */
    public function markRead(Request $request, int $messageId): JsonResponse
    {
        $message = $this->messageService->markAsRead($messageId, $request->user()->id);

        if (!$message) {
            return response()->json([
                'message' => 'Message not found or not addressed to you.',
            ], 404);
        }

        return response()->json([
            'message' => new MessageResource($message),
        ]);
    }

    /**
     * Mark all unread messages from a peer conversation as read.
     */
    public function markConversationRead(Request $request, int $peerId): JsonResponse
    {
        $updatedCount = $this->messageService->markConversationAsRead($peerId, $request->user()->id);

        return response()->json([
            'marked_count' => $updatedCount,
        ]);
    }

    /**
     * Mark an individual encrypted message as delivered.
     */
    public function markDelivered(Request $request, int $messageId): JsonResponse
    {
        $message = $this->messageService->markAsDelivered($messageId, $request->user()->id);

        if (!$message) {
            return response()->json([
                'message' => 'Message not found or not addressed to you.',
            ], 404);
        }

        return response()->json([
            'message' => new MessageResource($message),
        ]);
    }

    /**
     * Mark all undelivered messages from a peer conversation as delivered.
     */
    public function markConversationDelivered(Request $request, int $peerId): JsonResponse
    {
        $deliveredIds = $this->messageService->markConversationAsDelivered($peerId, $request->user()->id);

        return response()->json([
            'delivered_ids' => $deliveredIds,
            'delivered_count' => count($deliveredIds),
        ]);
    }

    /**
     * Delete selected messages (for_everyone or for_me).
     */
    public function delete(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'message_ids' => ['required', 'array', 'min:1'],
            'message_ids.*' => ['required', 'integer'],
            'type' => ['required', 'string', 'in:for_everyone,for_me'],
        ]);

        $result = $this->messageService->deleteMessages(
            $request->user()->id,
            $validated['message_ids'],
            $validated['type']
        );

        return response()->json([
            'message' => 'Messages deleted successfully',
            'deleted_ids' => $result['deleted_ids'],
            'type' => $result['type'],
        ]);
    }

    /**
     * Get conversation disappearing timer setting.
     */
    public function getDisappearing(Request $request, int $peerId): JsonResponse
    {
        $duration = $this->messageService->getDisappearingDuration($request->user()->id, $peerId);

        return response()->json([
            'disappearing_duration_seconds' => $duration,
        ]);
    }

    /**
     * Update conversation disappearing timer setting.
     */
    public function setDisappearing(Request $request, int $peerId): JsonResponse
    {
        $validated = $request->validate([
            'duration' => ['required', 'integer', 'in:0,3600,43200,86400,604800'],
        ]);

        $duration = $this->messageService->setDisappearingDuration(
            $request->user()->id,
            $peerId,
            (int) $validated['duration']
        );

        return response()->json([
            'message' => 'Disappearing duration updated successfully.',
            'disappearing_duration_seconds' => $duration,
        ]);
    }
}
