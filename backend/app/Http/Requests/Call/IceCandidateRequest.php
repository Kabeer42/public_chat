<?php

namespace App\Http\Requests\Call;

use Illuminate\Foundation\Http\FormRequest;

class IceCandidateRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        if (! $this->has('receiver_id') && $this->has('target_user_id')) {
            $this->merge(['receiver_id' => $this->input('target_user_id')]);
        }
    }

    public function rules(): array
    {
        return [
            'call_id' => ['nullable', 'string', 'max:255'],
            'receiver_id' => [
                'required',
                'integer',
                'exists:users,id',
                function ($attribute, $value, $fail) {
                    if ($this->user() && (int) $this->user()->id === (int) $value) {
                        $fail('You cannot send ICE candidates to yourself.');
                    }
                },
            ],
            'candidate' => ['required'],
        ];
    }

}
