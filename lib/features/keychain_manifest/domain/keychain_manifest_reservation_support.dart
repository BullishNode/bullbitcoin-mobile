import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';

class KeychainManifestReservationSupport {
  const KeychainManifestReservationSupport._();

  static bool supportsV1WalletManifestFile(Bip85Reservation reservation) {
    return _supportsReservation(reservation);
  }

  static bool supportsWalletMaterializations({
    required Bip85Reservation reservation,
    required List<KeychainManifestWalletMaterializationShape> materializations,
  }) {
    if (!_supportsReservation(reservation)) return false;
    final policy = reservation.walletMaterializationPolicy;
    if (policy == null) return materializations.isNotEmpty;
    if (materializations.length != policy.count) return false;
    return materializations.every((materialization) {
      return policy.networkNames.contains(materialization.network) &&
          materialization.walletPurpose == policy.walletPurpose &&
          materialization.scriptType == policy.scriptType;
    });
  }

  static bool _supportsReservation(Bip85Reservation reservation) {
    return reservation.purpose == Bip85ReservationPurpose.walletSeed &&
        switch (reservation.id) {
          'btcpay_wallet_seed' || 'lightning_address_wallet_seed' => true,
          _ => false,
        };
  }
}

class KeychainManifestWalletMaterializationShape {
  final String network;
  final String walletPurpose;
  final String scriptType;

  const KeychainManifestWalletMaterializationShape({
    required this.network,
    required this.walletPurpose,
    required this.scriptType,
  });
}
