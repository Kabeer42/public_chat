<?php

namespace App\Http\Requests\Key;

use Illuminate\Foundation\Http\FormRequest;

class PublishKeyRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'public_identity_key' => ['required', 'string'],
            'public_signed_prekey' => ['nullable', 'string'],
        ];
    }
}
