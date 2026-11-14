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
        Schema::create('error_audit_logs', function (Blueprint $table) {
            $table->id();
            $table->string('reference_code', 32)->unique()->index();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('error_code', 32)->nullable()->index();
            $table->string('exception_class')->nullable();
            $table->text('message');
            $table->longText('stack_trace')->nullable();
            $table->string('endpoint', 512)->nullable();
            $table->string('http_method', 10)->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->json('payload')->nullable();
            $table->string('source', 32)->default('backend');
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('error_audit_logs');
    }
};
