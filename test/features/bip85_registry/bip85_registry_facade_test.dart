import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const registry = Bip85RegistryFacade();

  test('exposes only the BTCPay wallet seed reservation', () {
    expect(registry.reservations, hasLength(1));
    expect(registry.reservations.single.id, 'btcpay_wallet_seed');
    expect(registry.reservationById('btcpay_wallet_seed')?.id,
        'btcpay_wallet_seed');
    expect(registry.reservationById('unknown_reservation'), isNull);
  });

  test('models BTCPay as a BIP39 child mnemonic exact path', () {
    final reservation = registry.btcpayWalletSeed;

    expect(reservation.application.number, 39);
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
    expect(reservation.walletIndex, 100);
  });
}
