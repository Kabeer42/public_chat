<?php

namespace App\Http\Controllers\Api\v1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Media\UploadEncryptedMediaRequest;
use App\Services\MediaService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class MediaController extends Controller
{
    public function __construct(
        protected MediaService $mediaService
    ) {}

    /**
     * Upload an opaque encrypted binary blob (image or video).
     */
    public function upload(UploadEncryptedMediaRequest $request): JsonResponse
    {
        $result = $this->mediaService->storeEncryptedBlob($request->file('file'));

        return response()->json([
            'message' => 'Encrypted media uploaded successfully',
            'media_id' => $result['media_id'],
            'url' => $result['url'],
            'size' => $result['size'],
        ], 201);
    }

    /**
     * Download the raw encrypted binary blob stream.
     */
    public function download(Request $request, string $uuid): BinaryFileResponse|JsonResponse
    {
        $path = $this->mediaService->getEncryptedBlobPath($uuid);

        if (!$path) {
            return response()->json([
                'message' => 'Encrypted media not found or invalid identifier.',
            ], 404);
        }

        return response()->file($path, [
            'Content-Type' => 'application/octet-stream',
            'Content-Disposition' => "attachment; filename=\"{$uuid}.enc\"",
            'Cache-Control' => 'private, no-transform, no-store',
        ]);
    }
}
