import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v19 to v20 adds Nostr key materializations', () async {
    final schema = await verifier.schemaAt(19);
    final database = SqliteDatabase(schema.newConnection());

    await verifier.migrateAndValidate(database, 20);
    const entryId = "01234567:128002'/1'/1'";
    await database
        .into(database.keychainManifestEntries)
        .insert(
          KeychainManifestEntriesCompanion.insert(
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
    await database
        .into(database.keychainManifestNostrKeys)
        .insert(
          KeychainManifestNostrKeysCompanion.insert(
            entryId: entryId,
            publicKeyHex: 'ab' * 32,
            keyKind: 'userGenerated',
            purpose: 'Personal identity',
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    final stored = await database
        .select(database.keychainManifestNostrKeys)
        .getSingle();
    expect(stored.entryId, entryId);
    expect(stored.purpose, 'Personal identity');

    await database.close();
  });
}
