import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds local metadata for materialized Nostr keys.
class Schema18To19 {
  static Future<void> migrate(Migrator m, Schema19 schema19) async {
    await m.createTable(schema19.keychainManifestNostrKeys);
  }
}
