import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';

enum KeychainManifestReactivationOnRecovery {
  /// Local materialization is sufficient; nothing to re-activate.
  none,

  /// A Bullnym-backed product whose registration must be checked and healed
  /// after its deterministic wallet is restored.
  autoHealOnRecovery,
}

/// Explicit v1 classification of a reserved wallet seed for the keychain
/// manifest: whether it is exported into the backup, whether it is recovered
/// FROM a backup at this stack level, and its post-recovery reactivation
/// intent.
class KeychainManifestReservationClassification {
  /// Included in the v1 manifest backup (so funded product wallets are never
  /// silently excluded - KC-3).
  final bool exportableV1;

  /// Materialized when restoring from a manifest at this stack level.
  final bool recoverableV1;

  final KeychainManifestReactivationOnRecovery reactivationOnRecovery;

  const KeychainManifestReservationClassification({
    required this.exportableV1,
    required this.recoverableV1,
    required this.reactivationOnRecovery,
  });
}

/// v1 keychain-manifest support classification for reserved wallet seeds.
///
/// Every [Bip85WalletSeedReservation] MUST appear in [_classifications]; the
/// AD-4 exhaustiveness test fails the build otherwise, forcing a human backup /
/// recovery decision on any newly reserved product seed rather than silently
/// dropping it from backups (KC-3) or from recovery.
///
/// Recoverability lands per owning PR: BTCPay at pr06, Lightning Address at
/// pr11 (recoverableV1 flips true here, with the requiresProductReactivation
/// flow + KC-6 posture re-applied). Payment Page (102) stays exportable but NOT
/// recoverable through this cascade; POS (103) is a future reservation.
///
/// Later product-owning PRs extend the classification when Payment Page and
/// POS recovery become available.
class KeychainManifestReservationSupport {
  const KeychainManifestReservationSupport._();

  static const _classifications =
      <String, KeychainManifestReservationClassification>{
        'btcpay_wallet_seed': KeychainManifestReservationClassification(
          exportableV1: true,
          recoverableV1: true,
          reactivationOnRecovery: KeychainManifestReactivationOnRecovery.none,
        ),
        // LN recovery is added by this PR (pr11): recoverableV1 flips to true
        // here. Its registration cannot be proven live from local state, so
        // remote recovery checks and heals it after materialization.
        'lightning_address_wallet_seed':
            KeychainManifestReservationClassification(
              exportableV1: true,
              recoverableV1: true,
              reactivationOnRecovery:
                  KeychainManifestReactivationOnRecovery.autoHealOnRecovery,
            ),
        'payment_page_wallet_seed': KeychainManifestReservationClassification(
          exportableV1: true,
          recoverableV1: false,
          reactivationOnRecovery:
              KeychainManifestReactivationOnRecovery.autoHealOnRecovery,
        ),
      };

  /// The classification for a wallet-seed reservation, or null for a
  /// non-wallet-seed reservation or an unclassified one.
  static KeychainManifestReservationClassification? classificationFor(
    Bip85Reservation reservation,
  ) {
    if (reservation is! Bip85WalletSeedReservation) return null;
    return _classifications[reservation.id];
  }

  /// Whether restoring this reservation's wallet materialization requires the
  /// owning product to be reactivated. Manifest recovery restores local wallet
  /// metadata but cannot prove that an external (Bullnym) registration is still
  /// active, so recovered bullnym-backed wallets are surfaced as requiring
  /// reactivation. Remote recovery uses this to run the owning product's
  /// conditional lookup/re-registration flow.
  static bool requiresProductReactivationOnRecovery(
    Bip85Reservation reservation,
  ) {
    return classificationFor(reservation)?.reactivationOnRecovery ==
        KeychainManifestReactivationOnRecovery.autoHealOnRecovery;
  }

  /// Whether the reserved seed is written into the v1 manifest backup
  /// (btcpay + lightning_address + payment_page - R2-KC3, decision [B]).
  static bool supportsV1Export(Bip85Reservation reservation) =>
      classificationFor(reservation)?.exportableV1 ?? false;

  /// Whether the reserved seed is materialized when restoring from a v1
  /// manifest at this stack level.
  static bool supportsV1Recovery(Bip85Reservation reservation) =>
      classificationFor(reservation)?.recoverableV1 ?? false;

  /// Every explicitly classified wallet-seed reservation id, for the AD-4
  /// exhaustiveness test.
  static Set<String> get classifiedReservationIds =>
      _classifications.keys.toSet();
}
