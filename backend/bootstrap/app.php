<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        channels: __DIR__.'/../routes/channels.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Trust all proxies for Cloudflare Tunnel / Ngrok / Dev Tunnels
        $middleware->trustProxies(at: '*');
        $middleware->trimStrings(except: [
            'sdp',
            'sdp_offer',
            'sdp_answer',
            'current_password',
            'password',
            'password_confirmation',
        ]);

        // Fix Dev Tunnels / reverse-proxy keep-alive hangs on PHP built-in server
        $middleware->append(\App\Http\Middleware\EnsureContentLength::class);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function (\Throwable $e, \Illuminate\Http\Request $request) {
            if ($request->is('api/*') || $request->expectsJson()) {
                if ($e instanceof \Illuminate\Auth\AuthenticationException) {
                    return response()->json([
                        'message' => 'Unauthenticated.',
                        'error_code' => 401,
                    ], 401);
                }

                $auditService = app(\App\Services\ErrorAuditService::class);
                $refCode = $auditService->logException($e, $request);

                if ($e instanceof \Illuminate\Validation\ValidationException) {
                    return response()->json([
                        'message' => $e->getMessage(),
                        'errors' => $e->errors(),
                        'reference_code' => $refCode,
                        'error_code' => 422,
                    ], 422);
                }

                $status = 500;
                if ($e instanceof \Symfony\Component\HttpKernel\Exception\HttpExceptionInterface) {
                    $status = $e->getStatusCode();
                }

                return response()->json([
                    'message' => $e->getMessage() ?: 'An unexpected server error occurred.',
                    'reference_code' => $refCode,
                    'error_code' => $status,
                ], $status);
            }
        });
    })->create();
