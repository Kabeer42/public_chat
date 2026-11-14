<?php

namespace Tests\Feature;

use App\Events\CallAnswerEvent;
use App\Events\CallEndedEvent;
use App\Events\CallOfferEvent;
use App\Events\IceCandidateEvent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

class CallSignalingTest extends TestCase
{
    use RefreshDatabase;

    public function test_unauthenticated_user_cannot_access_call_signaling_endpoints(): void
    {
        $this->postJson('/api/v1/call/offer', [])->assertStatus(401);
        $this->postJson('/api/v1/call/answer', [])->assertStatus(401);
        $this->postJson('/api/v1/call/ice-candidate', [])->assertStatus(401);
        $this->postJson('/api/v1/call/end', [])->assertStatus(401);
    }

    public function test_caller_can_emit_call_offer_and_callee_receives_broadcast(): void
    {
        Event::fake([CallOfferEvent::class]);

        $caller = User::factory()->create([
            'name' => 'Alice Caller',
            'public_identity_key' => 'MCowBQYDK2VuAyEAtestAliceKey123=',
            'is_online' => true,
        ]);

        $receiver = User::factory()->create([
            'name' => 'Bob Callee',
            'public_identity_key' => 'MCowBQYDK2VuAyEAtestBobKey456=',
            'is_online' => true,
        ]);

        $sdpOffer = [
            'type' => 'offer',
            'sdp' => 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 5004 UDP/TLS/RTP/SAVPF 111\r\n',
        ];

        $response = $this->actingAs($caller, 'sanctum')->postJson('/api/v1/call/offer', [
            'receiver_id' => $receiver->id,
            'call_type' => 'voice',
            'sdp' => $sdpOffer,
        ]);

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'ringing',
                     'message' => 'Call offer broadcasted successfully.',
                 ])
                 ->assertJsonStructure(['call_id']);

        $callId = $response->json('call_id');
        $this->assertNotEmpty($callId);

        // Verify active call state is cached for caller
        $this->assertEquals($callId, Cache::get("user_in_call_{$caller->id}"));

        // Verify CallOfferEvent is dispatched to receiver's private channel
        Event::assertDispatched(CallOfferEvent::class, function (CallOfferEvent $event) use ($caller, $receiver, $callId, $sdpOffer) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$receiver->id}", $channels[0]->name);
            $this->assertEquals('call.offer', $event->broadcastAs());

            $data = $event->broadcastWith();
            $this->assertEquals($callId, $data['call_id']);
            $this->assertEquals($caller->id, $data['caller_id']);
            $this->assertEquals('Alice Caller', $data['caller_name']);
            $this->assertEquals('MCowBQYDK2VuAyEAtestAliceKey123=', $data['caller_public_key']);
            $this->assertEquals($receiver->id, $data['receiver_id']);
            $this->assertEquals('voice', $data['call_type']);
            $this->assertEquals($sdpOffer, $data['sdp']);

            return true;
        });
    }

    public function test_call_offer_returns_offline_when_recipient_is_offline(): void
    {
        Event::fake([CallOfferEvent::class]);

        $caller = User::factory()->create(['is_online' => true]);
        $offlineReceiver = User::factory()->create(['is_online' => false]);

        $response = $this->actingAs($caller, 'sanctum')->postJson('/api/v1/call/offer', [
            'receiver_id' => $offlineReceiver->id,
            'call_type' => 'video',
            'sdp' => 'v=0\r\no=offline_test\r\n',
        ]);

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'offline',
                     'message' => 'Recipient is currently offline.',
                     'call_id' => null,
                 ]);

        Event::assertNotDispatched(CallOfferEvent::class);
    }

    public function test_call_offer_returns_busy_when_recipient_is_already_in_call(): void
    {
        Event::fake([CallOfferEvent::class]);

        $caller = User::factory()->create(['is_online' => true]);
        $busyReceiver = User::factory()->create(['is_online' => true]);

        // Simulate busy receiver already participating in another call
        Cache::put("user_in_call_{$busyReceiver->id}", 'call-active-999', now()->addMinutes(5));

        $response = $this->actingAs($caller, 'sanctum')->postJson('/api/v1/call/offer', [
            'receiver_id' => $busyReceiver->id,
            'call_type' => 'voice',
            'sdp' => 'v=0\r\no=busy_test\r\n',
        ]);

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'busy',
                     'message' => 'Recipient is currently on another call.',
                     'call_id' => null,
                 ]);

        Event::assertNotDispatched(CallOfferEvent::class);
    }

    public function test_user_cannot_call_themselves(): void
    {
        $user = User::factory()->create(['is_online' => true]);

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/call/offer', [
            'receiver_id' => $user->id,
            'call_type' => 'voice',
            'sdp' => 'v=0\r\no=self_test\r\n',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['receiver_id']);
    }

    public function test_callee_can_emit_call_answer_and_caller_receives_broadcast(): void
    {
        Event::fake([CallAnswerEvent::class]);

        $caller = User::factory()->create(['is_online' => true]);
        $callee = User::factory()->create([
            'name' => 'Bob Callee',
            'is_online' => true,
        ]);

        $callId = 'test-call-uuid-12345';
        $sdpAnswer = [
            'type' => 'answer',
            'sdp' => 'v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\n',
        ];

        $response = $this->actingAs($callee, 'sanctum')->postJson('/api/v1/call/answer', [
            'call_id' => $callId,
            'receiver_id' => $caller->id,
            'sdp' => $sdpAnswer,
        ]);

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'connected',
                     'message' => 'Call answer broadcasted successfully.',
                     'call_id' => $callId,
                 ]);

        // Verify active call state is registered for both peers
        $this->assertEquals($callId, Cache::get("user_in_call_{$callee->id}"));
        $this->assertEquals($callId, Cache::get("user_in_call_{$caller->id}"));

        Event::assertDispatched(CallAnswerEvent::class, function (CallAnswerEvent $event) use ($caller, $callee, $callId, $sdpAnswer) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$caller->id}", $channels[0]->name);
            $this->assertEquals('call.answer', $event->broadcastAs());

            $data = $event->broadcastWith();
            $this->assertEquals($callId, $data['call_id']);
            $this->assertEquals($callee->id, $data['callee_id']);
            $this->assertEquals('Bob Callee', $data['callee_name']);
            $this->assertEquals($caller->id, $data['receiver_id']);
            $this->assertEquals($sdpAnswer, $data['sdp']);

            return true;
        });
    }

    public function test_peers_can_exchange_ice_candidates(): void
    {
        Event::fake([IceCandidateEvent::class]);

        $peerA = User::factory()->create(['is_online' => true]);
        $peerB = User::factory()->create(['is_online' => true]);

        $callId = 'test-call-uuid-ice-123';
        $candidatePayload = [
            'candidate' => 'candidate:842163049 1 udp 1677729535 192.168.1.100 56789 typ srflx raddr 192.168.1.100 rport 56789',
            'sdpMid' => '0',
            'sdpMLineIndex' => 0,
        ];

        $response = $this->actingAs($peerA, 'sanctum')->postJson('/api/v1/call/ice-candidate', [
            'call_id' => $callId,
            'receiver_id' => $peerB->id,
            'candidate' => $candidatePayload,
        ]);

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'success',
                     'message' => 'ICE candidate relayed successfully.',
                 ]);

        Event::assertDispatched(IceCandidateEvent::class, function (IceCandidateEvent $event) use ($peerA, $peerB, $callId, $candidatePayload) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$peerB->id}", $channels[0]->name);
            $this->assertEquals('call.ice-candidate', $event->broadcastAs());

            $data = $event->broadcastWith();
            $this->assertEquals($callId, $data['call_id']);
            $this->assertEquals($peerA->id, $data['sender_id']);
            $this->assertEquals($peerB->id, $data['receiver_id']);
            $this->assertEquals($candidatePayload, $data['candidate']);

            return true;
        });
    }

    public function test_call_end_broadcasts_call_ended_event_and_clears_active_state(): void
    {
        Event::fake([CallEndedEvent::class]);

        $peerA = User::factory()->create(['is_online' => true]);
        $peerB = User::factory()->create(['is_online' => true]);

        $callId = 'test-call-uuid-end-456';
        Cache::put("user_in_call_{$peerA->id}", $callId, now()->addMinutes(10));
        Cache::put("user_in_call_{$peerB->id}", $callId, now()->addMinutes(10));

        $response = $this->actingAs($peerA, 'sanctum')->postJson('/api/v1/call/end', [
            'call_id' => $callId,
            'receiver_id' => $peerB->id,
            'reason' => 'hung_up',
        ]);

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'ended',
                     'message' => 'Call ended successfully.',
                     'reason' => 'hung_up',
                 ]);

        // Verify active call state is cleared for both peers
        $this->assertFalse(Cache::has("user_in_call_{$peerA->id}"));
        $this->assertFalse(Cache::has("user_in_call_{$peerB->id}"));

        Event::assertDispatched(CallEndedEvent::class, function (CallEndedEvent $event) use ($peerA, $peerB, $callId) {
            $channels = $event->broadcastOn();
            $this->assertCount(1, $channels);
            $this->assertEquals("private-user.{$peerB->id}", $channels[0]->name);
            $this->assertEquals('call.ended', $event->broadcastAs());

            $data = $event->broadcastWith();
            $this->assertEquals($callId, $data['call_id']);
            $this->assertEquals($peerA->id, $data['sender_id']);
            $this->assertEquals($peerB->id, $data['receiver_id']);
            $this->assertEquals('hung_up', $data['reason']);

            return true;
        });
    }
}
