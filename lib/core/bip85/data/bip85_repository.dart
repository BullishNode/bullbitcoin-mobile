import 'package:bb_mobile/core/bip85/data/bip85_datasource.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/storage/tables/bip85_derivations_table.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:convert/convert.dart';

class Bip85Repository {
  final Bip85Datasource _datasource;

  Bip85Repository({required this._datasource});

  Future<({String derivation, String hex})> deriveHex({
    required String xprvBase58,
    required int length,
    required int index,
    String? alias,
  }) async {
    try {
      final result = await _datasource.deriveHex(
        xprvBase58: xprvBase58,
        length: length,
        index: index,
        alias: alias,
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
  }) async {
    try {
      final result = await _datasource.deriveMnemonic(
        xprvBase58: xprvBase58,
        length: length,
        index: index,
        alias: alias,
      );

      return result;
    } catch (e) {
      rethrow;
    }
  }

  Future<({String derivation, bip39.Mnemonic mnemonic})>
  deriveMnemonicPreview({
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

  Future<Bip85DerivationEntity?> fetch(String path) async {
    try {
      final derivation = await _datasource.fetch(path);
      return derivation?.toEntity();
    } catch (e) {
      rethrow;
    }
  }

  String fingerprintFromXprv(String xprvBase58) {
    return hex.encode(bip32.Bip32Keys.fromBase58(xprvBase58).fingerprint);
  }

  Future<int> fetchNextIndexForApplication(Bip85Application application) async {
    try {
      final applicationColumn = Bip85ApplicationColumn.fromEntity(application);
      return await _datasource.fetchNextIndexForApplication(applicationColumn);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Bip85DerivationEntity>> fetchAll() async {
    try {
      final result = await _datasource.fetchAll();
      return result.map((e) => e.toEntity()).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> revoke(Bip85DerivationEntity derivation) async {
    try {
      await _datasource.revoke(derivation.path);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> activate(Bip85DerivationEntity derivation) async {
    try {
      await _datasource.activate(derivation.path);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> alias(Bip85DerivationEntity derivation, String alias) async {
    try {
      await _datasource.alias(derivation.path, alias);
    } catch (e) {
      rethrow;
    }
  }
}
