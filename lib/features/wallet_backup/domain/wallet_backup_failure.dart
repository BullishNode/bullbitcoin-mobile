import 'package:bb_mobile/core/failures/failure.dart';

sealed class WalletBackupFailure extends Failure {
  const WalletBackupFailure([super.logMessage]);
}

final class WalletBackupInvalidEnvelopeFailure extends WalletBackupFailure {
  const WalletBackupInvalidEnvelopeFailure([super.logMessage]);
}

final class WalletBackupUnsupportedEnvelopeVersionFailure
    extends WalletBackupFailure {
  final int version;

  const WalletBackupUnsupportedEnvelopeVersionFailure(this.version);
}

final class WalletBackupUnsupportedSectionFailure extends WalletBackupFailure {
  final String sectionId;
  final int? version;

  const WalletBackupUnsupportedSectionFailure({
    required this.sectionId,
    this.version,
  });
}

final class WalletBackupParentFingerprintMismatchFailure
    extends WalletBackupFailure {
  const WalletBackupParentFingerprintMismatchFailure();
}

final class WalletBackupTooLargeFailure extends WalletBackupFailure {
  const WalletBackupTooLargeFailure();
}

final class WalletBackupEncryptionFailure extends WalletBackupFailure {
  const WalletBackupEncryptionFailure([super.logMessage]);
}

final class WalletBackupKeyDerivationFailure extends WalletBackupFailure {
  const WalletBackupKeyDerivationFailure([super.logMessage]);
}

final class WalletBackupManifestFailure extends WalletBackupFailure {
  const WalletBackupManifestFailure([super.logMessage]);
}

final class WalletBackupUnexpectedFailure extends WalletBackupFailure {
  const WalletBackupUnexpectedFailure([super.logMessage]);
}
