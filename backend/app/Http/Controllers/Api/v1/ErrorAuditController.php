<?php

namespace App\Http\Controllers\Api\v1;

use App\Http\Controllers\Controller;
use App\Services\ErrorAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ErrorAuditController extends Controller
{
    public function __construct(
        protected ErrorAuditService $errorAuditService
    ) {}

    /**
     * Log a client-side Flutter exception or diagnostic event.
     */
    public function logClientError(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'message' => ['required', 'string', 'max:2000'],
            'error_code' => ['nullable', 'string', 'max:64'],
            'exception_class' => ['nullable', 'string', 'max:255'],
            'stack_trace' => ['nullable', 'string'],
            'screen' => ['nullable', 'string', 'max:255'],
            'metadata' => ['nullable', 'array'],
        ]);

        $userId = $request->user()?->id;
        $auditLog = $this->errorAuditService->logClientError($validated, $userId);

        return response()->json([
            'message' => 'Client diagnostic error logged successfully.',
            'reference_code' => $auditLog->reference_code,
            'error_code' => $auditLog->error_code,
        ], 201);
    }

    /**
     * Lookup an error audit record by reference code.
     */
    public function show(string $referenceCode): JsonResponse
    {
        $auditLog = $this->errorAuditService->findByReferenceCode($referenceCode);

        if (!$auditLog) {
            return response()->json([
                'message' => 'Error reference code not found.',
                'reference_code' => $referenceCode,
            ], 404);
        }

        return response()->json([
            'data' => [
                'reference_code' => $auditLog->reference_code,
                'user_id' => $auditLog->user_id,
                'user_name' => $auditLog->user?->name,
                'user_email' => $auditLog->user?->email,
                'error_code' => $auditLog->error_code,
                'exception_class' => $auditLog->exception_class,
                'message' => $auditLog->message,
                'stack_trace' => $auditLog->stack_trace,
                'endpoint' => $auditLog->endpoint,
                'http_method' => $auditLog->http_method,
                'source' => $auditLog->source,
                'created_at' => $auditLog->created_at?->toIso8601String(),
            ],
        ]);
    }
}
