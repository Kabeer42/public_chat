<?php

namespace App\Repositories\Eloquent;

use App\Models\User;
use App\Repositories\Contracts\UserRepositoryInterface;
use Illuminate\Database\Eloquent\Collection;

class UserRepository implements UserRepositoryInterface
{
    public function create(array $data): User
    {
        return User::create($data);
    }

    public function findById(int $id): ?User
    {
        return User::find($id);
    }

    public function findByEmail(string $email): ?User
    {
        return User::where('email', $email)->first();
    }

    public function getAllExcept(int $userId): Collection
    {
        return User::where('id', '!=', $userId)
            ->orderBy('name', 'asc')
            ->get();
    }

    public function updateKeys(int $userId, string $identityKey, ?string $signedPrekey = null): bool
    {
        $user = $this->findById($userId);
        if (!$user) {
            return false;
        }

        return $user->update([
            'public_identity_key' => $identityKey,
            'public_signed_prekey' => $signedPrekey,
        ]);
    }

    public function updatePresence(int $userId, bool $isOnline): bool
    {
        $user = $this->findById($userId);
        if (!$user) {
            return false;
        }

        return $user->update([
            'is_online' => $isOnline,
            'last_seen_at' => now(),
        ]);
    }
}
