enum RemoteKeychainRecoveryErrorKind {
  defaultWalletUnavailable,
  manifestCheckFailed,
  restoreFailed,
}

final class RemoteKeychainRecoveryException implements Exception {
  final RemoteKeychainRecoveryErrorKind kind;
  final Object? cause;

  const RemoteKeychainRecoveryException(this.kind, {this.cause});

  @override
  String toString() => 'RemoteKeychainRecoveryException: ${kind.name}';
}
