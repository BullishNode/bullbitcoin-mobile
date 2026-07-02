import 'package:bb_mobile/features/bip85_registry/domain/bip85_reservation.dart';

class Bip85Reservations {
  const Bip85Reservations._();

  static final btcpayWalletSeed = Bip85Reservation(
    id: 'btcpay_wallet_seed',
    owner: Bip85ReservationOwner.btcpay,
    purpose: Bip85ReservationPurpose.walletSeed,
    application: const Bip85ApplicationSpec(
      number: 39,
      name: 'bip39Mnemonic',
      standard: true,
    ),
    segments: const [
      Bip85PathSegment(name: 'language', value: 0),
      Bip85PathSegment(name: 'words', value: 12),
      Bip85PathSegment(name: 'index', value: 100),
    ],
    allocation: Bip85AllocationPolicy.blockExactPath,
    manifest: Bip85ManifestPolicy.includeWhenMaterialized,
    hints: const Bip85ReservationHints(
      wallets: [
        Bip85WalletHint(
          id: 'btcpay_bitcoin',
          networkFamily: Bip85NetworkFamily.bitcoin,
          purpose: 'btcpay',
        ),
        Bip85WalletHint(
          id: 'btcpay_liquid',
          networkFamily: Bip85NetworkFamily.liquid,
          purpose: 'btcpay',
        ),
      ],
    ),
  );

  static final all = [btcpayWalletSeed];
}
