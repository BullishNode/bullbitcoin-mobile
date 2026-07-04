import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';

/// PR23 forward-obligation for the auto-heal products, recorded as intent only
/// (there is no live reactivation field or flow at this stack level - DG-3).
enum KeychainManifestReactivationOnRecovery {
  /// Local materialization is sufficient; nothing to re-activate.
  none,

  /// A bullnym-backed product (LN address, Payment Page, POS). PR23 must, on
  /// recovery, look the registration up by the seed-derived npub and silently
  /// re-register if missing - NOT prompt unconditionally (DG-3/GATE-1).
  autoHealOnRecoveryPr23,
}

/// Explicit v1 classification of a reserved wallet seed for the keychain
/// manifest: whether it is exported into the backup, whether it is recovered
/// FROM a backup at this stack level, and its post-recovery reactivation
/// intent.
class KeychainManifestReservationClassification {
  /// Included in the v1 manifest backup (so funded product wallets are never
  /// silently excluded - KC-3).
  final bool exportableV1;

  /// Materialized when restoring FROM a manifest at this stack level. Remote
  /// recovery is dormant and unwired until PR23, so only BTCPay (local
  /// materialization, no server dependency) recovers today.
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
/// pr11, and Payment Page (102) at pr23 (recoverableV1 flips true here, with
/// the requiresProductReactivation flow + KC-6 posture re-applied). POS (103)
/// is a future reservation.
///
/// PR23 DISCHARGED (a), (b) and (d) of its forward-obligation (DG-3,
/// decisions [3]/[A]/[D]/[E]):
///   (a) requiresProductReactivation is UPGRADED into the DG-3 auto-heal for
///       the bullnym-backed products (verify the registration by seed-derived
///       npub and silently re-register if missing, keyed off
///       [KeychainManifestReactivationOnRecovery.autoHealOnRecoveryPr23])
///       rather than an unconditional reactivation prompt;
///   (b) Payment Page (102) recovery is added (its recoverableV1 is now true);
///   (d) the KC-6 hidden + autosweep posture is re-applied generically to all
///       restored wallet-seed wallets, so 102 inherits it.
/// Still future:
///   (c) POS (103) recovery lands with the POS reservation (pr28).
/// Note: 102 has no product client surface until the Payment Page PRs, so its
/// autoHealOnRecoveryPr23 reactivation signal is recovered wallet-only for now
/// (the recovered wallet + funds materialize with posture; there is no page to
/// re-save yet).
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
        // here. Its registration cannot be proven live on restore, so it is
        // flagged requiresProductReactivation (PR23 upgrades that to auto-heal).
        'lightning_address_wallet_seed':
            KeychainManifestReservationClassification(
              exportableV1: true,
              recoverableV1: true,
              reactivationOnRecovery:
                  KeychainManifestReactivationOnRecovery.autoHealOnRecoveryPr23,
            ),
        // Payment Page recovery is added by this PR (pr23): recoverableV1 flips
        // to true. Its registration cannot be proven live on restore, so it is
        // flagged autoHealOnRecoveryPr23 (recovered wallet-only until a page
        // client surface exists).
        'payment_page_wallet_seed': KeychainManifestReservationClassification(
          exportableV1: true,
          recoverableV1: true,
          reactivationOnRecovery:
              KeychainManifestReactivationOnRecovery.autoHealOnRecoveryPr23,
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
  /// reactivation. This PR flags it (the unconditional-reactivation precursor);
  /// PR23 upgrades it to the DG-3 conditional auto-heal (seed-npub lookup +
  /// silent reregister-if-missing).
  static bool requiresProductReactivationOnRecovery(
    Bip85Reservation reservation,
  ) {
    return classificationFor(reservation)?.reactivationOnRecovery ==
        KeychainManifestReactivationOnRecovery.autoHealOnRecoveryPr23;
  }

  /// Whether the reserved seed is written into the v1 manifest backup
  /// (btcpay + lightning_address + payment_page - R2-KC3, decision [B]).
  static bool supportsV1Export(Bip85Reservation reservation) =>
      classificationFor(reservation)?.exportableV1 ?? false;

  /// Whether the reserved seed is materialized when restoring from a v1
  /// manifest at this stack level (btcpay + lightning_address + payment_page;
  /// POS (103) recovery is future).
  static bool supportsV1Recovery(Bip85Reservation reservation) =>
      classificationFor(reservation)?.recoverableV1 ?? false;

  /// Every explicitly classified wallet-seed reservation id, for the AD-4
  /// exhaustiveness test.
  static Set<String> get classifiedReservationIds =>
      _classifications.keys.toSet();
}
