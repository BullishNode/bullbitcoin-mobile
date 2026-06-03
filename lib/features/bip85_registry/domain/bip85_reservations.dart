import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';

class Bip85Reservations {
  const Bip85Reservations._();

  static const btcpayWalletSeed = Bip85Reservation(
    id: 'btcpay_wallet_seed',
    owner: Bip85ReservationOwner.btcpay,
    purpose: Bip85ReservationPurpose.walletSeed,
    application: Bip85ApplicationSpec(
      number: 39,
      name: 'bip39Mnemonic',
      standard: true,
    ),
    scope: Bip85ReservationScope(
      exactPath: "39'/0'/12'/100'",
      segments: [
        Bip85PathSegment(name: 'language', value: 0),
        Bip85PathSegment(name: 'words', value: 12),
        Bip85PathSegment(name: 'index', value: 100),
      ],
    ),
    allocation: Bip85AllocationPolicy.blockExactPath,
  );

  static const all = [btcpayWalletSeed];
}
