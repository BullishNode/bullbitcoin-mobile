import 'package:bb_mobile/core/bip85/data/bip85_datasource.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Master BIP32 root key from the official BIP85 test vectors.
const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';

/// A second, unrelated root key (the BIP85 XPRV application output from the
/// same spec) so tests can simulate a replaced default wallet seed.
const _otherXprv =
    'xprv9s21ZrQH143K2srSbCSg4m4kLvPMzcWydgmKEnMmoZUurYuBuYG46c6P71UGXMzmriLzCCBvKQWBUv3vPB3m1SATMhp3uEjXHJ42jFg7myX';

void main() {
  late SqliteDatabase database;
  late Bip85Datasource datasource;

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    datasource = Bip85Datasource(sqlite: database);
  });

  tearDown(() => database.close());

  test('replaces stored row when fingerprint is stale', () async {
    final stale = await datasource.deriveMnemonic(
      xprvBase58: _otherXprv,
      length: bip39.MnemonicLength.words12,
      index: 0,
      alias: 'Old',
    );

    final replaced = await datasource.deriveMnemonic(
      xprvBase58: _masterXprv,
      length: bip39.MnemonicLength.words12,
      index: 0,
      alias: 'New',
    );

    expect(replaced.derivation, stale.derivation);
    expect(replaced.mnemonic.sentence, isNot(stale.mnemonic.sentence));
    final row = await datasource.fetch(replaced.derivation);
    expect(row, isNotNull);
    expect(row!.alias, 'New');
  });

  test('rejects duplicate insert for the same fingerprint', () async {
    await datasource.deriveMnemonic(
      xprvBase58: _masterXprv,
      length: bip39.MnemonicLength.words12,
      index: 0,
      alias: 'BTCPay',
    );

    expect(
      () => datasource.deriveMnemonic(
        xprvBase58: _masterXprv,
        length: bip39.MnemonicLength.words12,
        index: 0,
        alias: 'BTCPay',
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  group('official BIP85 application 39 test vectors', () {
    // Expected values from the BIP85 specification
    // (https://github.com/bitcoin/bips/blob/master/bip-0085.mediawiki),
    // matching the vectors bundled with the bip85_entropy package.
    test('derives the 12-word English mnemonic at index 0', () async {
      final result = await datasource.deriveMnemonic(
        xprvBase58: _masterXprv,
        length: bip39.MnemonicLength.words12,
        index: 0,
        alias: 'Vector',
      );

      expect(
        result.mnemonic.sentence,
        'girl mad pet galaxy egg matter matrix prison refuse sense ordinary '
        'nose',
      );
      expect(result.derivation, "39'/0'/12'/0'");

      final stored = await datasource.fetch("39'/0'/12'/0'");
      expect(stored, isNotNull);
      expect(stored!.path, "39'/0'/12'/0'");
      expect(stored.index, 0);
    });

    test('preview derives the same 12-word vector without storing', () async {
      final preview = await datasource.deriveMnemonicPreview(
        xprvBase58: _masterXprv,
        length: bip39.MnemonicLength.words12,
        index: 0,
      );

      expect(
        preview.mnemonic.sentence,
        'girl mad pet galaxy egg matter matrix prison refuse sense ordinary '
        'nose',
      );
      expect(preview.derivation, "39'/0'/12'/0'");
      expect(await datasource.fetch("39'/0'/12'/0'"), isNull);
    });

    test('derives the 18-word English mnemonic at index 0', () async {
      final preview = await datasource.deriveMnemonicPreview(
        xprvBase58: _masterXprv,
        length: bip39.MnemonicLength.words18,
        index: 0,
      );

      expect(
        preview.mnemonic.sentence,
        'near account window bike charge season chef number sketch tomorrow '
        'excuse sniff circle vital hockey outdoor supply token',
      );
      expect(preview.derivation, "39'/0'/18'/0'");
    });

    test('derives the 24-word English mnemonic at index 0', () async {
      final preview = await datasource.deriveMnemonicPreview(
        xprvBase58: _masterXprv,
        length: bip39.MnemonicLength.words24,
        index: 0,
      );

      expect(
        preview.mnemonic.sentence,
        'puppy ocean match cereal symbol another shed magic wrap hammer bulb '
        'intact gadget divorce twin tonight reason outdoor destroy simple '
        'truth cigar social volcano',
      );
      expect(preview.derivation, "39'/0'/24'/0'");
    });
  });
}
