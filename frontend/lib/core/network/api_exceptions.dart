class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic errors;
  final String? referenceCode;

  ApiException({
    required this.message,
    this.statusCode,
    this.errors,
    this.referenceCode,
  });

  @override
  String toString() {
    final ref = referenceCode != null ? ' [Ref: $referenceCode]' : '';
    return 'ApiException: $message$ref (Status: $statusCode)';
  }
}

class NetworkException extends ApiException {
  NetworkException({
    String message = 'Unable to connect to the backend server. Please verify your connection or tunnel URL.',
    String? referenceCode,
  }) : super(message: message, statusCode: 0, referenceCode: referenceCode);
}

class UnauthorizedException extends ApiException {
  UnauthorizedException({
    String message = 'Session expired. Please log in again.',
    String? referenceCode,
  }) : super(message: message, statusCode: 401, referenceCode: referenceCode);
}

class ValidationException extends ApiException {
  ValidationException({
    required String message,
    dynamic errors,
    String? referenceCode,
  }) : super(
          message: message,
          statusCode: 422,
          errors: errors,
          referenceCode: referenceCode,
        );
}
