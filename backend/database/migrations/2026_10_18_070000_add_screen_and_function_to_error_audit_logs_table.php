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
        Schema::table('error_audit_logs', function (Blueprint $table) {
            $table->string('screen', 128)->nullable()->after('endpoint');
            $table->string('function_name', 128)->nullable()->after('screen');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('error_audit_logs', function (Blueprint $table) {
            $table->dropColumn(['screen', 'function_name']);
        });
    }
};
