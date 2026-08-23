/// Base exception type for this wrapper. Callers can catch this instead
/// of guessing at whatever `purchases_flutter` throws underneath.
class RevenueCatWrapperException implements Exception {
  final String message;
  final Object? cause;

  const RevenueCatWrapperException(this.message, [this.cause]);

  @override
  String toString() => 'RevenueCatWrapperException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Thrown when a service method is called before [RevenueCatService.init].
class NotInitializedException extends RevenueCatWrapperException {
  const NotInitializedException() : super('RevenueCatService.init() must be called before use.');
}
