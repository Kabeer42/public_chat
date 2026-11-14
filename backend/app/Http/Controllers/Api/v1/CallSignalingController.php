<?php

namespace App\Http\Controllers\Api\v1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Call\CallAnswerRequest;
use App\Http\Requests\Call\CallEndRequest;
use App\Http\Requests\Call\CallOfferRequest;
use App\Http\Requests\Call\IceCandidateRequest;
use App\Services\CallSignalingService;
use Illuminate\Http\JsonResponse;

class CallSignalingController extends Controller
{
    public function __construct(
        protected CallSignalingService $signalingService
    ) {}

    /**
     * Send WebRTC SDP offer.
     */
    public function offer(CallOfferRequest $request): JsonResponse
    {
        $result = $this->signalingService->sendOffer(
            $request->user(),
            $request->validated()
        );

        return response()->json($result);
    }

    /**
     * Send WebRTC SDP answer.
     */
    public function answer(CallAnswerRequest $request): JsonResponse
    {
        $result = $this->signalingService->sendAnswer(
            $request->user(),
            $request->validated()
        );

        return response()->json($result);
    }

    /**
     * Relay WebRTC ICE candidate.
     */
    public function iceCandidate(IceCandidateRequest $request): JsonResponse
    {
        $result = $this->signalingService->relayIceCandidate(
            $request->user(),
            $request->validated()
        );

        return response()->json($result);
    }

    /**
     * Hang up, reject, or cancel call.
     */
    public function end(CallEndRequest $request): JsonResponse
    {
        $result = $this->signalingService->endCall(
            $request->user(),
            $request->validated()
        );

        return response()->json($result);
    }

    /**
     * Retrieve active call metadata and SDP offer.
     */
    public function show(string $callId): JsonResponse
    {
        $meta = $this->signalingService->getCallMeta($callId);
        if (!$meta) {
            return response()->json(['message' => 'Call not found or ended.'], 404);
        }

        return response()->json($meta);
    }
}
