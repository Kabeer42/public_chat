<?php

namespace Database\Factories;

use App\Models\Message;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Message>
 */
class MessageFactory extends Factory
{
    protected $model = Message::class;

    public function definition(): array
    {
        return [
            'sender_id' => User::factory(),
            'receiver_id' => User::factory(),
            'message_type' => 'text',
            'ciphertext' => base64_encode(fake()->sha256()),
            'iv' => base64_encode(random_bytes(12)),
            'mac' => base64_encode(random_bytes(16)),
            'media_url' => null,
            'encrypted_media_key' => null,
            'is_delivered' => false,
            'is_read' => false,
            'read_at' => null,
        ];
    }

    public function read(): static
    {
        return $this->state(fn (array $attributes) => [
            'is_read' => true,
            'is_delivered' => true,
            'read_at' => now(),
        ]);
    }
}
