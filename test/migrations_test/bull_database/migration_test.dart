// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v12.dart' as v12;
import 'generated/schema_v13.dart' as v13;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = SqliteDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v1 to v2 does not corrupt data', () async {
    // Add data to insert into the old database, and the expected rows after the
    // migration.
    // TODO: Fill these lists
    final oldTransactionsData = <v1.TransactionsData>[];
    final expectedNewTransactionsData = <v2.TransactionsData>[];

    final oldWalletMetadatasData = <v1.WalletMetadatasData>[];
    final expectedNewWalletMetadatasData = <v2.WalletMetadatasData>[];

    final oldLabelsData = <v1.LabelsData>[];
    final expectedNewLabelsData = <v2.LabelsData>[];

    final oldSettingsData = <v1.SettingsData>[];
    final expectedNewSettingsData = <v2.SettingsData>[];

    final oldPayjoinSendersData = <v1.PayjoinSendersData>[];
    final expectedNewPayjoinSendersData = <v2.PayjoinSendersData>[];

    final oldPayjoinReceiversData = <v1.PayjoinReceiversData>[];
    final expectedNewPayjoinReceiversData = <v2.PayjoinReceiversData>[];

    final oldElectrumServersData = <v1.ElectrumServersData>[];
    final expectedNewElectrumServersData = <v2.ElectrumServersData>[];

    final oldSwapsData = <v1.SwapsData>[];
    final expectedNewSwapsData = <v2.SwapsData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: SqliteDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.transactions, oldTransactionsData);
        batch.insertAll(oldDb.walletMetadatas, oldWalletMetadatasData);
        batch.insertAll(oldDb.labels, oldLabelsData);
        batch.insertAll(oldDb.settings, oldSettingsData);
        batch.insertAll(oldDb.payjoinSenders, oldPayjoinSendersData);
        batch.insertAll(oldDb.payjoinReceivers, oldPayjoinReceiversData);
        batch.insertAll(oldDb.electrumServers, oldElectrumServersData);
        batch.insertAll(oldDb.swaps, oldSwapsData);
      },
      validateItems: (newDb) async {
        expect(
          expectedNewTransactionsData,
          await newDb.select(newDb.transactions).get(),
        );
        expect(
          expectedNewWalletMetadatasData,
          await newDb.select(newDb.walletMetadatas).get(),
        );
        expect(expectedNewLabelsData, await newDb.select(newDb.labels).get());
        expect(
          expectedNewSettingsData,
          await newDb.select(newDb.settings).get(),
        );
        expect(
          expectedNewPayjoinSendersData,
          await newDb.select(newDb.payjoinSenders).get(),
        );
        expect(
          expectedNewPayjoinReceiversData,
          await newDb.select(newDb.payjoinReceivers).get(),
        );
        expect(
          expectedNewElectrumServersData,
          await newDb.select(newDb.electrumServers).get(),
        );
        expect(expectedNewSwapsData, await newDb.select(newDb.swaps).get());
      },
    );
  });

  test(
    'migration from v12 to v13 preserves BIP85 rows as manual rows',
    () async {
      final oldBip85Data = <v12.Bip85DerivationsData>[
        const v12.Bip85DerivationsData(
          path: "39'/0'/12'/75'",
          xprvFingerprint: 'root-a',
          application: 'bip39',
          status: 'active',
          alias: 'Lightning Address',
        ),
        const v12.Bip85DerivationsData(
          path: "39'/0'/12'/8'",
          xprvFingerprint: 'root-a',
          application: 'bip39',
          status: 'active',
          alias: 'Personal',
        ),
      ];

      await verifier.testWithDataIntegrity(
        oldVersion: 12,
        newVersion: 13,
        createOld: v12.DatabaseAtV12.new,
        createNew: v13.DatabaseAtV13.new,
        openTestedDatabase: SqliteDatabase.new,
        createItems: (batch, oldDb) {
          batch.insertAll(oldDb.bip85Derivations, oldBip85Data);
        },
        validateItems: (newDb) async {
          final rows = await (newDb.select(
            newDb.bip85Derivations,
          )..orderBy([(t) => OrderingTerm.asc(t.path)])).get();

          final usageByAlias = {for (final row in rows) row.alias: row.usage};
          expect(usageByAlias['Lightning Address'], 'manual');
          expect(usageByAlias['Personal'], 'manual');
          expect(rows.map((row) => row.xprvFingerprint).toSet(), {'root-a'});

          await newDb.customStatement(
            '''
INSERT INTO wallet_manifest_origins (
  wallet_id,
  root_fingerprint,
  bip85_derivation_path,
  network,
  created_at,
  updated_at
) VALUES (?, ?, ?, ?, ?, ?);
''',
            [
              'wallet-lbtc',
              'abcd1234',
              "m/83696968'/39'/0'/12'/77'",
              'liquid',
              100,
              100,
            ],
          );
          final originRows = await newDb
              .customSelect('SELECT wallet_id FROM wallet_manifest_origins')
              .get();
          expect(originRows.single.data['wallet_id'], 'wallet-lbtc');
        },
      );
    },
  );
}
