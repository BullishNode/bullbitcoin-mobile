import 'package:bb_mobile/core/storage/sqlite_database.steps.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:drift/drift.dart';

/// Migration from version 15 to 16.
///
/// - Creates the single-row Get Paid settings table holding the automated
///   backup preference (toggle + disclosure acknowledgement) introduced in
///   PR23.
/// - Adds the `recovered` column to swaps: marks swaps reconstructed by the
///   restore/rescue flow rather than created in-app. Fields not derivable from
///   the Boltz restore response + on-chain data are untrustworthy for these and
///   hidden in the UI.
/// - Adds the exchange testnet basic-auth username/password columns to
///   settings: in-app HTTP basic auth creds gating the testnet exchange web
///   frontend.
/// - Additive: creates the `frozen_utxos` table backing user freeze
///   persistence (issue #760). Idempotent: if the table already exists the
///   create is swallowed.
class Schema15To16 {
  static Future<void> migrate(Migrator m, Schema16 schema16) async {
    await m.createTable(schema16.getPaidSettings);

    try {
      await m.addColumn(schema16.swaps, schema16.swaps.recovered);
    } catch (e) {
      if (!e.toString().contains('duplicate column')) rethrow;
    }

    try {
      await m.addColumn(
        schema16.settings,
        schema16.settings.exchangeTestnetBasicAuthUsername,
      );
    } catch (e) {
      if (!e.toString().contains('duplicate column')) rethrow;
    }
    try {
      await m.addColumn(
        schema16.settings,
        schema16.settings.exchangeTestnetBasicAuthPassword,
      );
    } catch (e) {
      if (!e.toString().contains('duplicate column')) rethrow;
    }

    try {
      await m.createTable(schema16.frozenUtxos);
    } catch (e) {
      // Idempotency guard: only swallow "table already exists" (a re-run over a
      // partially-applied migration) — log it so a driver wording change
      // surfaces instead of silently becoming a hard failure.
      if (!e.toString().contains('already exists')) rethrow;
      log.warning(
        'Schema15To16: frozen_utxos already exists — skipping create',
        error: e,
      );
    }
  }
}
