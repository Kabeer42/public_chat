<?php

namespace App\Http\Requests\Call;

use Illuminate\Foundation\Http\FormRequest;

class CallOfferRequest extends FormRequest
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
                        $fail('You cannot initiate a call to yourself.');
                    }
                },
            ],
            'call_type' => ['required', 'string', 'in:voice,video'],
            'sdp' => ['required_without:sdp_offer'],
            'sdp_offer' => ['required_without:sdp'],
            'call_id' => ['nullable', 'string', 'max:255'],
        ];
    }

}
