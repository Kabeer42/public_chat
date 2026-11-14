<?php

namespace App\Http\Requests\Call;

use Illuminate\Foundation\Http\FormRequest;

class CallAnswerRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        if (! $this->has('receiver_id') && $this->has('caller_id')) {
            $this->merge(['receiver_id' => $this->input('caller_id')]);
        }
        if (! $this->has('sdp') && $this->has('sdp_answer')) {
            $this->merge(['sdp' => $this->input('sdp_answer')]);
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
                        $fail('You cannot answer a call to yourself.');
                    }
                },
            ],
            'sdp' => ['required_without:sdp_answer'],
            'sdp_answer' => ['required_without:sdp'],
        ];
    }

}
