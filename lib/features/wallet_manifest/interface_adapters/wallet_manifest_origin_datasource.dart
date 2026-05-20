import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_origin_store.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';

class WalletManifestOriginDatasource implements WalletManifestOriginStore {
  final SqliteDatabase _sqlite;

  WalletManifestOriginDatasource({required SqliteDatabase sqlite})
    : _sqlite = sqlite;

  @override
  Future<void> upsert(WalletManifestOrigin origin) async {
    await _sqlite.customStatement(
      '''
INSERT INTO wallet_manifest_origins (
  wallet_id,
  root_fingerprint,
  bip85_derivation_path,
  network,
  created_at,
  updated_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(root_fingerprint, bip85_derivation_path, network) DO UPDATE SET
  wallet_id = excluded.wallet_id,
  updated_at = excluded.updated_at;
''',
      [
        origin.walletId,
        origin.rootFingerprint,
        origin.bip85DerivationPath.value,
        origin.network.value,
        origin.createdAt,
        origin.updatedAt,
      ],
    );
  }

  @override
  Future<List<WalletManifestOrigin>> fetchAll() async {
    final rows = await _sqlite.customSelect('''
SELECT
  wallet_id,
  root_fingerprint,
  bip85_derivation_path,
  network,
  created_at,
  updated_at
FROM wallet_manifest_origins
ORDER BY root_fingerprint, bip85_derivation_path, network;
''').get();
    return rows.map((row) => _rowToOrigin(row.data)).toList();
  }

  @override
  Future<void> deleteByWalletId(String walletId) async {
    await _sqlite.customStatement(
      '''
DELETE FROM wallet_manifest_origins
WHERE wallet_id = ?;
''',
      [walletId],
    );
  }

  WalletManifestOrigin _rowToOrigin(Map<String, Object?> row) {
    final path = Bip85DerivationPath.tryParse(
      row['bip85_derivation_path'] as String?,
    );
    final network = WalletManifestNetwork.tryParse(row['network'] as String?);
    if (path == null || network == null) {
      throw StateError('Invalid wallet manifest origin row');
    }
    return WalletManifestOrigin(
      walletId: row['wallet_id'] as String,
      rootFingerprint: row['root_fingerprint'] as String,
      bip85DerivationPath: path,
      network: network,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}
