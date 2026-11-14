<?php

namespace App\Services;

use App\Events\DisappearingDurationUpdatedEvent;
use App\Events\MessageReadEvent;
use App\Events\MessageSentEvent;
use App\Models\ConversationSetting;
use App\Models\Message;
use App\Repositories\Contracts\MessageRepositoryInterface;
use App\Repositories\Contracts\UserRepositoryInterface;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

class MessageService
{
    public function __construct(
        protected MessageRepositoryInterface $messageRepository,
        protected UserRepositoryInterface $userRepository
    ) {}

    /**
     * Send an E2EE encrypted message and broadcast it to the receiver.
     */
    public function sendMessage(int $senderId, array $data): Message
    {
        $receiver = $this->userRepository->findById($data['receiver_id']);
        if (!$receiver) {
            throw new NotFoundHttpException('Recipient user not found.');
        }

        $data['sender_id'] = $senderId;
        $data['is_delivered'] = false;
        $data['is_read'] = false;

        // Auto-assign expires_at if disappearing messages are active for this conversation
        $setting = ConversationSetting::getSetting($senderId, (int) $data['receiver_id']);
        if ($setting && $setting->disappearing_duration_seconds > 0) {
            $data['expires_at'] = now()->addSeconds($setting->disappearing_duration_seconds);
        }

        $message = $this->messageRepository->create($data);

        // Broadcast immediately over Reverb to recipient's private channel
        MessageSentEvent::dispatch($message);

        // Push notification via FCM
        if (!empty($receiver->fcm_token)) {
            $sender = $this->userRepository->findById($senderId);
            $senderName = $sender ? $sender->name : 'Someone';
            FcmService::sendChatMessage($receiver->fcm_token, $senderName, $senderId);
        }

        return $message;
    }

    /**
     * Retrieve paginated encrypted chat history between two users.
     */
    public function getConversation(int $userId, int $peerId, int $perPage = 30, ?int $beforeId = null, int $page = 1): array
    {
        $peer = $this->userRepository->findById($peerId);
        if (!$peer) {
            throw new NotFoundHttpException('Peer contact not found.');
        }

        return $this->messageRepository->getConversation($userId, $peerId, $perPage, $beforeId, $page);
    }

    /**
     * Mark an individual message as read and broadcast receipt to the sender.
     */
    public function markAsRead(int $messageId, int $readerId): ?Message
    {
        $message = $this->messageRepository->markAsRead($messageId, $readerId);

        if ($message) {
            MessageReadEvent::dispatch($message);
        }

        return $message;
    }

    /**
     * Mark all unread messages from a peer conversation as read.
     */
    public function markConversationAsRead(int $peerId, int $readerId): int
    {
        return $this->messageRepository->markConversationAsRead($peerId, $readerId);
    }

    /**
     * Mark an individual message as delivered and broadcast receipt to the sender.
     */
    public function markAsDelivered(int $messageId, int $receiverId): ?Message
    {
        $message = $this->messageRepository->markAsDelivered($messageId, $receiverId);

        if ($message) {
            \App\Events\MessageDeliveredEvent::dispatch(
                $message->sender_id,
                $receiverId,
                [$message->id],
                $message->delivered_at ? $message->delivered_at->toIso8601String() : now()->toIso8601String()
            );
        }

        return $message;
    }

    /**
     * Mark all undelivered messages from a peer conversation as delivered and broadcast receipt.
     */
    public function markConversationAsDelivered(int $peerId, int $receiverId): array
    {
        $deliveredIds = $this->messageRepository->markConversationAsDelivered($peerId, $receiverId);

        if (!empty($deliveredIds)) {
            \App\Events\MessageDeliveredEvent::dispatch(
                $peerId,
                $receiverId,
                $deliveredIds,
                now()->toIso8601String()
            );
        }

        return $deliveredIds;
    }

    /**
     * Delete messages either for everyone or for the current user only.
     */
    public function deleteMessages(int $userId, array $messageIds, string $type): array
    {
        if ($type === 'for_everyone') {
            $result = $this->messageRepository->deleteForEveryone($messageIds, $userId);
            // Broadcast deletion event to each recipient
            if (!empty($result['recipient_groups'])) {
                foreach ($result['recipient_groups'] as $receiverId => $deletedIds) {
                    \App\Events\MessageDeletedEvent::dispatch((int) $receiverId, $userId, $deletedIds);
                }
            }
            return [
                'deleted_ids' => $result['deleted_ids'],
                'type' => 'for_everyone',
            ];
        }

        $deletedIds = $this->messageRepository->deleteForMe($messageIds, $userId);
        return [
            'deleted_ids' => $deletedIds,
            'type' => 'for_me',
        ];
    }

    /**
     * Get active disappearing duration in seconds for this conversation.
     */
    public function getDisappearingDuration(int $userA, int $userB): int
    {
        $setting = ConversationSetting::getSetting($userA, $userB);
        return $setting ? (int) $setting->disappearing_duration_seconds : 0;
    }

    /**
     * Set disappearing duration and broadcast update to peer.
     */
    public function setDisappearingDuration(int $userId, int $peerId, int $durationSeconds): int
    {
        $peer = $this->userRepository->findById($peerId);
        if (!$peer) {
            throw new NotFoundHttpException('Peer contact not found.');
        }

        ConversationSetting::setDuration($userId, $peerId, $durationSeconds);

        // Broadcast setting update to peer private channel
        DisappearingDurationUpdatedEvent::dispatch($peerId, $userId, $durationSeconds);

        return $durationSeconds;
    }
}
