<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class MediaService
{
    protected const DISK = 'encrypted_media';

    /**
     * Store an opaque encrypted binary blob on the secure disk.
     */
    public function storeEncryptedBlob(UploadedFile $file): array
    {
        $uuid = Str::uuid()->toString();
        $filename = "{$uuid}.enc";

        Storage::disk(self::DISK)->putFileAs('', $file, $filename);

        return [
            'media_id' => $uuid,
            'url' => "/api/v1/media/{$uuid}",
            'filename' => $filename,
            'size' => $file->getSize(),
        ];
    }

    /**
     * Retrieve the filesystem path of the encrypted binary blob.
     * Returns null if UUID is invalid or file does not exist.
     */
    public function getEncryptedBlobPath(string $uuid): ?string
    {
        // Strict UUID validation to prevent path traversal
        if (!Str::isUuid($uuid)) {
            return null;
        }

        $filename = "{$uuid}.enc";
        if (!Storage::disk(self::DISK)->exists($filename)) {
            return null;
        }

        return Storage::disk(self::DISK)->path($filename);
    }

    /**
     * Delete an encrypted binary blob.
     */
    public function deleteEncryptedBlob(string $uuid): bool
    {
        if (!Str::isUuid($uuid)) {
            return false;
        }

        return Storage::disk(self::DISK)->delete("{$uuid}.enc");
    }
}
