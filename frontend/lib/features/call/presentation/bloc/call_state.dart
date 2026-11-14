import 'package:equatable/equatable.dart';
import '../../domain/entities/call_entity.dart';

abstract class CallState extends Equatable {
  const CallState();

  @override
  List<Object?> get props => [];
}

class CallInitialState extends CallState {
  const CallInitialState();
}

class CallSessionState extends CallState {
  final CallSessionEntity session;

  const CallSessionState({required this.session});

  @override
  List<Object?> get props => [session];
}
