<?php

namespace App\Services;

use App\Models\ErrorAuditLog;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Throwable;

class ErrorAuditService
{
    /**
     * Generate a unique, human-friendly error reference code.
     * Format: ERR-XXXX-XXXX
     */
    public function generateReferenceCode(): string
    {
        do {
            $part1 = strtoupper(Str::random(4));
            $part2 = strtoupper(Str::random(4));
            $code = "ERR-{$part1}-{$part2}";
        } while (ErrorAuditLog::where('reference_code', $code)->exists());

        return $code;
    }

    /**
     * Log a backend exception to the error_audit_logs table.
     */
    public function logException(Throwable $e, ?Request $request = null, ?int $userId = null): string
    {
        $referenceCode = $this->generateReferenceCode();

        $statusCode = 500;
        if ($e instanceof \Illuminate\Validation\ValidationException) {
            $statusCode = 422;
        } elseif ($e instanceof \Illuminate\Auth\AuthenticationException) {
            $statusCode = 401;
        } elseif ($e instanceof HttpExceptionInterface) {
            $statusCode = $e->getStatusCode();
        } elseif ($e->getCode() > 0 && $e->getCode() < 600) {
            $statusCode = $e->getCode();
        }

        $endpoint = null;
        $httpMethod = null;
        $ipAddress = null;
        $payload = null;

        if ($request) {
            $endpoint = $request->fullUrl();
            $httpMethod = $request->method();
            $ipAddress = $request->ip();
            $payload = $this->sanitizePayload($request->all());

            if (!$userId && $request->user()) {
                $userId = $request->user()->id;
            }
        }

        // Truncate stack trace to 8000 characters to prevent database bloat while keeping full diagnostic value
        $stackTrace = substr($e->getTraceAsString(), 0, 8000);

        ErrorAuditLog::create([
            'reference_code' => $referenceCode,
            'user_id' => $userId,
            'error_code' => (string) $statusCode,
            'exception_class' => get_class($e),
            'message' => $e->getMessage() ?: 'No exception message provided.',
            'stack_trace' => $stackTrace,
            'endpoint' => $endpoint,
            'http_method' => $httpMethod,
            'ip_address' => $ipAddress,
            'payload' => $payload,
            'source' => 'backend',
        ]);

        return $referenceCode;
    }

    /**
     * Log a client-side Flutter diagnostic error to the database.
     */
    public function logClientError(array $data, ?int $userId = null): ErrorAuditLog
    {
        $referenceCode = $this->generateReferenceCode();

        return ErrorAuditLog::create([
            'reference_code' => $referenceCode,
            'user_id' => $userId ?? ($data['user_id'] ?? null),
            'error_code' => isset($data['error_code']) ? (string) $data['error_code'] : 'CLIENT_ERROR',
            'exception_class' => $data['exception_class'] ?? 'FlutterException',
            'message' => $data['message'] ?? 'Client encountered an error.',
            'stack_trace' => isset($data['stack_trace']) ? substr((string) $data['stack_trace'], 0, 8000) : null,
            'endpoint' => $data['screen'] ?? $data['endpoint'] ?? null,
            'http_method' => 'CLIENT',
            'ip_address' => request()->ip(),
            'payload' => isset($data['metadata']) ? $this->sanitizePayload((array) $data['metadata']) : null,
            'source' => 'frontend',
        ]);
    }

    /**
     * Retrieve audit record by reference code.
     */
    public function findByReferenceCode(string $referenceCode): ?ErrorAuditLog
    {
        return ErrorAuditLog::with('user:id,name,email')
            ->where('reference_code', $referenceCode)
            ->first();
    }

    /**
     * Sanitize array to strip sensitive fields.
     */
    protected function sanitizePayload(array $data): array
    {
        $sensitiveKeys = ['password', 'password_confirmation', 'private_key', 'e2ee_private_key', 'token', 'secret', 'authorization'];

        array_walk_recursive($data, function (&$value, $key) use ($sensitiveKeys) {
            if (in_array(strtolower($key), $sensitiveKeys, true)) {
                $value = '[REDACTED]';
            }
        });

        return $data;
    }
}
