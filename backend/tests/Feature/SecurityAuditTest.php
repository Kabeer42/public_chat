<?php

namespace Tests\Feature;

use App\Events\MessageSentEvent;
use App\Models\Message;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class SecurityAuditTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'broadcasting.default' => 'reverb',
            'broadcasting.connections.reverb.key' => 'chatapp_key',
            'broadcasting.connections.reverb.secret' => 'chatapp_secret',
            'broadcasting.connections.reverb.app_id' => 'chatapp',
        ]);

        require base_path('routes/channels.php');
    }

    /**
     * 1. Audit Database Schema: Verify ZERO plaintext, private keys, or raw media keys in tables.
     */
    public function test_database_schema_enforces_zero_knowledge_and_no_private_keys(): void
    {
        // Audit 'users' table
        $userColumns = Schema::getColumnListing('users');
        $forbiddenUserColumns = [
            'private_key',
            'private_identity_key',
            'identity_private_key',
            'secret_key',
            'seed',
            'mnemonic',
        ];
        foreach ($forbiddenUserColumns as $forbidden) {
            $this->assertNotContains(
                $forbidden,
                $userColumns,
                "SECURITY VIOLATION: Column '{$forbidden}' found in 'users' table!"
            );
        }

        // Must contain public keys only
        $this->assertContains('public_identity_key', $userColumns);
        $this->assertContains('public_signed_prekey', $userColumns);

        // Audit 'messages' table
        $messageColumns = Schema::getColumnListing('messages');
        $forbiddenMessageColumns = [
            'body',
            'content',
            'text',
            'message',
            'plaintext',
            'raw_media_key',
            'media_key',
        ];
        foreach ($forbiddenMessageColumns as $forbidden) {
            $this->assertNotContains(
                $forbidden,
                $messageColumns,
                "SECURITY VIOLATION: Plaintext column '{$forbidden}' found in 'messages' table!"
            );
        }

        // Must contain cryptographic artifacts only
        $this->assertContains('ciphertext', $messageColumns);
        $this->assertContains('iv', $messageColumns);
        $this->assertContains('mac', $messageColumns);
        $this->assertContains('encrypted_media_key', $messageColumns);
        $this->assertContains('media_url', $messageColumns);
    }

    /**
     * 2. Audit In-Transit & At-Rest Storage: Backend never stores plaintext even if an attacker passes plaintext fields.
     */
    public function test_message_api_stores_only_ciphertext_and_ignores_injected_plaintext(): void
    {
        Event::fake([MessageSentEvent::class]);

        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        $token = $sender->createToken('auth-token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/v1/messages/send', [
                'receiver_id' => $receiver->id,
                'ciphertext' => 'e2ee_base64_encrypted_payload_sample==',
                'iv' => 'base64_iv_12bytes==',
                'mac' => 'base64_mac_16bytes==',
                'message_type' => 'text',
                'plaintext' => 'INJECTED_PLAINTEXT_SHOULD_BE_IGNORED',
                'body' => 'INJECTED_BODY_SHOULD_BE_IGNORED',
                'content' => 'INJECTED_CONTENT_SHOULD_BE_IGNORED',
            ]);

        $response->assertStatus(201);

        // Verify database row has zero plaintext
        $savedMessage = Message::first();
        $this->assertNotNull($savedMessage);
        $this->assertEquals('e2ee_base64_encrypted_payload_sample==', $savedMessage->ciphertext);
        $this->assertEquals('base64_iv_12bytes==', $savedMessage->iv);
        $this->assertEquals('base64_mac_16bytes==', $savedMessage->mac);

        // Ensure database row array contains zero plaintext keys
        $array = $savedMessage->toArray();
        $this->assertArrayNotHasKey('plaintext', $array);
        $this->assertArrayNotHasKey('body', $array);
        $this->assertArrayNotHasKey('content', $array);

        // Ensure API response JSON contains no plaintext fields
        $json = $response->json('message');
        $this->assertArrayNotHasKey('plaintext', $json);
        $this->assertArrayNotHasKey('body', $json);
        $this->assertArrayNotHasKey('content', $json);
    }

    /**
     * 3. Audit Media Storage: Media blobs are stored byte-for-byte as raw ciphertext without metadata extraction.
     */
    public function test_media_storage_is_opaque_binary_blob_with_no_exif_or_thumbnail_generation(): void
    {
        Storage::fake('encrypted_media');

        $user = User::factory()->create();
        $token = $user->createToken('auth-token')->plainTextToken;

        // Create an encrypted fake ciphertext payload (random bytes)
        $opaqueCiphertext = random_bytes(1024 * 16); // 16KB of opaque encrypted data
        $fakeFile = UploadedFile::fake()->createWithContent('encrypted_media.enc', $opaqueCiphertext);

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/v1/media/upload', [
                'file' => $fakeFile,
            ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'message',
                'media_id',
                'url',
                'size',
            ]);

        $mediaId = $response->json('media_id');
        $fileName = "{$mediaId}.enc";

        // Verify exact byte preservation in storage
        Storage::disk('encrypted_media')->assertExists($fileName);
        $storedContent = Storage::disk('encrypted_media')->get($fileName);
        $this->assertEquals(
            $opaqueCiphertext,
            $storedContent,
            "SECURITY AUDIT FAILED: Stored media binary blob does not match exact uploaded ciphertext!"
        );

        // Ensure no unencrypted thumbnails, previews, or extracted metadata were written to disk
        $allFiles = Storage::disk('encrypted_media')->allFiles();
        $this->assertCount(1, $allFiles);
        $this->assertEquals($fileName, $allFiles[0]);
    }

    /**
     * 4. Audit Path Traversal Protection: Ensure media download blocks ../ and invalid traversal attempts.
     */
    public function test_media_download_strictly_blocks_directory_traversal(): void
    {
        Storage::fake('encrypted_media');
        $user = User::factory()->create();
        $token = $user->createToken('auth-token')->plainTextToken;

        // Path traversal and non-UUID attacks
        $traversalAttempts = [
            '..%2F..%2Fetc%2Fpasswd',
            'etc_passwd',
            '00000000-0000-0000-0000-000000000000/../../.env',
            '../../../app/Models/User.php',
            'invalid-uuid-format',
            'SELECT * FROM users',
        ];

        foreach ($traversalAttempts as $attempt) {
            $response = $this->withHeader('Authorization', "Bearer {$token}")
                ->get("/api/v1/media/{$attempt}");

            $this->assertContains(
                $response->getStatusCode(),
                [400, 404],
                "SECURITY AUDIT FAILED: Path traversal payload '{$attempt}' returned code {$response->getStatusCode()}"
            );
        }
    }

    /**
     * 5. Audit Authentication & Channel Isolation: Unauthorized users cannot access private channels or API.
     */
    public function test_api_and_websocket_channel_auth_strict_isolation(): void
    {
        // 1. Unauthenticated API access rejected
        $this->getJson('/api/v1/users')->assertStatus(401);
        $this->getJson('/api/v1/messages/1')->assertStatus(401);
        $this->postJson('/api/v1/messages/send', [])->assertStatus(401);
        $this->postJson('/api/v1/call/offer', [])->assertStatus(401);
        $this->postJson('/api/v1/broadcasting/auth', [
            'channel_name' => 'private-user.1',
            'socket_id' => '1234.5678',
        ])->assertStatus(401);

        // 2. Private channel authorization
        $alice = User::factory()->create();
        $bob = User::factory()->create();

        $aliceToken = $alice->createToken('alice-token')->plainTextToken;

        // Alice attempts to listen on Bob's private channel
        $response = $this->withHeader('Authorization', "Bearer {$aliceToken}")
            ->postJson('/api/v1/broadcasting/auth', [
                'channel_name' => "private-user.{$bob->id}",
                'socket_id' => '12345.67890',
            ]);

        $response->assertStatus(403);

        // Alice listens on her own private channel
        $validResponse = $this->withHeader('Authorization', "Bearer {$aliceToken}")
            ->postJson('/api/v1/broadcasting/auth', [
                'channel_name' => "private-user.{$alice->id}",
                'socket_id' => '12345.67890',
            ]);

        $validResponse->assertStatus(200);
    }
}
