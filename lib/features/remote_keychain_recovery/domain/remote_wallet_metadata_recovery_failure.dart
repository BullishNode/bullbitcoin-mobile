import 'package:bb_mobile/core/failures/failure.dart';

sealed class RemoteWalletMetadataRecoveryFailure extends Failure {
  const RemoteWalletMetadataRecoveryFailure([super.logMessage]);
}

final class RemoteWalletMetadataRecoveryUnavailableFailure
    extends RemoteWalletMetadataRecoveryFailure {
  const RemoteWalletMetadataRecoveryUnavailableFailure()
    : super('Remote wallet metadata recovery failed');
}
