// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_backup_wallet.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/nostr_key_display.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/get_keychain_manifest_nostr_keys_usecase.dart';

final class GetDefaultWalletNostrKeysUsecase {
  final KeychainManifestBackupWalletPort _wallet;
  final GetKeychainManifestNostrKeysUsecase _getKeys;
  final Bip85RegistryFacade _registry;

  const GetDefaultWalletNostrKeysUsecase({
    required KeychainManifestBackupWalletPort wallet,
    required GetKeychainManifestNostrKeysUsecase getKeys,
    Bip85RegistryFacade registry = const Bip85RegistryFacade(),
  }) : _wallet = wallet,
       _getKeys = getKeys,
       _registry = registry;

  /// The default wallet's listable Nostr keys.
  ///
  /// Retired system roles are excluded here, at the domain boundary, so no
  /// presentation layer can surface one. The exclusion is read-side only: the
  /// rows stay in the database and in the manifest backup untouched, because
  /// dropping them would rewrite recoverable inventory.
  Future<List<KeychainManifestNostrKeyRecord>> execute() async {
    final source = await _wallet.deriveDefaultWallet();
    final records = await _getKeys.execute(source.parentFingerprint);
    return records
        .where(
          (record) => !KeychainManifestNostrKeyDisplay.of(
            record,
            registry: _registry,
          ).isObsolete,
        )
        .toList(growable: false);
  }
}
