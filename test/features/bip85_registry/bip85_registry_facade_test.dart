import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const registry = Bip85RegistryFacade();

  test('exposes only the BTCPay wallet seed reservation', () {
    expect(registry.reservations, hasLength(1));
    expect(registry.reservations.single.id, 'btcpay_wallet_seed');
  });

  test('models BTCPay as a BIP39 child mnemonic exact path', () {
    final reservation = registry.btcpayWalletSeed;

    expect(reservation.application.number, 39);
    expect(reservation.application.name, 'bip39Mnemonic');
    expect(reservation.application.standard, isTrue);
    expect(reservation.scope.exactPath, "39'/0'/12'/100'");
    expect(reservation.scope.segments.map((segment) => segment.name), [
      'language',
      'words',
      'index',
    ]);
    expect(reservation.scope.segments.map((segment) => segment.value), [
      0,
      12,
      100,
    ]);
  });

  test('resolves and blocks only the exact BTCPay path', () {
    expect(
      registry.reservationByExactPath("39'/0'/12'/100'")?.id,
      'btcpay_wallet_seed',
    );
    expect(
      registry.isExactPathReservedForManualAllocation("39'/0'/12'/100'"),
      isTrue,
    );
    expect(registry.reservationByExactPath("39'/0'/12'/99'"), isNull);
    expect(
      registry.isExactPathReservedForManualAllocation("39'/0'/12'/99'"),
      isFalse,
    );
  });

  test('keeps wallet hints non-authoritative and scoped to BTCPay', () {
    final wallets = registry.btcpayWalletSeed.hints.wallets;

    expect(wallets.map((wallet) => wallet.id), [
      'btcpay_bitcoin',
      'btcpay_liquid',
    ]);
    expect(wallets.map((wallet) => wallet.networkFamily), [
      Bip85NetworkFamily.bitcoin,
      Bip85NetworkFamily.liquid,
    ]);
  });
}
