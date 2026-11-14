<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class MessageDeliveredEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /**
     * Create a new event instance.
     *
     * @param int $senderId The original sender of the messages (who needs delivery receipts)
     * @param int $receiverId The recipient acknowledging delivery
     * @param array<int> $messageIds List of message IDs delivered
     * @param string $deliveredAt ISO-8601 timestamp of delivery
     */
    public function __construct(
        public int $senderId,
        public int $receiverId,
        public array $messageIds,
        public string $deliveredAt,
    ) {}

    /**
     * The channels the event should broadcast on.
     *
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [
            new PrivateChannel('user.' . $this->senderId),
        ];
    }

    /**
     * The event's broadcast name.
     */
    public function broadcastAs(): string
    {
        return 'message.delivered';
    }

    /**
     * Get the data to broadcast.
     *
     * @return array<string, mixed>
     */
    public function broadcastWith(): array
    {
        return [
            'message_ids' => $this->messageIds,
            'receiver_id' => $this->receiverId,
            'delivered_at' => $this->deliveredAt,
        ];
    }
}
