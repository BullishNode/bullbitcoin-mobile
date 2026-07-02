import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v15.dart' as v15;
import 'generated/schema_v16.dart' as v16;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v15 to v16 preserves backup state and adds recovery fence', () async {
    final schema = await verifier.schemaAt(15);
    final oldDb = v15.DatabaseAtV15(schema.newConnection());
    await oldDb
        .into(oldDb.walletBackupStates)
        .insert(
          v15.WalletBackupStatesCompanion.insert(
            enabled: const Value(1),
            dirty: const Value(1),
            dirtyRevision: const Value(7),
            remoteGeneration: const Value(3),
          ),
        );
    await oldDb.close();

    final db = SqliteDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 16);
    await db.close();

    final migratedDb = v16.DatabaseAtV16(schema.newConnection());
    final state = await migratedDb
        .select(migratedDb.walletBackupStates)
        .getSingle();
    expect(state.enabled, 1);
    expect(state.dirty, 1);
    expect(state.dirtyRevision, 7);
    expect(state.remoteGeneration, 3);
    expect(state.recoveryBlocked, 0);
    await migratedDb.close();
  });
}
