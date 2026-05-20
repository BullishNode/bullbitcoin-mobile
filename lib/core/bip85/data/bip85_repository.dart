import 'package:bb_mobile/core/bip85/data/bip85_datasource.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/storage/tables/bip85_derivations_table.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:convert/convert.dart';

class Bip85Repository {
  final Bip85Datasource _datasource;

  Bip85Repository({required Bip85Datasource datasource})
    : _datasource = datasource;

  Future<({String derivation, String hex})> deriveHex({
    required String xprvBase58,
    required int length,
    required int index,
    String? alias,
    Bip85Usage usage = Bip85Usage.manual,
  }) async {
    try {
      final result = await _datasource.deriveHex(
        xprvBase58: xprvBase58,
        length: length,
        index: index,
        alias: alias,
        usage: Bip85UsageColumn.fromEntity(usage),
      );

      return result;
    } catch (e) {
      rethrow;
    }
  }

  Future<({String derivation, bip39.Mnemonic mnemonic})> deriveMnemonic({
    required String xprvBase58,
    required bip39.MnemonicLength length,
    required int index,
    String? alias,
    Bip85Usage usage = Bip85Usage.manual,
  }) async {
    try {
      final result = await _datasource.deriveMnemonic(
        xprvBase58: xprvBase58,
        length: length,
        index: index,
        alias: alias,
        usage: Bip85UsageColumn.fromEntity(usage),
      );

      return result;
    } catch (e) {
      rethrow;
    }
  }

  Future<({String derivation, bip39.Mnemonic mnemonic})> deriveMnemonicPreview({
    required String xprvBase58,
    required bip39.MnemonicLength length,
    required int index,
  }) async {
    try {
      return await _datasource.deriveMnemonicPreview(
        xprvBase58: xprvBase58,
        length: length,
        index: index,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> recordMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
    String? alias,
    Bip85Usage usage = Bip85Usage.manual,
  }) async {
    try {
      await _datasource.recordMnemonicDerivation(
        xprvBase58: xprvBase58,
        derivationPath: derivationPath,
        alias: alias,
        usage: Bip85UsageColumn.fromEntity(usage),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
  }) async {
    try {
      await _datasource.delete(
        xprvFingerprint: _fingerprintFromXprv(xprvBase58),
        path: derivationPath,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<int> fetchNextIndexForApplication({
    required Bip85Application application,
    required String xprvBase58,
    Set<int> excludedIndexes = const {},
    Bip85Usage? usage,
  }) async {
    try {
      final applicationColumn = Bip85ApplicationColumn.fromEntity(application);
      final xprvFingerprint = _fingerprintFromXprv(xprvBase58);
      return await _datasource.fetchNextIndexForApplication(
        applicationColumn,
        xprvFingerprint,
        excludedIndexes: excludedIndexes,
        usage: usage == null ? null : Bip85UsageColumn.fromEntity(usage),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Bip85DerivationEntity>> fetchAll({Bip85Usage? usage}) async {
    try {
      final result = await _datasource.fetchAll(
        usage: usage == null ? null : Bip85UsageColumn.fromEntity(usage),
      );
      return result.map((e) => e.toEntity()).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> revoke(Bip85DerivationEntity derivation) async {
    try {
      await _datasource.revoke(
        xprvFingerprint: derivation.xprvFingerprint,
        path: derivation.path,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> activate(Bip85DerivationEntity derivation) async {
    try {
      await _datasource.activate(
        xprvFingerprint: derivation.xprvFingerprint,
        path: derivation.path,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> alias(Bip85DerivationEntity derivation, String alias) async {
    try {
      await _datasource.alias(
        xprvFingerprint: derivation.xprvFingerprint,
        path: derivation.path,
        alias: alias,
      );
    } catch (e) {
      rethrow;
    }
  }

  String _fingerprintFromXprv(String xprvBase58) {
    return hex.encode(bip32.Bip32Keys.fromBase58(xprvBase58).fingerprint);
  }
}
