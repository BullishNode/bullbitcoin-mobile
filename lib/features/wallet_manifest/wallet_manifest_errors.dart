import 'package:bb_mobile/core/errors/bull_exception.dart';

sealed class WalletManifestException extends BullException {
  WalletManifestException(super.message);
}

class WalletManifestInvalidOriginException extends WalletManifestException {
  WalletManifestInvalidOriginException(super.message);
}

class WalletManifestOriginPersistenceException extends WalletManifestException {
  final Object cause;

  WalletManifestOriginPersistenceException(this.cause)
    : super('Failed to persist wallet manifest origin');
}

class WalletManifestOriginReadException extends WalletManifestException {
  final Object cause;

  WalletManifestOriginReadException(this.cause)
    : super('Failed to read wallet manifest origins');
}

class WalletManifestSnapshotBuildException extends WalletManifestException {
  final Object cause;

  WalletManifestSnapshotBuildException(this.cause)
    : super('Failed to build wallet manifest snapshot');
}

class WalletManifestSnapshotPublishException extends WalletManifestException {
  final Object cause;

  WalletManifestSnapshotPublishException(this.cause)
    : super('Failed to publish wallet manifest snapshot');
}

class WalletManifestSnapshotFetchException extends WalletManifestException {
  final Object cause;

  WalletManifestSnapshotFetchException(this.cause)
    : super('Failed to fetch wallet manifest snapshot');
}

class WalletManifestKeyDerivationException extends WalletManifestException {
  final Object cause;

  WalletManifestKeyDerivationException(this.cause)
    : super('Failed to derive wallet manifest key');
}

class WalletManifestSnapshotRestoreException extends WalletManifestException {
  final Object cause;

  WalletManifestSnapshotRestoreException(this.cause)
    : super('Failed to restore wallet manifest snapshot');
}

class WalletManifestManualBip85LabelRequiredException
    extends WalletManifestException {
  WalletManifestManualBip85LabelRequiredException()
    : super('A label is required for each manual BIP85 wallet');
}

class WalletManifestManualBip85ReservedLabelException
    extends WalletManifestException {
  WalletManifestManualBip85ReservedLabelException()
    : super('This wallet label is reserved');
}

class WalletManifestManualBip85InvalidIndexException
    extends WalletManifestException {
  final int index;

  WalletManifestManualBip85InvalidIndexException(this.index)
    : super('Invalid BIP85 wallet index: $index');
}

class WalletManifestManualBip85IndexUnavailableException
    extends WalletManifestException {
  final int index;

  WalletManifestManualBip85IndexUnavailableException(this.index)
    : super('A wallet with BIP85 index $index already exists or is reserved');
}

class WalletManifestManualBip85WalletCreationException
    extends WalletManifestException {
  WalletManifestManualBip85WalletCreationException(super.message);
}
