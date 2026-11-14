<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Message extends Model
{
    use HasFactory;

    protected $fillable = [
        'sender_id',
        'receiver_id',
        'message_type',
        'ciphertext',
        'iv',
        'mac',
        'media_url',
        'encrypted_media_key',
        'file_name',
        'file_size',
        'reply_to_id',
        'reply_preview',
        'deleted_by_sender',
        'deleted_by_receiver',
        'is_deleted_for_everyone',
        'is_delivered',
        'delivered_at',
        'is_read',
        'read_at',
        'expires_at',
    ];

    protected $casts = [
        'is_delivered' => 'boolean',
        'delivered_at' => 'datetime',
        'is_read' => 'boolean',
        'deleted_by_sender' => 'boolean',
        'deleted_by_receiver' => 'boolean',
        'is_deleted_for_everyone' => 'boolean',
        'read_at' => 'datetime',
        'expires_at' => 'datetime',
    ];

    /**
     * The user who sent this encrypted message.
     */
    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    /**
     * The intended recipient of this encrypted message.
     */
    public function receiver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'receiver_id');
    }

    /**
     * The optional parent message being replied to.
     */
    public function replyTo(): BelongsTo
    {
        return $this->belongsTo(Message::class, 'reply_to_id');
    }
}
