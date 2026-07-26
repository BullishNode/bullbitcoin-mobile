import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:drift/drift.dart';

/// Adds local metadata for materialized Nostr keys: public key, kind, purpose,
/// and the optional user-authored description.
///
/// The table is created with its final v19 shape, so there is no separate
/// column-add step for `description`. v19 has never shipped — it was introduced
/// on this branch and the table does not exist on main — so amending it in
/// place is the correct move rather than stacking a v20. A dev or QA install
/// that already ran an interim v19 without the column must have its app data
/// wiped.
class Schema18To19 {
  static Future<void> migrate(Migrator m, Schema19 schema19) async {
    await m.createTable(schema19.keychainManifestNostrKeys);
  }
}
