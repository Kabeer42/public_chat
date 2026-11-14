<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class SettingsTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_update_profile_name_and_email(): void
    {
        $user = User::factory()->create([
            'name' => 'Original Name',
            'email' => 'original@example.com',
        ]);

        $response = $this->actingAs($user, 'sanctum')->putJson('/api/v1/auth/profile', [
            'name' => 'Updated Name',
            'email' => 'updated@example.com',
        ]);

        $response->assertStatus(200)
            ->assertJson([
                'message' => 'Profile updated successfully',
                'user' => [
                    'id' => $user->id,
                    'name' => 'Updated Name',
                    'email' => 'updated@example.com',
                ],
            ]);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Updated Name',
            'email' => 'updated@example.com',
        ]);
    }

    public function test_user_cannot_update_email_to_another_users_email(): void
    {
        $existing = User::factory()->create(['email' => 'existing@example.com']);
        $user = User::factory()->create(['email' => 'myemail@example.com']);

        $response = $this->actingAs($user, 'sanctum')->putJson('/api/v1/auth/profile', [
            'name' => 'My Name',
            'email' => 'existing@example.com',
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['email']);
    }

    public function test_user_can_change_password_with_valid_current_password(): void
    {
        $user = User::factory()->create([
            'password' => Hash::make('old_secret_123'),
        ]);

        $response = $this->actingAs($user, 'sanctum')->putJson('/api/v1/auth/password', [
            'current_password' => 'old_secret_123',
            'new_password' => 'new_secret_456',
            'new_password_confirmation' => 'new_secret_456',
        ]);

        $response->assertStatus(200)
            ->assertJson([
                'message' => 'Password updated successfully',
            ]);

        $this->assertTrue(Hash::check('new_secret_456', $user->fresh()->password));
    }

    public function test_user_cannot_change_password_with_incorrect_current_password(): void
    {
        $user = User::factory()->create([
            'password' => Hash::make('correct_password_123'),
        ]);

        $response = $this->actingAs($user, 'sanctum')->putJson('/api/v1/auth/password', [
            'current_password' => 'wrong_password_999',
            'new_password' => 'new_secret_456',
            'new_password_confirmation' => 'new_secret_456',
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['current_password']);
    }

    public function test_user_can_toggle_show_last_seen_privacy(): void
    {
        $user = User::factory()->create([
            'show_last_seen' => true,
        ]);

        $response = $this->actingAs($user, 'sanctum')->putJson('/api/v1/auth/privacy', [
            'show_last_seen' => false,
        ]);

        $response->assertStatus(200)
            ->assertJson([
                'message' => 'Privacy settings updated successfully',
                'user' => [
                    'id' => $user->id,
                    'show_last_seen' => false,
                ],
            ]);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'show_last_seen' => false,
        ]);
    }

    public function test_peer_cannot_see_last_seen_when_privacy_is_disabled(): void
    {
        $privateUser = User::factory()->create([
            'name' => 'Private User',
            'last_seen_at' => now()->subMinutes(10),
            'show_last_seen' => false,
        ]);

        $viewer = User::factory()->create();

        // 1. Viewer lists users directory
        $response = $this->actingAs($viewer, 'sanctum')->getJson('/api/v1/users');
        $response->assertStatus(200);

        $userData = collect($response->json('users'))->firstWhere('id', $privateUser->id);
        $this->assertNotNull($userData);
        $this->assertNull($userData['last_seen_at']); // Hidden due to show_last_seen = false

        // 2. Private user checks their own profile via /me -> sees their last_seen_at
        $selfResponse = $this->actingAs($privateUser, 'sanctum')->getJson('/api/v1/auth/me');
        $selfResponse->assertStatus(200);
        $this->assertNotNull($selfResponse->json('user.last_seen_at'));
    }
}
