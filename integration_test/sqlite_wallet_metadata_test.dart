import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/storage/tables/wallet_metadata_table.dart'
    show WalletSource;
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/wallet_metadata_service.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  locator.registerLazySingleton<SqliteDatabase>(() => SqliteDatabase());
  final sqlite = locator<SqliteDatabase>();

  group('WalletMetadata Sqlite Integration Tests', () {
    test('', () async {
      const fingerprint = 'master';
      const scriptType = ScriptType.bip84;

      final metadata = WalletMetadataModel(
        masterFingerprint: fingerprint,
        id: WalletMetadataService.encodeOrigin(
          fingerprint: fingerprint,
          network: Network.bitcoinMainnet,
          scriptType: scriptType,
        ),
        xpubFingerprint: 'abc12345',
        xpub: 'xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKp5i1Lsfk...',
        externalPublicDescriptor: 'wpkh([abcd1234/84h/0h/0h]xpub.../0/*)',
        internalPublicDescriptor: 'wpkh([abcd1234/84h/0h/0h]xpub.../1/*)',
        source: WalletSource.mnemonic,
        latestEncryptedBackup: 1680000000,
        latestPhysicalBackup: 1681000000,
        isEncryptedVaultTested: true,
        isPhysicalBackupTested: true,
        isDefault: true,
        label: 'My Main Wallet',
        syncedAt: DateTime.now(),
      );

      // Store a metadata
      await sqlite.into(sqlite.walletMetadatas).insert(metadata);

      // Fetch one
      final fetchedMetadata =
          await sqlite.managers.walletMetadatas
              .filter((e) => e.id(metadata.id))
              .getSingleOrNull();
      expect(fetchedMetadata, isNotNull);
      expect(fetchedMetadata!.id, metadata.id);

      // Delete the only one
      await sqlite.managers.walletMetadatas
          .filter((f) => f.id(metadata.id))
          .delete();

      // Fetch all
      final fetchedMetadatas = await sqlite.managers.walletMetadatas.get();
      expect(fetchedMetadatas, isEmpty);
    });
  });
}
