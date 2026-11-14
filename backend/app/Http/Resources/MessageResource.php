<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MessageResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'sender_id' => $this->sender_id,
            'receiver_id' => $this->receiver_id,
            'message_type' => $this->message_type,
            'ciphertext' => $this->ciphertext,
            'iv' => $this->iv,
            'mac' => $this->mac,
            'media_url' => $this->media_url,
            'encrypted_media_key' => $this->encrypted_media_key,
            'file_name' => $this->file_name,
            'file_size' => $this->file_size,
            'reply_to_id' => $this->reply_to_id,
            'reply_preview' => $this->reply_preview,
            'is_delivered' => (bool) $this->is_delivered,
            'delivered_at' => $this->delivered_at ? $this->delivered_at->toIso8601String() : null,
            'is_read' => (bool) $this->is_read,
            'read_at' => $this->read_at ? $this->read_at->toIso8601String() : null,
            'expires_at' => $this->expires_at ? $this->expires_at->toIso8601String() : null,
            'created_at' => $this->created_at ? $this->created_at->toIso8601String() : null,
        ];
    }
}
