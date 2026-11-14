<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_register(): void
    {
        $payload = [
            'name' => 'Alice Johnson',
            'email' => 'alice@example.com',
            'password' => 'SecretPassword123',
            'public_identity_key' => 'MCowBQYDK2VuAyEAtestAlicePublicKey1234567890=',
            'public_signed_prekey' => 'MCowBQYDK2VuAyEAtestAliceSignedPrekey12345678=',
        ];

        $response = $this->postJson('/api/v1/auth/register', $payload);

        $response->assertStatus(201)
                 ->assertJsonStructure([
                     'message',
                     'token',
                     'user' => [
                         'id',
                         'name',
                         'email',
                         'public_identity_key',
                         'public_signed_prekey',
                         'is_online',
                         'created_at',
                     ],
                 ]);

        $this->assertDatabaseHas('users', [
            'email' => 'alice@example.com',
            'name' => 'Alice Johnson',
            'public_identity_key' => 'MCowBQYDK2VuAyEAtestAlicePublicKey1234567890=',
        ]);
    }

    public function test_registration_validation_fails_for_duplicate_email(): void
    {
        User::factory()->create(['email' => 'duplicate@example.com']);

        $response = $this->postJson('/api/v1/auth/register', [
            'name' => 'Duplicate User',
            'email' => 'duplicate@example.com',
            'password' => 'SecretPassword123',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['email']);
    }

    public function test_user_can_login_with_valid_credentials(): void
    {
        $user = User::factory()->create([
            'email' => 'bob@example.com',
            'password' => 'SecretPassword123',
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'bob@example.com',
            'password' => 'SecretPassword123',
        ]);

        $response->assertStatus(200)
                 ->assertJsonStructure([
                     'message',
                     'token',
                     'user' => ['id', 'name', 'email', 'is_online'],
                 ]);

        $this->assertTrue($user->fresh()->is_online);
    }

    public function test_login_fails_with_invalid_credentials(): void
    {
        User::factory()->create([
            'email' => 'bob@example.com',
            'password' => 'SecretPassword123',
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'bob@example.com',
            'password' => 'WrongPassword',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['email']);
    }

    public function test_me_endpoint_returns_current_user(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user, 'sanctum')->getJson('/api/v1/auth/me');

        $response->assertStatus(200)
                 ->assertJson([
                     'user' => [
                         'id' => $user->id,
                         'email' => $user->email,
                     ],
                 ]);
    }

    public function test_logout_revokes_token_and_sets_offline(): void
    {
        $user = User::factory()->create(['is_online' => true]);
        $token = $user->createToken('test_token')->plainTextToken;

        $response = $this->withHeader('Authorization', 'Bearer ' . $token)
                         ->postJson('/api/v1/auth/logout');

        $response->assertStatus(200)
                 ->assertJson(['message' => 'Logged out successfully']);

        $this->assertFalse($user->fresh()->is_online);
        $this->assertCount(0, $user->tokens);
    }

    public function test_users_directory_lists_other_contacts(): void
    {
        $currentUser = User::factory()->create(['name' => 'Charlie']);
        $otherUser1 = User::factory()->create(['name' => 'David']);
        $otherUser2 = User::factory()->create(['name' => 'Eve']);

        $response = $this->actingAs($currentUser, 'sanctum')->getJson('/api/v1/users');

        $response->assertStatus(200)
                 ->assertJsonStructure([
                     'users' => [
                         '*' => ['id', 'name', 'email', 'is_online', 'public_identity_key'],
                     ],
                 ]);

        $userIds = collect($response->json('users'))->pluck('id')->all();
        $this->assertContains($otherUser1->id, $userIds);
        $this->assertContains($otherUser2->id, $userIds);
        $this->assertNotContains($currentUser->id, $userIds);
    }

    public function test_publish_and_retrieve_e2ee_public_key(): void
    {
        $userA = User::factory()->create();
        $userB = User::factory()->create();

        // User A publishes key
        $newKey = 'MCowBQYDK2VuAyEAnewX25519KeyForUserA123456789012=';
        $publishResponse = $this->actingAs($userA, 'sanctum')
                                ->postJson('/api/v1/keys/publish', [
                                    'public_identity_key' => $newKey,
                                ]);

        $publishResponse->assertStatus(200);

        // User B retrieves User A's key
        $getKeyResponse = $this->actingAs($userB, 'sanctum')
                               ->getJson("/api/v1/keys/{$userA->id}");

        $getKeyResponse->assertStatus(200)
                       ->assertJson([
                           'user_id' => $userA->id,
                           'public_identity_key' => $newKey,
                       ]);
    }
}
