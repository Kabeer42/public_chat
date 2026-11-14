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
        Schema::table('users', function (Blueprint $table) {
            $table->text('public_identity_key')->nullable()->after('password');
            $table->text('public_signed_prekey')->nullable()->after('public_identity_key');
            $table->boolean('is_online')->default(false)->after('public_signed_prekey');
            $table->timestamp('last_seen_at')->nullable()->after('is_online');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'public_identity_key',
                'public_signed_prekey',
                'is_online',
                'last_seen_at',
            ]);
        });
    }
};
