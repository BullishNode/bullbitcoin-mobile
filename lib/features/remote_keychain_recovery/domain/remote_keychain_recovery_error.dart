import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:flutter/widgets.dart';

enum RemoteKeychainRecoveryErrorKind {
  defaultWalletUnavailable,
  manifestCheckFailed,
  restoreFailed,
}

/// Sealed error family for remote keychain recovery (P22b, per the AD9c
/// convention). Every variant carries a `toTranslated` user message; the raw
/// [cause] stays for logs only and is never surfaced through presentation.
sealed class RemoteKeychainRecoveryException extends BullException {
  final RemoteKeychainRecoveryErrorKind kind;
  final Object? cause;

  RemoteKeychainRecoveryException._(this.kind, String message, {this.cause})
    : super(message);

  String toTranslated(BuildContext context) {
    // Feature-specific copy per variant (the pr22 placeholder is discharged
    // here); the sealed switch guarantees every variant has a user-facing
    // message and the raw cause stays in logs.
    return switch (this) {
      DefaultWalletUnavailableRecoveryException() =>
        context.loc.remoteKeychainRecoveryDefaultWalletUnavailable,
      ManifestCheckFailedRecoveryException() =>
        context.loc.remoteKeychainRecoveryCheckFailed,
      RestoreFailedRecoveryException() =>
        context.loc.remoteKeychainRecoveryRestoreFailed,
    };
  }
}

final class DefaultWalletUnavailableRecoveryException
    extends RemoteKeychainRecoveryException {
  DefaultWalletUnavailableRecoveryException({Object? cause})
    : super._(
        RemoteKeychainRecoveryErrorKind.defaultWalletUnavailable,
        'default wallet unavailable for remote keychain recovery',
        cause: cause,
      );
}

final class ManifestCheckFailedRecoveryException
    extends RemoteKeychainRecoveryException {
  ManifestCheckFailedRecoveryException({Object? cause})
    : super._(
        RemoteKeychainRecoveryErrorKind.manifestCheckFailed,
        'remote keychain manifest check failed',
        cause: cause,
      );
}

final class RestoreFailedRecoveryException
    extends RemoteKeychainRecoveryException {
  RestoreFailedRecoveryException({Object? cause})
    : super._(
        RemoteKeychainRecoveryErrorKind.restoreFailed,
        'remote keychain manifest restore failed',
        cause: cause,
      );
}
