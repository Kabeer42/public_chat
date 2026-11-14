<?php

namespace App\Http\Requests\Media;

use Illuminate\Foundation\Http\FormRequest;

class UploadEncryptedMediaRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'file' => [
                'required',
                'file',
                'max:51200', // 50MB max size for encrypted media blobs
            ],
        ];
    }

    public function messages(): array
    {
        return [
            'file.required' => 'An encrypted media file must be provided.',
            'file.file' => 'The provided input must be a valid binary file.',
            'file.max' => 'The encrypted media file cannot exceed 50MB.',
        ];
    }
}
