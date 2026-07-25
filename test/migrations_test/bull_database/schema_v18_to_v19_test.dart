import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v18 to v19 removes metadata state and adds recovery fence', () async {
    final schema = await verifier.schemaAt(18);
    final database = SqliteDatabase(schema.newConnection());

    await verifier.migrateAndValidate(database, 19);
    await database
        .into(database.walletBackupStates)
        .insert(const WalletBackupStatesCompanion());
    final state = await database
        .select(database.walletBackupStates)
        .getSingle();

    expect(state.recoveryBlocked, isFalse);
    final oldTable = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>('wallet_metadata_backup_states')],
        )
        .get();
    expect(oldTable, isEmpty);

    await database.close();
  });
}
