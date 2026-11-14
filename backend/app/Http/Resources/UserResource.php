<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $isSelf = $request->user() && $request->user()->id === $this->id;
        $canShowLastSeen = $isSelf || (bool) $this->show_last_seen;

        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'public_identity_key' => $this->public_identity_key,
            'public_signed_prekey' => $this->public_signed_prekey,
            'has_key_backup' => $isSelf ? !empty($this->encrypted_key_backup) : null,
            'is_online' => (bool) $this->is_online,
            'show_last_seen' => (bool) $this->show_last_seen,
            'last_seen_at' => ($canShowLastSeen && $this->last_seen_at) ? $this->last_seen_at->toIso8601String() : null,
            'created_at' => $this->created_at ? $this->created_at->toIso8601String() : null,
        ];
    }
}
