import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds local metadata for materialized Nostr keys in its final shape,
/// including the optional user-authored description.
class Schema16To17 {
  static Future<void> migrate(Migrator m, Schema17 schema17) async {
    await m.createTable(schema17.keychainManifestNostrKeys);
  }
}
