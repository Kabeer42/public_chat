<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class MediaTest extends TestCase
{
    use RefreshDatabase;

    public function test_unauthenticated_user_cannot_access_media_endpoints(): void
    {
        $this->postJson('/api/v1/media/upload')->assertStatus(401);
        $this->getJson('/api/v1/media/12345678-1234-1234-1234-123456789abc')->assertStatus(401);
    }

    public function test_user_can_upload_encrypted_media_blob(): void
    {
        Storage::fake('encrypted_media');

        $user = User::factory()->create();
        $binaryData = random_bytes(256); // Raw scrambled encrypted binary bytes

        $file = UploadedFile::fake()->createWithContent('payload.enc', $binaryData);

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/media/upload', [
            'file' => $file,
        ]);

        $response->assertStatus(201)
                 ->assertJsonStructure([
                     'message',
                     'media_id',
                     'url',
                     'size',
                 ]);

        $mediaId = $response->json('media_id');
        $this->assertTrue(\Illuminate\Support\Str::isUuid($mediaId));
        $this->assertEquals("/api/v1/media/{$mediaId}", $response->json('url'));

        // Verify encrypted file exists on disk with matching binary content
        Storage::disk('encrypted_media')->assertExists("{$mediaId}.enc");
        $storedContent = Storage::disk('encrypted_media')->get("{$mediaId}.enc");
        $this->assertEquals($binaryData, $storedContent);
    }

    public function test_upload_validation_fails_when_file_is_missing(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/media/upload', []);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['file']);
    }

    public function test_user_can_download_exact_encrypted_binary_blob(): void
    {
        Storage::fake('encrypted_media');

        $user = User::factory()->create();
        $uuid = 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d';
        $encryptedContent = "ZERO_KNOWLEDGE_AES_GCM_ENCRYPTED_BLOB_STREAM_XYZ";

        Storage::disk('encrypted_media')->put("{$uuid}.enc", $encryptedContent);

        $response = $this->actingAs($user, 'sanctum')->get("/api/v1/media/{$uuid}");

        $response->assertStatus(200);
        $this->assertEquals('application/octet-stream', $response->headers->get('Content-Type'));
        $this->assertStringContainsString("{$uuid}.enc", $response->headers->get('Content-Disposition'));
        $this->assertEquals($encryptedContent, file_get_contents($response->getFile()->getPathname()));
    }

    public function test_download_returns_404_for_non_existent_media(): void
    {
        Storage::fake('encrypted_media');

        $user = User::factory()->create();
        $nonExistentUuid = '00000000-0000-0000-0000-000000000000';

        $response = $this->actingAs($user, 'sanctum')->getJson("/api/v1/media/{$nonExistentUuid}");

        $response->assertStatus(404);
    }

    public function test_download_prevents_path_traversal_attacks(): void
    {
        Storage::fake('encrypted_media');

        $user = User::factory()->create();

        // Attempts to pass directory traversal paths
        $this->actingAs($user, 'sanctum')->getJson('/api/v1/media/..%2F..%2Fetc%2Fpasswd')->assertStatus(404);
        $this->actingAs($user, 'sanctum')->getJson('/api/v1/media/invalid-uuid-string')->assertStatus(404);
    }
}
