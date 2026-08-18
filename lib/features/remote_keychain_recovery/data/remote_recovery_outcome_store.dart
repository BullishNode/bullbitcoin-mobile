import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/data/models/remote_recovery_outcome_model.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/repositories/remote_recovery_outcome_repository.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

/// One-record store for the last remote-recovery outcome (see
/// [RemoteRecoveryOutcome] for why it exists and what it may contain).
final class RemoteRecoveryOutcomeStore
    implements RemoteRecoveryOutcomeRepository {
  static const _key = 'remoteKeychainRecoveryLastOutcome';

  final KeyValueStorageDatasource<String> _storage;

  const RemoteRecoveryOutcomeStore(this._storage);

  @override
  Future<void> save(RemoteRecoveryOutcome outcome) => _storage.saveValue(
    key: _key,
    value: RemoteRecoveryOutcomeModel.fromDomain(outcome).encode(),
  );

  @override
  Future<RemoteRecoveryOutcome?> read() async {
    final raw = await _storage.getValue(_key);
    if (raw == null) return null;
    return RemoteRecoveryOutcomeModel.tryDecode(raw)?.toDomain();
  }
}
