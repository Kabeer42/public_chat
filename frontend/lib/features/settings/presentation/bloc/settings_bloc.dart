import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/storage/storage_manager_service.dart';
import '../../domain/repositories/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _settingsRepository;

  SettingsBloc({
    required SettingsRepository settingsRepository,
  })  : _settingsRepository = settingsRepository,
        super(const SettingsState()) {
    on<LoadSettingsEvent>(_onLoadSettings);
    on<UpdateProfileEvent>(_onUpdateProfile);
    on<UpdatePasswordEvent>(_onUpdatePassword);
    on<ToggleLastSeenPrivacyEvent>(_onToggleLastSeenPrivacy);
    on<LoadStorageBreakdownEvent>(_onLoadStorageBreakdown);
    on<ClearMediaCacheEvent>(_onClearMediaCache);
  }

  void _onLoadSettings(
    LoadSettingsEvent event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(user: event.user, clearMessages: true));
    add(const LoadStorageBreakdownEvent());
  }

  Future<void> _onUpdateProfile(
    UpdateProfileEvent event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearMessages: true));
    try {
      final updatedUser = await _settingsRepository.updateProfile(
        name: event.name,
        email: event.email,
      );
      emit(state.copyWith(
        isLoading: false,
        user: updatedUser,
        successMessage: 'Profile updated successfully.',
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: e.message,
        referenceCode: e.referenceCode,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update profile: $e',
      ));
    }
  }

  Future<void> _onUpdatePassword(
    UpdatePasswordEvent event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearMessages: true));
    try {
      final message = await _settingsRepository.updatePassword(
        currentPassword: event.currentPassword,
        newPassword: event.newPassword,
        confirmPassword: event.confirmPassword,
      );
      emit(state.copyWith(
        isLoading: false,
        successMessage: message,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: e.message,
        referenceCode: e.referenceCode,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update password: $e',
      ));
    }
  }

  Future<void> _onToggleLastSeenPrivacy(
    ToggleLastSeenPrivacyEvent event,
    Emitter<SettingsState> emit,
  ) async {
    final previousUser = state.user;
    if (previousUser != null) {
      emit(state.copyWith(
        user: previousUser.copyWith(showLastSeen: event.showLastSeen),
        clearMessages: true,
      ));
    }

    try {
      final updatedUser = await _settingsRepository.updatePrivacy(
        showLastSeen: event.showLastSeen,
      );
      emit(state.copyWith(
        user: updatedUser,
        successMessage: event.showLastSeen
            ? 'Last seen is now visible.'
            : 'Last seen is now hidden.',
      ));
    } on ApiException catch (e) {
      if (previousUser != null) {
        emit(state.copyWith(
          user: previousUser,
          errorMessage: e.message,
          referenceCode: e.referenceCode,
        ));
      }
    } catch (e) {
      if (previousUser != null) {
        emit(state.copyWith(
          user: previousUser,
          errorMessage: 'Failed to update privacy setting.',
        ));
      }
    }
  }

  Future<void> _onLoadStorageBreakdown(
    LoadStorageBreakdownEvent event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isStorageLoading: true));
    try {
      final breakdown = await _settingsRepository.getStorageBreakdown();
      emit(state.copyWith(
        isStorageLoading: false,
        storageBreakdown: breakdown,
      ));
    } catch (_) {
      emit(state.copyWith(isStorageLoading: false));
    }
  }

  Future<void> _onClearMediaCache(
    ClearMediaCacheEvent event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isStorageLoading: true, clearMessages: true));
    try {
      final freedBytes = await _settingsRepository.clearMediaCache();
      final freshBreakdown = await _settingsRepository.getStorageBreakdown();
      emit(state.copyWith(
        isStorageLoading: false,
        storageBreakdown: freshBreakdown,
        successMessage: 'Cleaned cache: freed ${StorageBreakdown.formatBytes(freedBytes)}.',
      ));
    } catch (e) {
      emit(state.copyWith(
        isStorageLoading: false,
        errorMessage: 'Failed to clear media cache: $e',
      ));
    }
  }
}
