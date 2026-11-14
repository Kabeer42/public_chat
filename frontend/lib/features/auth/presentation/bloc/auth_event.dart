import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthLoginSubmitted extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginSubmitted({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

class AuthRegisterSubmitted extends AuthEvent {
  final String name;
  final String email;
  final String password;
  final String? publicIdentityKey;
  final String? publicSignedPrekey;

  const AuthRegisterSubmitted({
    required this.name,
    required this.email,
    required this.password,
    this.publicIdentityKey,
    this.publicSignedPrekey,
  });

  @override
  List<Object?> get props => [
        name,
        email,
        password,
        publicIdentityKey,
        publicSignedPrekey,
      ];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}
