<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ErrorAuditLog extends Model
{
    use HasFactory;

    protected $table = 'error_audit_logs';

    protected $fillable = [
        'reference_code',
        'user_id',
        'error_code',
        'exception_class',
        'message',
        'stack_trace',
        'endpoint',
        'http_method',
        'ip_address',
        'payload',
        'source',
    ];

    protected $casts = [
        'payload' => 'array',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
