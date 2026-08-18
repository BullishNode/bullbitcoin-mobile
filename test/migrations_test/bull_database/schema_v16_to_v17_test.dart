import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v16.dart' as v16;
import 'generated/schema_v17.dart' as v17;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v16 to v17 adds Nostr key materializations', () async {
    final schema = await verifier.schemaAt(16);
    final oldDb = v16.DatabaseAtV16(schema.newConnection());
    const preservedEntryId = "89abcdef:39'/0'/12'/7'";
    await oldDb
        .into(oldDb.keychainManifestEntries)
        .insert(
          v16.KeychainManifestEntriesCompanion.insert(
            entryId: preservedEntryId,
            parentFingerprint: '89abcdef',
            bip85DerivationPath: "39'/0'/12'/7'",
            reservationId: 'payment_page_wallet_seed',
            entryType: 'walletSeed',
            ownerFeature: 'payment_page',
            bip85Application: 39,
            bip85Index: 7,
            createdAt: 10,
            updatedAt: 11,
          ),
        );
    await oldDb.close();

    final db = SqliteDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 17);
    await db.close();

    final migratedDb = v17.DatabaseAtV17(schema.newConnection());
    final preserved = await migratedDb
        .select(migratedDb.keychainManifestEntries)
        .getSingle();
    expect(preserved.entryId, preservedEntryId);
    expect(preserved.reservationId, 'payment_page_wallet_seed');
    expect(preserved.updatedAt, 11);

    const entryId = "01234567:128002'/1'/1'";
    await migratedDb
        .into(migratedDb.keychainManifestEntries)
        .insert(
          v17.KeychainManifestEntriesCompanion.insert(
            entryId: entryId,
            parentFingerprint: '01234567',
            bip85DerivationPath: "128002'/1'/1'",
            reservationId: 'nostr_user_key',
            entryType: 'userGenerated',
            ownerFeature: 'nostr',
            bip85Application: 128002,
            bip85Index: 1,
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await migratedDb
        .into(migratedDb.keychainManifestNostrKeys)
        .insert(
          v17.KeychainManifestNostrKeysCompanion.insert(
            entryId: entryId,
            publicKeyHex: 'ab' * 32,
            keyKind: 'userGenerated',
            purpose: 'Personal identity',
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    final stored = await migratedDb
        .select(migratedDb.keychainManifestNostrKeys)
        .getSingle();
    expect(stored.entryId, entryId);
    expect(stored.purpose, 'Personal identity');
    expect(stored.description, isNull);
    expect(
      await migratedDb.select(migratedDb.keychainManifestEntries).get(),
      hasLength(2),
    );
    await migratedDb.close();
  });
}
