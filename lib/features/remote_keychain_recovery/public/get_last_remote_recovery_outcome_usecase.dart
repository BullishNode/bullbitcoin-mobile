import 'package:bb_mobile/features/remote_keychain_recovery/data/remote_recovery_outcome_store.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

export 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

/// Read-only view of the last recovery pass for unified wallet-backup settings:
/// page: whether it completed, and when. Returns null when no pass has ever
/// recorded an outcome (fresh install) or the record is unreadable.
class GetLastRemoteRecoveryOutcomeUsecase {
  final RemoteRecoveryOutcomeStore _store;

  const GetLastRemoteRecoveryOutcomeUsecase(this._store);

  Future<RemoteRecoveryOutcome?> execute() => _store.read();
}
