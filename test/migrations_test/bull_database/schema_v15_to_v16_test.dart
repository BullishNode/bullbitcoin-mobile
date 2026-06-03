import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v16.dart' as v16;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v15 to v16 creates keychain manifest entries table', () async {
    final schema = await verifier.schemaAt(15);
    final db = SqliteDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 16);
    await db.close();

    final migratedDb = v16.DatabaseAtV16(schema.newConnection());
    await migratedDb
        .into(migratedDb.keychainManifestEntries)
        .insert(
          v16.KeychainManifestEntriesCompanion.insert(
            entryId: "fedcba98:39'/0'/12'/100'",
            parentFingerprint: 'fedcba98',
            bip85DerivationPath: "39'/0'/12'/100'",
            reservationId: 'btcpay_wallet_seed',
            entryType: 'walletSeed',
            ownerFeature: 'btcpay',
            bip85Application: 39,
            bip85Index: 100,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await migratedDb
        .into(migratedDb.keychainManifestWalletBindings)
        .insert(
          v16.KeychainManifestWalletBindingsCompanion.insert(
            walletId: 'btc-wallet',
            entryId: "fedcba98:39'/0'/12'/100'",
            childSeedFingerprint: '0123abcd',
            network: 'bitcoinMainnet',
            walletPurpose: 'bitcoin',
            scriptType: 'bip84',
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    final rows = await migratedDb
        .select(migratedDb.keychainManifestEntries)
        .get();
    final bindings = await migratedDb
        .select(migratedDb.keychainManifestWalletBindings)
        .get();
    expect(rows.single.entryId, "fedcba98:39'/0'/12'/100'");
    expect(bindings.single.walletId, 'btc-wallet');

    await migratedDb.close();
  });
}
