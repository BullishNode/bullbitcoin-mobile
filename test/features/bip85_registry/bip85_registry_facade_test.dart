import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const registry = Bip85RegistryFacade();

  test('exposes reserved first-party derivations', () {
    expect(registry.reservations.map((reservation) => reservation.id), [
      'btcpay_wallet_seed',
      'lightning_address_wallet_seed',
      'payment_page_wallet_seed',
      'nostr_wallet_manifest_key',
      'nostr_bullnym_server_auth_key',
      'nostr_nip05_public_nym_verification_key',
    ]);
  });

  test('models Get Paid receive wallets as BIP39 child mnemonic paths', () {
    final reservations = [
      _reservation('btcpay_wallet_seed'),
      _reservation('lightning_address_wallet_seed'),
      _reservation('payment_page_wallet_seed'),
    ];

    expect(reservations.map((reservation) => reservation.scope.exactPath), [
      "39'/0'/12'/100'",
      "39'/0'/12'/101'",
      "39'/0'/12'/102'",
    ]);
    for (final reservation in reservations) {
      expect(reservation.application.number, 39);
      expect(reservation.application.name, 'bip39Mnemonic');
      expect(reservation.application.standard, isTrue);
      expect(reservation.purpose, Bip85ReservationPurpose.walletSeed);
      expect(reservation.scope.segments.map((segment) => segment.name), [
        'language',
        'words',
        'index',
      ]);
      expect(reservation.scope.segmentValue('language'), 0);
      expect(reservation.scope.segmentValue('words'), 12);
    }
    expect(_reservation('btcpay_wallet_seed').scope.segmentValue('index'), 100);
    expect(
      _reservation('lightning_address_wallet_seed').scope.segmentValue('index'),
      101,
    );
    expect(
      _reservation(
        'lightning_address_wallet_seed',
      ).walletMaterializationPolicy?.requiresProductReactivationOnRecovery,
      isTrue,
    );
    expect(
      _reservation('payment_page_wallet_seed').scope.segmentValue('index'),
      102,
    );
  });

  test('models Nostr role paths as reserved policy only', () {
    final reservations = [
      _reservation('nostr_wallet_manifest_key'),
      _reservation('nostr_bullnym_server_auth_key'),
      _reservation('nostr_nip05_public_nym_verification_key'),
    ];

    expect(reservations.map((reservation) => reservation.scope.exactPath), [
      "9000'/1'/1'",
      "9000'/2'/1'",
      "9000'/3'/1'",
    ]);
    expect(reservations.map((reservation) => reservation.purpose), [
      Bip85ReservationPurpose.nonWalletNostrKey,
      Bip85ReservationPurpose.nonWalletNostrKey,
      Bip85ReservationPurpose.nonWalletNostrKey,
    ]);
    for (final reservation in reservations) {
      expect(reservation.owner, Bip85ReservationOwner.nostr);
      expect(reservation.application.number, 9000);
      expect(reservation.application.name, 'nostr');
      expect(reservation.application.standard, isFalse);
      expect(reservation.scope.segments.map((segment) => segment.name), [
        'identity',
        'account',
      ]);
      expect(reservation.scope.segmentValue('account'), 1);
    }
  });

  test('resolves and blocks every exact reserved path', () {
    for (final reservation in registry.reservations) {
      expect(registry.reservationById(reservation.id), same(reservation));
      expect(
        registry.reservationByExactPath(reservation.scope.exactPath),
        same(reservation),
      );
      expect(
        registry.isExactPathReservedForManualAllocation(
          reservation.scope.exactPath,
        ),
        isTrue,
      );
    }
    expect(registry.reservationByExactPath("39'/0'/12'/99'"), isNull);
    expect(
      registry.isExactPathReservedForManualAllocation("39'/0'/12'/99'"),
      isFalse,
    );
  });

  test('keeps reservation ids and exact paths unique', () {
    final ids = registry.reservations.map((reservation) => reservation.id);
    final paths = registry.reservations.map(
      (reservation) => reservation.scope.exactPath,
    );

    expect(ids.toSet(), hasLength(registry.reservations.length));
    expect(paths.toSet(), hasLength(registry.reservations.length));
  });
}

Bip85Reservation _reservation(String id) {
  const registry = Bip85RegistryFacade();
  final reservation = registry.reservationById(id);
  expect(reservation, isNotNull);
  return reservation!;
}
