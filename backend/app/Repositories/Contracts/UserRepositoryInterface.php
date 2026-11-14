<?php

namespace App\Repositories\Contracts;

use App\Models\User;
use Illuminate\Database\Eloquent\Collection;

interface UserRepositoryInterface
{
    public function create(array $data): User;

    public function findById(int $id): ?User;

    public function findByEmail(string $email): ?User;

    public function getAllExcept(int $userId): Collection;

    public function updateKeys(int $userId, string $identityKey, ?string $signedPrekey = null): bool;

    public function updatePresence(int $userId, bool $isOnline): bool;
}
