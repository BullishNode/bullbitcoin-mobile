import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds local metadata for materialized Nostr keys: public key, kind, purpose,
/// and the optional user-authored description.
///
/// The table is created with its final version-20 shape, so there is no
/// separate column-add step for `description`.
class Schema19To20 {
  static Future<void> migrate(Migrator m, Schema20 schema20) async {
    await m.createTable(schema20.keychainManifestNostrKeys);
  }
}
