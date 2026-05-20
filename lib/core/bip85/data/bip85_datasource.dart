import 'package:bb_mobile/core/bip85/data/bip85_derivation_model.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/storage/tables/bip85_derivations_table.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:convert/convert.dart';
import 'package:drift/drift.dart';

class Bip85Datasource {
  final SqliteDatabase _sqlite;

  Bip85Datasource({required SqliteDatabase sqlite}) : _sqlite = sqlite;

  Future<({String derivation, String hex})> deriveHex({
    required String xprvBase58,
    required int length,
    required int index,
    String? alias,
    Bip85UsageColumn usage = Bip85UsageColumn.manual,
  }) async {
    try {
      const application = Bip85ApplicationColumn.hex;
      final derivationPath = "${application.number}'/$length'/$index'";

      // Ensure the xprv is valid.
      final xprv = bip32.Bip32Keys.fromBase58(xprvBase58);

      final bip85Hex = bip85.Bip85Entropy.deriveHex(
        xprvBase58: xprvBase58,
        numBytes: length,
        index: index,
      );

      // store the derivation into sqlite
      await _store(
        Bip85DerivationModel(
          path: derivationPath,
          xprvFingerprint: hex.encode(xprv.fingerprint),
          alias: alias,
          status: Bip85StatusColumn.active,
          usage: usage,
          application: application,
        ),
      );

      return (derivation: derivationPath, hex: bip85Hex);
    } catch (e) {
      rethrow;
    }
  }

  Future<({String derivation, bip39.Mnemonic mnemonic})> deriveMnemonic({
    required String xprvBase58,
    required bip39.MnemonicLength length,
    required int index,
    String? alias,
    Bip85UsageColumn usage = Bip85UsageColumn.manual,
    bip39.Language language = bip39.Language.english,
  }) async {
    try {
      const application = Bip85ApplicationColumn.bip39;
      final derivationPath = _mnemonicDerivationPath(
        length: length,
        index: index,
        language: language,
      );

      // Ensure the xprv is valid.
      final xprv = bip32.Bip32Keys.fromBase58(xprvBase58);

      final bip85Mnemonic = bip85.Bip85Entropy.deriveMnemonic(
        xprvBase58: xprvBase58,
        language: language,
        length: length,
        index: index,
      );

      // store the derivation into sqlite
      await _store(
        Bip85DerivationModel(
          path: derivationPath,
          xprvFingerprint: hex.encode(xprv.fingerprint),
          alias: alias,
          status: Bip85StatusColumn.active,
          usage: usage,
          application: application,
        ),
      );

      return (derivation: derivationPath, mnemonic: bip85Mnemonic);
    } catch (e) {
      rethrow;
    }
  }

  Future<({String derivation, bip39.Mnemonic mnemonic})> deriveMnemonicPreview({
    required String xprvBase58,
    required bip39.MnemonicLength length,
    required int index,
    bip39.Language language = bip39.Language.english,
  }) async {
    try {
      const application = Bip85ApplicationColumn.bip39;
      final derivationPath =
          "${application.number}'/${language.toBip85Code()}'/${length.toBip85Code()}'/$index'";

      // Ensure the xprv is valid.
      bip32.Bip32Keys.fromBase58(xprvBase58);

      final bip85Mnemonic = bip85.Bip85Entropy.deriveMnemonic(
        xprvBase58: xprvBase58,
        language: language,
        length: length,
        index: index,
      );

      return (derivation: derivationPath, mnemonic: bip85Mnemonic);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> recordMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
    String? alias,
    Bip85UsageColumn usage = Bip85UsageColumn.manual,
  }) async {
    try {
      const application = Bip85ApplicationColumn.bip39;
      final xprv = bip32.Bip32Keys.fromBase58(xprvBase58);
      final xprvFingerprint = hex.encode(xprv.fingerprint);
      final existing = await fetch(
        xprvFingerprint: xprvFingerprint,
        path: derivationPath,
      );
      if (existing != null) return;

      await _store(
        Bip85DerivationModel(
          path: derivationPath,
          xprvFingerprint: xprvFingerprint,
          alias: alias,
          status: Bip85StatusColumn.active,
          usage: usage,
          application: application,
        ),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> delete({
    required String xprvFingerprint,
    required String path,
  }) async {
    try {
      await _sqlite.customStatement(
        '''
DELETE FROM bip85_derivations
WHERE xprv_fingerprint = ? AND path = ?;
''',
        [xprvFingerprint, path],
      );
    } catch (e) {
      rethrow;
    }
  }

  String _mnemonicDerivationPath({
    required bip39.MnemonicLength length,
    required int index,
    required bip39.Language language,
  }) {
    const application = Bip85ApplicationColumn.bip39;
    return "${application.number}'/${language.toBip85Code()}'/${length.toBip85Code()}'/$index'";
  }

  Future<Bip85DerivationModel?> fetch({
    required String xprvFingerprint,
    required String path,
  }) async {
    final row = await _sqlite.managers.bip85Derivations
        .filter((b) => b.xprvFingerprint(xprvFingerprint) & b.path(path))
        .getSingleOrNull();

    return row != null ? Bip85DerivationModel.fromSqlite(row) : null;
  }

  Future<int> fetchNextIndexForApplication(
    Bip85ApplicationColumn application,
    String xprvFingerprint, {
    Set<int> excludedIndexes = const {},
    Bip85UsageColumn? usage,
  }) async {
    final rows = await _sqlite.managers.bip85Derivations.filter((b) {
      var predicate =
          b.application(application) & b.xprvFingerprint(xprvFingerprint);
      if (usage != null) {
        predicate = predicate & b.usage(usage);
      }
      return predicate;
    }).get();

    final models = rows
        .map((row) => Bip85DerivationModel.fromSqlite(row))
        .toList();

    final usedIndexes = models.map((model) => model.index).toSet();
    var nextIndex = 0;
    while (usedIndexes.contains(nextIndex) ||
        excludedIndexes.contains(nextIndex)) {
      nextIndex += 1;
    }

    return nextIndex;
  }

  Future<List<Bip85DerivationModel>> fetchAll({Bip85UsageColumn? usage}) async {
    try {
      final rows = await _sqlite.managers.bip85Derivations.filter((b) {
        if (usage == null) return const Constant(true);
        return b.usage(usage);
      }).get();
      return rows.map((row) => Bip85DerivationModel.fromSqlite(row)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> revoke({
    required String xprvFingerprint,
    required String path,
  }) async {
    try {
      await _sqlite.managers.bip85Derivations
          .filter((b) => b.xprvFingerprint(xprvFingerprint) & b.path(path))
          .update((b) => b(status: const Value(Bip85StatusColumn.revoked)));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> activate({
    required String xprvFingerprint,
    required String path,
  }) async {
    try {
      await _sqlite.managers.bip85Derivations
          .filter((b) => b.xprvFingerprint(xprvFingerprint) & b.path(path))
          .update((b) => b(status: const Value(Bip85StatusColumn.active)));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> alias({
    required String xprvFingerprint,
    required String path,
    required String alias,
  }) async {
    try {
      await _sqlite.managers.bip85Derivations
          .filter((b) => b.xprvFingerprint(xprvFingerprint) & b.path(path))
          .update((b) => b(alias: Value(alias)));
    } catch (e) {
      rethrow;
    }
  }

  // We should not use _store without properly formatting the derivation path.
  Future<void> _store(Bip85DerivationModel bip85) async {
    try {
      await _sqlite.managers.bip85Derivations.create(
        (b) => b(
          path: bip85.path,
          xprvFingerprint: bip85.xprvFingerprint,
          alias: Value(bip85.alias),
          status: bip85.status,
          usage: Value(bip85.usage),
          application: bip85.application,
        ),
        mode: InsertMode.insertOrReplace,
      );
    } catch (e) {
      rethrow;
    }
  }
}
