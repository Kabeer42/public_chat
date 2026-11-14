import 'package:chatapp/core/storage/storage_manager_service.dart';
import 'package:chatapp/features/auth/domain/entities/user_entity.dart';
import 'package:chatapp/features/settings/domain/repositories/settings_repository.dart';
import 'package:chatapp/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:chatapp/features/settings/presentation/bloc/settings_event.dart';
import 'package:flutter_test/flutter_test.dart';

class MockSettingsRepository implements SettingsRepository {
  UserEntity user;
  StorageBreakdown breakdown;
  int clearMediaCount = 0;

  MockSettingsRepository({
    required this.user,
    this.breakdown = const StorageBreakdown(
      imagesBytes: 1048576,
      videosBytes: 2097152,
    ),
  });

  @override
  Future<UserEntity> updateProfile({required String name, required String email}) async {
    user = user.copyWith(name: name, email: email);
    return user;
  }

  @override
  Future<String> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    return 'Password updated successfully.';
  }

  @override
  Future<UserEntity> updatePrivacy({required bool showLastSeen}) async {
    user = user.copyWith(showLastSeen: showLastSeen);
    return user;
  }

  @override
  Future<StorageBreakdown> getStorageBreakdown() async {
    return breakdown;
  }

  @override
  Future<int> clearMediaCache() async {
    clearMediaCount++;
    breakdown = const StorageBreakdown();
    return 3145728; // 3 MB
  }
}

void main() {
  group('SettingsBloc Feature Tests', () {
    late MockSettingsRepository mockRepo;
    late SettingsBloc bloc;

    const initialUser = UserEntity(
      id: 1,
      name: 'Alice Cooper',
      email: 'alice@example.com',
      showLastSeen: true,
    );

    setUp(() {
      mockRepo = MockSettingsRepository(user: initialUser);
      bloc = SettingsBloc(settingsRepository: mockRepo);
    });

    tearDown(() {
      bloc.close();
    });

    test('LoadSettingsEvent sets user and triggers storage breakdown retrieval', () async {
      bloc.add(const LoadSettingsEvent(initialUser));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<dynamic>((s) => s.user?.name == 'Alice Cooper'),
          predicate<dynamic>((s) => s.isStorageLoading == true),
          predicate<dynamic>((s) => s.storageBreakdown.imagesBytes == 1048576 && !s.isStorageLoading),
        ]),
      );
    });

    test('UpdateProfileEvent updates user info and sets successMessage', () async {
      bloc.add(const UpdateProfileEvent(name: 'Alice Wonder', email: 'wonder@example.com'));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<dynamic>((s) => s.isLoading == true),
          predicate<dynamic>((s) =>
              s.user?.name == 'Alice Wonder' &&
              s.user?.email == 'wonder@example.com' &&
              s.successMessage == 'Profile updated successfully.'),
        ]),
      );
    });

    test('UpdatePasswordEvent sets success message upon success', () async {
      bloc.add(const UpdatePasswordEvent(
        currentPassword: 'old_password_123',
        newPassword: 'new_password_456',
        confirmPassword: 'new_password_456',
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<dynamic>((s) => s.isLoading == true),
          predicate<dynamic>((s) =>
              s.successMessage == 'Password updated successfully.' &&
              s.isLoading == false),
        ]),
      );
    });

    test('ToggleLastSeenPrivacyEvent updates showLastSeen in state and repository', () async {
      bloc.add(const LoadSettingsEvent(initialUser));
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.add(const ToggleLastSeenPrivacyEvent(false));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<dynamic>((s) => s.user?.showLastSeen == false),
          predicate<dynamic>((s) =>
              s.user?.showLastSeen == false &&
              s.successMessage == 'Last seen is now hidden.'),
        ]),
      );
    });

    test('ClearMediaCacheEvent calls repo and resets storage breakdown', () async {
      bloc.add(const ClearMediaCacheEvent());

      await expectLater(
        bloc.stream,
        emitsInOrder([
          predicate<dynamic>((s) => s.isStorageLoading == true),
          predicate<dynamic>((s) =>
              s.storageBreakdown.totalBytes == 0 &&
              s.isStorageLoading == false &&
              s.successMessage != null &&
              s.successMessage!.contains('Cleaned cache')),
        ]),
      );
    });
  });
}
