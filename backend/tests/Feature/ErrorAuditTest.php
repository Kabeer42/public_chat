<?php

namespace Tests\Feature;

use App\Models\ErrorAuditLog;
use App\Models\User;
use App\Services\ErrorAuditService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class ErrorAuditTest extends TestCase
{
    use RefreshDatabase;

    public function test_error_audit_service_generates_formatted_reference_code(): void
    {
        $service = app(ErrorAuditService::class);
        $code = $service->generateReferenceCode();

        $this->assertMatchesRegularExpression('/^ERR-[A-Z0-9]{4}-[A-Z0-9]{4}$/', $code);
    }

    public function test_validation_exception_records_audit_log_and_returns_reference_code(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'invalid-email-format',
            // password omitted to trigger validation
        ]);

        $response->assertStatus(422)
            ->assertJsonStructure([
                'message',
                'errors',
                'reference_code',
                'error_code',
            ]);

        $refCode = $response->json('reference_code');
        $this->assertNotNull($refCode);

        $this->assertDatabaseHas('error_audit_logs', [
            'reference_code' => $refCode,
            'error_code' => '422',
        ]);
    }

    public function test_unhandled_exception_returns_500_with_reference_code_and_logs_audit(): void
    {
        Route::get('/api/test-server-error', function () {
            throw new \RuntimeException('Database connection abruptly terminated');
        });

        $response = $this->getJson('/api/test-server-error');

        $response->assertStatus(500)
            ->assertJsonStructure([
                'message',
                'reference_code',
                'error_code',
            ]);

        $refCode = $response->json('reference_code');
        $this->assertNotNull($refCode);

        $log = ErrorAuditLog::where('reference_code', $refCode)->first();
        $this->assertNotNull($log);
        $this->assertEquals('Database connection abruptly terminated', $log->message);
        $this->assertEquals('RuntimeException', class_basename($log->exception_class));
        $this->assertEquals('500', $log->error_code);
        $this->assertEquals('backend', $log->source);
    }

    public function test_sensitive_fields_are_redacted_in_audit_payload(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'not-an-email',
            'password' => 'super_secret_password_123',
            'private_key' => 'secret_private_key_pem',
        ]);

        $refCode = $response->json('reference_code');
        $log = ErrorAuditLog::where('reference_code', $refCode)->first();

        $this->assertNotNull($log);
        $this->assertEquals('[REDACTED]', $log->payload['password']);
        $this->assertEquals('[REDACTED]', $log->payload['private_key']);
    }

    public function test_client_error_logging_endpoint_saves_frontend_diagnostic_event(): void
    {
        $user = User::factory()->create();

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/errors/client', [
            'message' => 'Unable to RTCPeerConnection::setRemoteDescription: SessionDescription is Null',
            'error_code' => 'WEBRTC_SET_REMOTE_DESCRIPTION_ERROR',
            'exception_class' => 'PlatformException',
            'screen' => 'CallScreen',
            'function_name' => 'createAnswer',
            'stack_trace' => '#0 WebRtcService.createAnswer (webrtc_service.dart:102)',
            'metadata' => [
                'call_type' => 'video',
                'has_sdp' => false,
            ],
        ]);

        $response->assertStatus(201)
            ->assertJsonStructure([
                'message',
                'reference_code',
                'error_code',
            ]);

        $refCode = $response->json('reference_code');

        $this->assertDatabaseHas('error_audit_logs', [
            'reference_code' => $refCode,
            'user_id' => $user->id,
            'error_code' => 'WEBRTC_SET_REMOTE_DESCRIPTION_ERROR',
            'exception_class' => 'PlatformException',
            'screen' => 'CallScreen',
            'function_name' => 'createAnswer',
            'source' => 'frontend',
        ]);
    }

    public function test_authenticated_user_can_lookup_error_by_reference_code(): void
    {
        $user = User::factory()->create();
        $auditLog = ErrorAuditLog::create([
            'reference_code' => 'ERR-TEST-9999',
            'user_id' => $user->id,
            'error_code' => '500',
            'exception_class' => 'CustomException',
            'message' => 'Test error message for diagnostics',
            'source' => 'backend',
        ]);

        $response = $this->actingAs($user, 'sanctum')->getJson("/api/v1/errors/{$auditLog->reference_code}");

        $response->assertStatus(200)
            ->assertJson([
                'data' => [
                    'reference_code' => 'ERR-TEST-9999',
                    'error_code' => '500',
                    'message' => 'Test error message for diagnostics',
                ],
            ]);
    }
}
