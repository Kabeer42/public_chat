<?php

namespace App\Console\Commands;

use App\Events\MessageDeletedEvent;
use App\Models\Message;
use App\Services\MediaService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class PruneDisappearingMessagesCommand extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'chat:prune-disappearing';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Hard-delete expired disappearing messages and purge their encrypted media files';

    /**
     * Execute the console command.
     */
    public function handle(MediaService $mediaService): int
    {
        $expiredMessages = Message::whereNotNull('expires_at')
            ->where('expires_at', '<=', now())
            ->get();

        $count = $expiredMessages->count();

        if ($count === 0) {
            $this->info('No expired disappearing messages to prune.');
            return Command::SUCCESS;
        }

        $mediaDeletedCount = 0;
        $deletedIds = [];
        $recipientGroups = [];

        foreach ($expiredMessages as $message) {
            $deletedIds[] = $message->id;

            // Group by recipients for websocket broadcasting
            $recipientGroups[$message->receiver_id][] = $message->id;
            $recipientGroups[$message->sender_id][] = $message->id;

            // Delete physical encrypted media file from storage disk if applicable
            if ($message->media_url) {
                $uuid = basename($message->media_url);
                if ($mediaService->deleteEncryptedBlob($uuid)) {
                    $mediaDeletedCount++;
                }
            }
        }

        // Hard-delete records from database
        Message::whereIn('id', $deletedIds)->delete();

        // Broadcast deletion event to connected clients over Reverb
        foreach ($recipientGroups as $userId => $ids) {
            $uniqueIds = array_unique($ids);
            // Broadcast as system prune (peerId 0 indicates system auto-prune)
            MessageDeletedEvent::dispatch((int) $userId, 0, $uniqueIds);
        }

        $logMsg = "Pruned {$count} expired messages and purged {$mediaDeletedCount} encrypted media files.";
        $this->info($logMsg);
        Log::info("[DisappearingMessages] {$logMsg}");

        return Command::SUCCESS;
    }
}
