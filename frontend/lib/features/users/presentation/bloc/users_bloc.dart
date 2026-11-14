import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_users_usecase.dart';
import 'users_event.dart';
import 'users_state.dart';

class UsersBloc extends Bloc<UsersEvent, UsersState> {
  final GetUsersUseCase _getUsersUseCase;

  UsersBloc({
    required GetUsersUseCase getUsersUseCase,
  })  : _getUsersUseCase = getUsersUseCase,
        super(const UsersInitial()) {
    on<FetchUsersRequested>(_onFetchUsersRequested);
    on<RefreshUsersRequested>(_onRefreshUsersRequested);
  }

  Future<void> _onFetchUsersRequested(
    FetchUsersRequested event,
    Emitter<UsersState> emit,
  ) async {
    emit(const UsersLoading());
    try {
      final users = await _getUsersUseCase();
      emit(UsersLoaded(users));
    } catch (e) {
      emit(UsersError(e.toString().replaceAll('ApiException: ', '')));
    }
  }

  Future<void> _onRefreshUsersRequested(
    RefreshUsersRequested event,
    Emitter<UsersState> emit,
  ) async {
    try {
      final users = await _getUsersUseCase();
      emit(UsersLoaded(users));
    } catch (e) {
      emit(UsersError(e.toString().replaceAll('ApiException: ', '')));
    }
  }
}
