<?php

namespace Tests\Feature;

use Tests\TestCase;

class HealthCheckTest extends TestCase
{
    /**
     * Test health check endpoint returns status 200 and expected payload.
     */
    public function test_health_check_returns_ok(): void
    {
        $response = $this->getJson('/api/v1/health');

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'ok',
                     'service' => 'ChatAPP Backend',
                     'version' => '1.0.0',
                 ])
                 ->assertJsonStructure([
                     'status',
                     'service',
                     'timestamp',
                     'version',
                     'environment',
                 ]);
    }
}
