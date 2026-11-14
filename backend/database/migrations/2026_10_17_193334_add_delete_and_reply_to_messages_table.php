<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->unsignedBigInteger('reply_to_id')->nullable()->after('encrypted_media_key');
            $table->text('reply_preview')->nullable()->after('reply_to_id');
            $table->boolean('deleted_by_sender')->default(false)->after('read_at');
            $table->boolean('deleted_by_receiver')->default(false)->after('deleted_by_sender');
            $table->boolean('is_deleted_for_everyone')->default(false)->after('deleted_by_receiver');
        });
    }

    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            $table->dropColumn([
                'reply_to_id',
                'reply_preview',
                'deleted_by_sender',
                'deleted_by_receiver',
                'is_deleted_for_everyone',
            ]);
        });
    }
};
