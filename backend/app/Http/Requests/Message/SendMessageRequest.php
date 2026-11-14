<?php

namespace App\Http\Requests\Message;

use Illuminate\Foundation\Http\FormRequest;

class SendMessageRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'receiver_id' => [
                'required',
                'integer',
                'exists:users,id',
                function ($attribute, $value, $fail) {
                    if ($this->user() && (int) $this->user()->id === (int) $value) {
                        $fail('You cannot send an encrypted message to yourself.');
                    }
                },
            ],
            'message_type' => ['required', 'string', 'in:text,image,video,audio,document,contact'],
            'ciphertext' => ['required', 'string'],
            'iv' => ['required', 'string'],
            'mac' => ['required', 'string'],
            'media_url' => ['nullable', 'string', 'max:2048'],
            'encrypted_media_key' => ['nullable', 'string'],
            'file_name' => ['nullable', 'string', 'max:255'],
            'file_size' => ['nullable', 'integer'],
            'reply_to_id' => ['nullable', 'integer', 'exists:messages,id'],
            'reply_preview' => ['nullable', 'string', 'max:500'],
        ];
    }

}
