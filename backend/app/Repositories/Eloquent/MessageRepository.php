<?php

namespace App\Repositories\Eloquent;

use App\Models\Message;
use App\Repositories\Contracts\MessageRepositoryInterface;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class MessageRepository implements MessageRepositoryInterface
{
    public function create(array $data): Message
    {
        return Message::create($data);
    }

    public function findById(int $id): ?Message
    {
        return Message::find($id);
    }

    public function getConversation(int $userId, int $peerId, int $perPage = 30, ?int $beforeId = null, int $page = 1): array
    {
        $query = Message::where(function ($query) use ($userId, $peerId) {
            $query->where(function ($q) use ($userId, $peerId) {
                $q->where('sender_id', $userId)
                  ->where('receiver_id', $peerId)
                  ->where('deleted_by_sender', false);
            })->orWhere(function ($q) use ($userId, $peerId) {
                $q->where('sender_id', $peerId)
                  ->where('receiver_id', $userId)
                  ->where('deleted_by_receiver', false);
            });
        })
        ->where('is_deleted_for_everyone', false)
        ->where(function ($query) {
            $query->whereNull('expires_at')
                  ->orWhere('expires_at', '>', now());
        });

        if ($beforeId) {
            $query->where('id', '<', $beforeId);
        } elseif ($page > 1) {
            $query->offset(($page - 1) * $perPage);
        }

        $items = $query->orderBy('id', 'desc')
                       ->limit($perPage + 1)
                       ->get();

        $hasMore = $items->count() > $perPage;
        if ($hasMore) {
            $items = $items->slice(0, $perPage);
        }

        $messages = $items->reverse()->values();

        return [
            'messages' => $messages,
            'has_more' => $hasMore,
            'oldest_id' => $messages->first()?->id,
        ];
    }

    public function markAsRead(int $messageId, int $readerId): ?Message
    {
        $message = Message::where('id', $messageId)
            ->where('receiver_id', $readerId)
            ->first();

        if (!$message) {
            return null;
        }

        $message->update([
            'is_read' => true,
            'is_delivered' => true,
            'read_at' => now(),
        ]);

        return $message;
    }

    public function markConversationAsRead(int $peerId, int $readerId): int
    {
        return Message::where('sender_id', $peerId)
            ->where('receiver_id', $readerId)
            ->where('is_read', false)
            ->update([
                'is_read' => true,
                'is_delivered' => true,
                'read_at' => now(),
            ]);
    }

    public function markAsDelivered(int $messageId, int $receiverId): ?Message
    {
        $message = Message::find($messageId);

        if (!$message || $message->receiver_id !== $receiverId) {
            return null;
        }

        if (!$message->is_delivered) {
            $message->update([
                'is_delivered' => true,
                'delivered_at' => now(),
            ]);
        }

        return $message;
    }

    public function markConversationAsDelivered(int $peerId, int $receiverId): array
    {
        $messages = Message::where('sender_id', $peerId)
            ->where('receiver_id', $receiverId)
            ->where('is_delivered', false)
            ->get();

        $ids = [];
        $now = now();
        foreach ($messages as $message) {
            $message->update([
                'is_delivered' => true,
                'delivered_at' => $now,
            ]);
            $ids[] = $message->id;
        }

        return $ids;
    }

    public function deleteForEveryone(array $messageIds, int $userId): array
    {
        $messages = Message::whereIn('id', $messageIds)
            ->where('sender_id', $userId)
            ->get();

        $deletedIds = [];
        $recipientGroups = [];

        foreach ($messages as $message) {
            $message->update(['is_deleted_for_everyone' => true]);
            $deletedIds[] = $message->id;
            $recipientGroups[$message->receiver_id][] = $message->id;
        }

        return [
            'deleted_ids' => $deletedIds,
            'recipient_groups' => $recipientGroups,
        ];
    }

    public function deleteForMe(array $messageIds, int $userId): array
    {
        Message::whereIn('id', $messageIds)
            ->where('sender_id', $userId)
            ->update(['deleted_by_sender' => true]);

        Message::whereIn('id', $messageIds)
            ->where('receiver_id', $userId)
            ->update(['deleted_by_receiver' => true]);

        return $messageIds;
    }
}
