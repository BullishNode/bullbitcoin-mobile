import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

abstract interface class RemoteRecoveryOutcomeRepository {
  Future<void> save(RemoteRecoveryOutcome outcome);

  Future<RemoteRecoveryOutcome?> read();
}
