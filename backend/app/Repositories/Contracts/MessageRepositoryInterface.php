<?php

namespace App\Repositories\Contracts;

use App\Models\Message;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

interface MessageRepositoryInterface
{
    /**
     * Store a new encrypted message.
     */
    public function create(array $data): Message;

    /**
     * Find a message by its ID.
     */
    public function findById(int $id): ?Message;

    /**
     * Retrieve paginated chronological chat history between two users.
     */
    public function getConversation(int $userId, int $peerId, int $perPage = 30, ?int $beforeId = null, int $page = 1): array;

    /**
     * Mark an individual message as read if the reader is the recipient.
     */
    public function markAsRead(int $messageId, int $readerId): ?Message;

    /**
     * Mark all unread messages from peer to current user as read.
     */
    public function markConversationAsRead(int $peerId, int $readerId): int;

    /**
     * Mark an individual message as delivered if receiver matches.
     */
    public function markAsDelivered(int $messageId, int $receiverId): ?Message;

    /**
     * Mark all undelivered messages from peer to current user as delivered.
     */
    public function markConversationAsDelivered(int $peerId, int $receiverId): array;

    /**
     * Delete messages for everyone (only messages authored by userId).
     */
    public function deleteForEveryone(array $messageIds, int $userId): array;

    /**
     * Delete messages for current user only.
     */
    public function deleteForMe(array $messageIds, int $userId): array;
}
