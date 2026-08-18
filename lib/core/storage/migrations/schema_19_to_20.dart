import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds local metadata for materialized Nostr keys.
class Schema19To20 {
  static Future<void> migrate(Migrator m, Schema20 schema20) async {
    await m.createTable(schema20.keychainManifestNostrKeys);
  }
}
