<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureContentLength
{
    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        if (method_exists($response, 'getContent') && !$response->headers->has('Content-Length')) {
            $content = $response->getContent();
            if ($content !== false && !is_null($content)) {
                $response->headers->set('Content-Length', (string) strlen($content));
            }
        }

        return $response;
    }
}
