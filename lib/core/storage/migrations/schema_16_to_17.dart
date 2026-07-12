import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:drift/drift.dart';

/// Migration from version 16 to 17.
///
/// - Additive: creates the `payment_recoveries` table backing merchant
///   detection + recovery of stuck POS/Payment-Page Bitcoin chain swaps (PR29).
///   One row per invoice; durable so first-write-wins refund-address reuse and
///   idempotent retry survive an app restart. Idempotent: if the table already
///   exists (a re-run over a partially-applied migration) the create is
///   swallowed and logged.
class Schema16To17 {
  static Future<void> migrate(Migrator m, Schema17 schema17) async {
    try {
      await m.createTable(schema17.paymentRecoveries);
    } catch (e) {
      if (!e.toString().contains('already exists')) rethrow;
      log.warning(
        'Schema16To17: payment_recoveries already exists — skipping create',
        error: e,
      );
    }
  }
}
