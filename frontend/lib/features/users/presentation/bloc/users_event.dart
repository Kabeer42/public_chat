import 'package:equatable/equatable.dart';

abstract class UsersEvent extends Equatable {
  const UsersEvent();

  @override
  List<Object?> get props => [];
}

class FetchUsersRequested extends UsersEvent {
  const FetchUsersRequested();
}

class RefreshUsersRequested extends UsersEvent {
  const RefreshUsersRequested();
}
