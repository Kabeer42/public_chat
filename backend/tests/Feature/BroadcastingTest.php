<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BroadcastingTest extends TestCase
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

    public function test_unauthenticated_user_cannot_access_channel_auth(): void
    {
        $response = $this->postJson('/api/v1/broadcasting/auth', [
            'channel_name' => 'private-user.1',
            'socket_id' => '1234.5678',
        ]);

        $response->assertStatus(401);
    }

    public function test_user_can_authenticate_own_private_channel(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/broadcasting/auth', [
            'channel_name' => "private-user.{$user->id}",
            'socket_id' => '1234.5678',
        ]);

        $response->assertStatus(200)
                 ->assertJsonStructure(['auth']);
    }

    public function test_user_cannot_authenticate_another_users_private_channel(): void
    {
        $userA = User::factory()->create();
        $userB = User::factory()->create();

        $response = $this->actingAs($userA, 'sanctum')->postJson('/api/v1/broadcasting/auth', [
            'channel_name' => "private-user.{$userB->id}",
            'socket_id' => '1234.5678',
        ]);

        $response->assertStatus(403);
    }

    public function test_user_can_authenticate_presence_call_channel(): void
    {
        $user = User::factory()->create([
            'name' => 'Alice Test',
            'public_identity_key' => 'MCowBQYDK2VuAyEAtestAlice1234=',
        ]);

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/broadcasting/auth', [
            'channel_name' => 'presence-call.call_abc123',
            'socket_id' => '1234.5678',
        ]);

        $response->assertStatus(200)
                 ->assertJsonStructure([
                     'auth',
                     'channel_data',
                 ]);

        $channelData = json_decode($response->json('channel_data'), true);
        $this->assertEquals($user->id, $channelData['user_id']);
        $this->assertEquals('Alice Test', $channelData['user_info']['name']);
        $this->assertEquals('MCowBQYDK2VuAyEAtestAlice1234=', $channelData['user_info']['public_identity_key']);
    }
}
