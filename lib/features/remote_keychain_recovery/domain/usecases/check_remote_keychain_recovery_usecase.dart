// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';

class CheckRemoteKeychainRecoveryUsecase {
  final RemoteKeychainRecoveryDefaultWalletXprvPort _defaultWalletXprv;
  final KeychainManifestFacade _keychainManifest;
  final NostrRelayPolicyFacade _relayPolicy;

  const CheckRemoteKeychainRecoveryUsecase({
    required RemoteKeychainRecoveryDefaultWalletXprvPort defaultWalletXprv,
    required KeychainManifestFacade keychainManifest,
    required NostrRelayPolicyFacade relayPolicy,
  }) : _defaultWalletXprv = defaultWalletXprv,
       _keychainManifest = keychainManifest,
       _relayPolicy = relayPolicy;

  Future<RemoteKeychainRecoveryCheckResult> execute({
    required bool acceptedThirdPartyRelayDisclosure,
  }) async {
    final policy = _relayPolicy.getPolicy();
    if (policy.usesThirdPartyPublicRelays &&
        !acceptedThirdPartyRelayDisclosure) {
      return const RemoteKeychainRecoveryCheckResult.requiresRelayDisclosure();
    }
    final KeychainManifestNostrImportResult manifestResult;
    try {
      final defaultWallet = await _defaultWalletXprv.deriveDefaultWalletXprv();
      manifestResult = await _keychainManifest.fetchEncryptedNostrImportPlan(
        parentFingerprint: defaultWallet.parentFingerprint,
        xprvBase58: defaultWallet.xprvBase58,
        relayUrls: policy.defaultRelays
            .map((relay) => relay.url)
            .toList(growable: false),
        // The relay-disclosure gate above has already been satisfied to reach
        // here; pass the checked consent value through the (P21c) fetch gate so
        // it stays structurally non-bypassable.
        acceptedThirdPartyRelayDisclosure: acceptedThirdPartyRelayDisclosure,
      );
    } on RemoteKeychainRecoveryException {
      rethrow;
    } catch (e) {
      throw ManifestCheckFailedRecoveryException(cause: e);
    }
    return switch (manifestResult.status) {
      KeychainManifestNostrImportStatus.latestRecoverable =>
        RemoteKeychainRecoveryCheckResult.latestManifestReady(
          manifestResult: manifestResult,
        ),
      KeychainManifestNostrImportStatus.newestFailedOlderRecoverable =>
        RemoteKeychainRecoveryCheckResult.olderManifestAvailable(
          manifestResult: manifestResult,
        ),
      KeychainManifestNostrImportStatus.noManifestFound =>
        const RemoteKeychainRecoveryCheckResult.noManifestFound(),
      KeychainManifestNostrImportStatus.relaysUnavailable =>
        const RemoteKeychainRecoveryCheckResult.relaysUnavailable(),
      KeychainManifestNostrImportStatus.noRecoverableManifest =>
        const RemoteKeychainRecoveryCheckResult.noRecoverableManifest(),
      KeychainManifestNostrImportStatus.unsupportedNewerManifest =>
        const RemoteKeychainRecoveryCheckResult.unsupportedNewerManifest(),
    };
  }
}
