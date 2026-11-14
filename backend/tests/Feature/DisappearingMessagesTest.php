<?php

namespace Tests\Feature;

use App\Events\DisappearingDurationUpdatedEvent;
use App\Models\ConversationSetting;
use App\Models\Message;
use App\Models\User;
use App\Services\MediaService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class DisappearingMessagesTest extends TestCase
{
    use RefreshDatabase;

    protected User $sender;
    protected User $receiver;

    protected function setUp(): void
    {
        parent::setUp();

        $this->sender = User::factory()->create(['name' => 'Alice']);
        $this->receiver = User::factory()->create(['name' => 'Bob']);
    }

    public function test_can_set_and_get_disappearing_message_duration(): void
    {
        Event::fake([DisappearingDurationUpdatedEvent::class]);

        $response = $this->actingAs($this->sender, 'sanctum')
            ->postJson("/api/v1/conversations/{$this->receiver->id}/disappearing", [
                'duration' => 43200, // 12 hours
            ]);

        $response->assertStatus(200)
            ->assertJson([
                'disappearing_duration_seconds' => 43200,
            ]);

        Event::assertDispatched(DisappearingDurationUpdatedEvent::class, function ($event) {
            return $event->receiverId === $this->receiver->id &&
                   $event->peerId === $this->sender->id &&
                   $event->durationSeconds === 43200;
        });

        // Verify GET endpoint returns updated duration
        $getResponse = $this->actingAs($this->receiver, 'sanctum')
            ->getJson("/api/v1/conversations/{$this->sender->id}/disappearing");

        $getResponse->assertStatus(200)
            ->assertJson([
                'disappearing_duration_seconds' => 43200,
            ]);
    }

    public function test_sent_messages_inherit_expiration_when_disappearing_is_active(): void
    {
        // Set 12 hours duration (43200 seconds)
        ConversationSetting::setDuration($this->sender->id, $this->receiver->id, 43200);

        $sendResponse = $this->actingAs($this->sender, 'sanctum')
            ->postJson('/api/v1/messages/send', [
                'receiver_id' => $this->receiver->id,
                'ciphertext' => base64_encode('opaque-encrypted-content'),
                'iv' => base64_encode(random_bytes(12)),
                'mac' => base64_encode(random_bytes(16)),
                'message_type' => 'text',
            ]);

        $sendResponse->assertStatus(201);
        $messageData = $sendResponse->json('message');

        $this->assertNotNull($messageData['expires_at']);
        $expiresAt = \Carbon\Carbon::parse($messageData['expires_at']);
        $this->assertTrue($expiresAt->isFuture());
    }

    public function test_expired_messages_are_excluded_from_conversation_history(): void
    {
        // Message 1: Not expired
        Message::create([
            'sender_id' => $this->sender->id,
            'receiver_id' => $this->receiver->id,
            'message_type' => 'text',
            'ciphertext' => 'cipher1',
            'iv' => 'iv1',
            'mac' => 'mac1',
            'expires_at' => now()->addHour(),
        ]);

        // Message 2: Expired 10 minutes ago
        Message::create([
            'sender_id' => $this->sender->id,
            'receiver_id' => $this->receiver->id,
            'message_type' => 'text',
            'ciphertext' => 'cipher2',
            'iv' => 'iv2',
            'mac' => 'mac2',
            'expires_at' => now()->subMinutes(10),
        ]);

        $response = $this->actingAs($this->sender, 'sanctum')
            ->getJson("/api/v1/messages/{$this->receiver->id}");

        $response->assertStatus(200);
        $data = $response->json('data');

        $this->assertCount(1, $data);
        $this->assertEquals('cipher1', $data[0]['ciphertext']);
    }

    public function test_prune_command_hard_deletes_expired_messages_and_media(): void
    {
        Storage::fake('encrypted_media');
        $mediaService = app(MediaService::class);
        $file = UploadedFile::fake()->create('encrypted.bin', 100);
        $storedBlob = $mediaService->storeEncryptedBlob($file);

        // Expired message with media
        $expiredMsg = Message::create([
            'sender_id' => $this->sender->id,
            'receiver_id' => $this->receiver->id,
            'message_type' => 'image',
            'ciphertext' => 'cipher-media',
            'iv' => 'iv-media',
            'mac' => 'mac-media',
            'media_url' => $storedBlob['url'],
            'expires_at' => now()->subMinute(),
        ]);

        // Active message
        $activeMsg = Message::create([
            'sender_id' => $this->sender->id,
            'receiver_id' => $this->receiver->id,
            'message_type' => 'text',
            'ciphertext' => 'active-cipher',
            'iv' => 'iv-active',
            'mac' => 'mac-active',
            'expires_at' => now()->addHours(2),
        ]);

        $this->artisan('chat:prune-disappearing')
            ->expectsOutputToContain('Pruned 1 expired messages and purged 1 encrypted media files.')
            ->assertExitCode(0);

        // Verify expired message is gone from database
        $this->assertDatabaseMissing('messages', ['id' => $expiredMsg->id]);
        $this->assertDatabaseHas('messages', ['id' => $activeMsg->id]);

        // Verify physical file was deleted
        Storage::disk('encrypted_media')->assertMissing("{$storedBlob['media_id']}.enc");
    }
}
