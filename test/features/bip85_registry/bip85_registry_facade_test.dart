import 'package:bb_mobile/core/bip85/data/bip85_datasource.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Master BIP32 root key from the official BIP85 test vectors.
const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';

void main() {
  const registry = Bip85RegistryFacade();

  test('exposes only the BTCPay wallet seed reservation', () {
    expect(registry.reservations, hasLength(1));
    expect(registry.reservations.single.id, 'btcpay_wallet_seed');
    expect(
      registry.reservationById('btcpay_wallet_seed')?.id,
      'btcpay_wallet_seed',
    );
    expect(registry.reservationById('unknown_reservation'), isNull);
  });

  test('reserves the locked BIP39 English 12-word path at index 100', () {
    final reservation = registry.btcpayWalletSeed;

    expect(reservation.application.number, 39);
    expect(
      reservation.scope.segmentValue('language'),
      bip39.Language.english.toBip85Code(),
    );
    expect(
      reservation.scope.segmentValue('words'),
      bip39.MnemonicLength.words12.toBip85Code(),
    );
    expect(reservation.walletIndex, 100);
    expect(reservation.scope.exactPath, "39'/0'/12'/100'");
  });

  group('against the core BIP85 datasource', () {
    late SqliteDatabase database;
    late Bip85Datasource datasource;

    setUp(() {
      database = SqliteDatabase(NativeDatabase.memory());
      datasource = Bip85Datasource(sqlite: database);
    });

    tearDown(() => database.close());

    test(
      'encodes the reserved path exactly as the datasource derives it',
      () async {
        final reservation = registry.btcpayWalletSeed;

        final preview = await datasource.deriveMnemonicPreview(
          xprvBase58: _masterXprv,
          length: bip39.MnemonicLength.words12,
          index: reservation.walletIndex,
        );

        expect(preview.derivation, reservation.scope.exactPath);
      },
    );

    test('derives the pinned mnemonic at the reserved index', () async {
      final preview = await datasource.deriveMnemonicPreview(
        xprvBase58: _masterXprv,
        length: bip39.MnemonicLength.words12,
        index: registry.btcpayWalletSeed.walletIndex,
      );

      expect(
        preview.mnemonic.sentence,
        'nurse knock brief chronic category music mosquito sell clean proud '
        'useful soon',
      );
    });
  });
}
