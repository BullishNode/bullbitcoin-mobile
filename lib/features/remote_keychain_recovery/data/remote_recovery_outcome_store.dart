import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

/// One-record store for the last remote-recovery outcome (see
/// [RemoteRecoveryOutcome] for why it exists and what it may contain).
final class RemoteRecoveryOutcomeStore {
  static const _key = 'remoteKeychainRecoveryLastOutcome';

  final KeyValueStorageDatasource<String> _storage;

  const RemoteRecoveryOutcomeStore(this._storage);

  Future<void> save(RemoteRecoveryOutcome outcome) =>
      _storage.saveValue(key: _key, value: outcome.toJsonString());

  Future<RemoteRecoveryOutcome?> read() async {
    final raw = await _storage.getValue(_key);
    if (raw == null) return null;
    return RemoteRecoveryOutcome.tryParse(raw);
  }
}
