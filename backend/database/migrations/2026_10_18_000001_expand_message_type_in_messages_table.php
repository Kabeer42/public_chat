<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        if (DB::getDriverName() === 'mysql') {
            DB::statement("ALTER TABLE messages MODIFY COLUMN message_type ENUM('text', 'image', 'video', 'audio', 'document', 'contact') NOT NULL DEFAULT 'text'");
        }

        Schema::table('messages', function (Blueprint $table) {
            if (! Schema::hasColumn('messages', 'file_name')) {
                $table->string('file_name')->nullable()->after('encrypted_media_key');
            }
            if (! Schema::hasColumn('messages', 'file_size')) {
                $table->unsignedBigInteger('file_size')->nullable()->after('file_name');
            }
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('messages', function (Blueprint $table) {
            if (Schema::hasColumn('messages', 'file_size')) {
                $table->dropColumn('file_size');
            }
            if (Schema::hasColumn('messages', 'file_name')) {
                $table->dropColumn('file_name');
            }
        });

        if (DB::getDriverName() === 'mysql') {
            DB::statement("ALTER TABLE messages MODIFY COLUMN message_type ENUM('text', 'image', 'video') NOT NULL DEFAULT 'text'");
        }
    }
};
