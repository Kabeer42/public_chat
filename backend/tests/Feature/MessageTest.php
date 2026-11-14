<?php

namespace Tests\Feature;

use App\Events\MessageDeliveredEvent;
use App\Events\MessageReadEvent;
use App\Events\MessageSentEvent;
use App\Models\Message;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

class MessageTest extends TestCase
{
    use RefreshDatabase;

    public function test_unauthenticated_user_cannot_access_message_endpoints(): void
    {
        $this->postJson('/api/v1/messages/send', [])->assertStatus(401);
        $this->getJson('/api/v1/messages/1')->assertStatus(401);
        $this->postJson('/api/v1/messages/1/read')->assertStatus(401);
        $this->postJson('/api/v1/messages/conversation/1/read')->assertStatus(401);
    }

    public function test_user_can_send_encrypted_message_and_broadcast_event(): void
    {
        Event::fake([MessageSentEvent::class]);

        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        $payload = [
            'receiver_id' => $receiver->id,
            'message_type' => 'text',
            'ciphertext' => 'dGVzdENpcGhlcnRleHRFbmNyeXB0ZWQ=',
            'iv' => 'Y2hhcmdlZElWYmFzZTY0',
            'mac' => 'YXV0aFRhZ01BQ2Jhc2U2NA==',
        ];

        $response = $this->actingAs($sender, 'sanctum')->postJson('/api/v1/messages/send', $payload);

        $response->assertStatus(201)
                 ->assertJsonStructure([
                     'message' => [
                         'id',
                         'sender_id',
                         'receiver_id',
                         'message_type',
                         'ciphertext',
                         'iv',
                         'mac',
                         'media_url',
                         'encrypted_media_key',
                         'is_delivered',
                         'is_read',
                         'read_at',
                         'created_at',
                     ],
                 ]);

        // Verify database state: ONLY ciphertext, iv, and mac are stored
        $this->assertDatabaseHas('messages', [
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'message_type' => 'text',
            'ciphertext' => 'dGVzdENpcGhlcnRleHRFbmNyeXB0ZWQ=',
            'iv' => 'Y2hhcmdlZElWYmFzZTY0',
            'mac' => 'YXV0aFRhZ01BQ2Jhc2U2NA==',
            'is_read' => false,
        ]);

        // Verify real-time broadcast event is dispatched for recipient
        Event::assertDispatched(MessageSentEvent::class, function (MessageSentEvent $event) use ($receiver, $payload) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$receiver->id}", $channels[0]->name);
            $this->assertEquals('message.sent', $event->broadcastAs());
            $this->assertEquals($payload['ciphertext'], $event->broadcastWith()['message']['ciphertext']);
            return $event->message->receiver_id === $receiver->id;
        });
    }

    public function test_cannot_send_message_to_non_existent_user(): void
    {
        $sender = User::factory()->create();

        $response = $this->actingAs($sender, 'sanctum')->postJson('/api/v1/messages/send', [
            'receiver_id' => 99999,
            'message_type' => 'text',
            'ciphertext' => 'dGVzdA==',
            'iv' => 'aXY=',
            'mac' => 'bWFj',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['receiver_id']);
    }

    public function test_user_cannot_send_message_to_themselves(): void
    {
        $sender = User::factory()->create();

        $response = $this->actingAs($sender, 'sanctum')->postJson('/api/v1/messages/send', [
            'receiver_id' => $sender->id,
            'message_type' => 'text',
            'ciphertext' => 'dGVzdA==',
            'iv' => 'aXY=',
            'mac' => 'bWFj',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['receiver_id']);
    }

    public function test_user_can_retrieve_paginated_encrypted_chat_history(): void
    {
        $userA = User::factory()->create();
        $userB = User::factory()->create();
        $userC = User::factory()->create();

        // Messages between A and B
        Message::factory()->create([
            'sender_id' => $userA->id,
            'receiver_id' => $userB->id,
            'ciphertext' => 'Message 1 from A to B',
            'created_at' => now()->subMinutes(10),
        ]);
        Message::factory()->create([
            'sender_id' => $userB->id,
            'receiver_id' => $userA->id,
            'ciphertext' => 'Message 2 from B to A',
            'created_at' => now()->subMinutes(5),
        ]);

        // Message between A and C (should not appear in A-B conversation)
        Message::factory()->create([
            'sender_id' => $userA->id,
            'receiver_id' => $userC->id,
            'ciphertext' => 'Message to C',
            'created_at' => now()->subMinutes(1),
        ]);

        $response = $this->actingAs($userA, 'sanctum')->getJson("/api/v1/messages/{$userB->id}?per_page=10");

        $response->assertStatus(200)
                 ->assertJsonStructure([
                     'data' => [
                         '*' => [
                             'id',
                             'sender_id',
                             'receiver_id',
                             'ciphertext',
                             'iv',
                             'mac',
                         ],
                     ],
                     'pagination' => [
                         'current_page',
                         'last_page',
                         'per_page',
                         'total',
                     ],
                 ]);

        $data = $response->json('data');
        $this->assertCount(2, $data);
        $this->assertEquals('Message 1 from A to B', $data[0]['ciphertext']);
        $this->assertEquals('Message 2 from B to A', $data[1]['ciphertext']);
    }

    public function test_user_can_mark_message_as_read_and_broadcast_read_receipt(): void
    {
        Event::fake([MessageReadEvent::class]);

        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        $message = Message::factory()->create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'is_read' => false,
            'read_at' => null,
        ]);

        $response = $this->actingAs($receiver, 'sanctum')->postJson("/api/v1/messages/{$message->id}/read");

        $response->assertStatus(200)
                 ->assertJson([
                     'message' => [
                         'id' => $message->id,
                         'is_read' => true,
                     ],
                 ]);

        $this->assertDatabaseHas('messages', [
            'id' => $message->id,
            'is_read' => true,
        ]);

        // Verify read event dispatched to notify sender
        Event::assertDispatched(MessageReadEvent::class, function (MessageReadEvent $event) use ($sender, $message) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$sender->id}", $channels[0]->name);
            $this->assertEquals('message.read', $event->broadcastAs());
            return $event->message->id === $message->id;
        });
    }

    public function test_user_cannot_mark_another_users_incoming_message_as_read(): void
    {
        $sender = User::factory()->create();
        $receiver = User::factory()->create();
        $intruder = User::factory()->create();

        $message = Message::factory()->create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'is_read' => false,
        ]);

        // Intruder tries to mark message as read
        $response = $this->actingAs($intruder, 'sanctum')->postJson("/api/v1/messages/{$message->id}/read");

        $response->assertStatus(404);

        $this->assertDatabaseHas('messages', [
            'id' => $message->id,
            'is_read' => false,
        ]);
    }

    public function test_user_can_mark_entire_conversation_as_read(): void
    {
        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        Message::factory()->count(3)->create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'is_read' => false,
        ]);

        $response = $this->actingAs($receiver, 'sanctum')->postJson("/api/v1/messages/conversation/{$sender->id}/read");

        $response->assertStatus(200)
                 ->assertJson([
                     'marked_count' => 3,
                 ]);

        $this->assertEquals(0, Message::where('receiver_id', $receiver->id)->where('is_read', false)->count());
    }

    public function test_recipient_can_mark_message_as_delivered_and_broadcast_event(): void
    {
        Event::fake([MessageDeliveredEvent::class]);

        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        $message = Message::factory()->create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'is_delivered' => false,
            'is_read' => false,
        ]);

        $response = $this->actingAs($receiver, 'sanctum')->postJson("/api/v1/messages/{$message->id}/delivered");

        $response->assertStatus(200)
                 ->assertJsonPath('message.is_delivered', true);

        $this->assertDatabaseHas('messages', [
            'id' => $message->id,
            'is_delivered' => true,
        ]);

        Event::assertDispatched(MessageDeliveredEvent::class, function (MessageDeliveredEvent $event) use ($sender, $message) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$sender->id}", $channels[0]->name);
            $this->assertEquals('message.delivered', $event->broadcastAs());
            return in_array($message->id, $event->messageIds);
        });
    }

    public function test_user_cannot_mark_another_users_message_as_delivered(): void
    {
        $sender = User::factory()->create();
        $receiver = User::factory()->create();
        $intruder = User::factory()->create();

        $message = Message::factory()->create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'is_delivered' => false,
        ]);

        $response = $this->actingAs($intruder, 'sanctum')->postJson("/api/v1/messages/{$message->id}/delivered");

        $response->assertStatus(404);

        $this->assertDatabaseHas('messages', [
            'id' => $message->id,
            'is_delivered' => false,
        ]);
    }

    public function test_recipient_can_mark_entire_conversation_as_delivered(): void
    {
        Event::fake([MessageDeliveredEvent::class]);

        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        Message::factory()->count(3)->create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'is_delivered' => false,
        ]);

        $response = $this->actingAs($receiver, 'sanctum')->postJson("/api/v1/messages/conversation/{$sender->id}/delivered");

        $response->assertStatus(200)
                 ->assertJson([
                     'delivered_count' => 3,
                 ]);

        $this->assertEquals(0, Message::where('receiver_id', $receiver->id)->where('is_delivered', false)->count());

        Event::assertDispatched(MessageDeliveredEvent::class);
    }
}
