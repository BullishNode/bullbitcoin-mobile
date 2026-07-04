import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';

/// The single production chokepoint for publishing the encrypted Nostr backup
/// snapshot (§3.2). Every consent/empty/xprv gate lives here; no other code
/// calls `KeychainManifestFacade.publishEncryptedNostrSnapshot`.
///
/// Best-effort by contract (AD-3 post-commitment): [execute] NEVER throws and
/// NEVER passes `allowEmpty` — the facade method has no such parameter, so an
/// empty inventory can only surface as a logged skip, never an empty NIP-33
/// event that would tombstone a populated backup.
class PublishAutomatedKeychainBackupUsecase {
  final GetPaidSettingsRepository _repository;
  final GetPaidSettingsDefaultWalletXprvPort _xprvPort;
  final KeychainManifestFacade _keychainManifest;
  final NostrRelayPolicyFacade _relayPolicy;

  const PublishAutomatedKeychainBackupUsecase({
    required this._repository,
    required this._xprvPort,
    required this._keychainManifest,
    required this._relayPolicy,
  });

  Future<void> execute() async {
    try {
      final settings = await _repository.fetch();
      if (!settings.automatedBackupEnabled) {
        log.fine('AUTOBACKUP: skipped, toggle off');
        return;
      }
      final policy = _relayPolicy.getPolicy();
      // AD-8: the default relay set is third-party; publishing requires the
      // acknowledged disclosure. The ack is the SAME persisted value the
      // recovery fetch gate reads.
      if (policy.usesThirdPartyPublicRelays &&
          !settings.backupDisclosureAcknowledged) {
        log.fine('AUTOBACKUP: skipped, disclosure not acknowledged');
        return;
      }
      final wallet = await _xprvPort.deriveDefaultWalletXprv();
      await _keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: wallet.parentFingerprint,
        xprvBase58: wallet.xprvBase58,
        relayUrls: policy.defaultRelays
            .map((relay) => relay.url)
            .toList(growable: false),
      );
      log.fine('AUTOBACKUP: snapshot published');
    } catch (e, stack) {
      // Post-commitment best effort (AD-3): an empty inventory or relay
      // failure must never fail the local operation that triggered the
      // publish. Log id-level detail only; no secret material.
      log.warning(
        'AUTOBACKUP: snapshot publish failed',
        error: e,
        trace: stack,
      );
    }
  }
}
