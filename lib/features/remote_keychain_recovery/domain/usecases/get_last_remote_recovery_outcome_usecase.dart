import 'package:bb_mobile/features/remote_keychain_recovery/domain/repositories/remote_recovery_outcome_repository.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

/// Read-only view of the last recovery pass for unified wallet-backup settings:
/// page: whether it completed, and when. Returns null when no pass has ever
/// recorded an outcome (fresh install) or the record is unreadable.
class GetLastRemoteRecoveryOutcomeUsecase {
  final RemoteRecoveryOutcomeRepository _repository;

  const GetLastRemoteRecoveryOutcomeUsecase(this._repository);

  Future<RemoteRecoveryOutcome?> execute() => _repository.read();
}
