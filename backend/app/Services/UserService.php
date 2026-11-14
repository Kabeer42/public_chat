<?php

namespace App\Services;

use App\Models\User;
use App\Repositories\Contracts\UserRepositoryInterface;
use Illuminate\Database\Eloquent\Collection;

class UserService
{
    public function __construct(
        protected UserRepositoryInterface $userRepository
    ) {}

    public function getAllUsersExcept(int $currentUserId): Collection
    {
        return $this->userRepository->getAllExcept($currentUserId);
    }

    public function publishPublicKey(int $userId, string $identityKey, ?string $signedPrekey = null): bool
    {
        return $this->userRepository->updateKeys($userId, $identityKey, $signedPrekey);
    }

    public function getUserPublicKey(int $userId): ?array
    {
        $user = $this->userRepository->findById($userId);

        if (!$user) {
            return null;
        }

        return [
            'user_id' => $user->id,
            'name' => $user->name,
            'public_identity_key' => $user->public_identity_key,
            'public_signed_prekey' => $user->public_signed_prekey,
        ];
    }
}
