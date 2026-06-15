import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_wallet_behavior_defaults_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_wallet.dart';

const _lightningAddressLiquidSpecId = 'lightning-address-liquid';
const _lightningAddressLiquidLabel = 'Lightning Address Liquid';

class PrepareLightningAddressWalletUsecase {
  final GetSettingsUsecase _getSettings;
  final DeterministicWalletsFacade _deterministicWallets;
  final KeychainManifestFacade _keychainManifest;
  final Bip85RegistryFacade _bip85Registry;
  final ApplyWalletBehaviorDefaultsUsecase _applyWalletBehaviorDefaults;

  const PrepareLightningAddressWalletUsecase({
    required this._getSettings,
    required this._deterministicWallets,
    required this._keychainManifest,
    required this._applyWalletBehaviorDefaults,
    this._bip85Registry = const Bip85RegistryFacade(),
  });

  Future<PreparedLightningAddressWallet> execute() async {
    PreparedDeterministicWallets? preparedWallets;
    try {
      final settings = await _getSettings.execute();
      preparedWallets = await _deterministicWallets.prepare(
        _lightningAddressWalletRequest(settings.environment),
      );
      await _recordKeychainManifestEntry(preparedWallets);
      final preparedWallet = preparedWallets.wallets.single;
      await _applyLightningAddressWalletDefaults(preparedWallet.wallet.id);
      return PreparedLightningAddressWallet(
        walletId: preparedWallet.walletId,
        ctDescriptor: preparedWallet.externalPublicDescriptor,
        created: preparedWallet.created,
      );
    } on LightningAddressException {
      if (preparedWallets != null) {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
      }
      rethrow;
    } on DeterministicWalletException catch (e) {
      if (preparedWallets != null) {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
      }
      if (e.type == DeterministicWalletExceptionType.generic) {
        throw const LightningAddressException.localPreparationFailed(
          code: 'DeterministicWalletPreparationFailed',
          retryable: true,
        );
      }
      throw const LightningAddressException.unexpected();
    } on KeychainManifestException catch (e) {
      if (preparedWallets != null) {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
      }
      throw LightningAddressException.localPreparationFailed(
        code: 'KeychainManifestRecordFailed',
        retryable: _isRetryableManifestFailure(e),
      );
    } catch (_) {
      if (preparedWallets != null) {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
      }
      throw const LightningAddressException.unexpected();
    }
  }

  DeterministicWalletsRequest _lightningAddressWalletRequest(
    Environment environment,
  ) {
    final reservation = _bip85Registry.lightningAddressWalletSeed;
    final policy = _materializationPolicy(reservation);
    return DeterministicWalletsRequest(
      bip85Index: reservation.scope.segmentValue('index'),
      bip85Alias: reservation.deterministicAlias,
      environment: environment,
      walletSpecs: [
        DeterministicWalletSpec(
          id: _lightningAddressLiquidSpecId,
          network: Network.values.byName(
            policy.networkNameForEnvironment(environment.name),
          ),
          scriptType: ScriptType.values.byName(policy.scriptType),
          label: _lightningAddressLiquidLabel,
          isDefault: false,
          sync: false,
        ),
      ],
    );
  }

  Future<void> _recordKeychainManifestEntry(
    PreparedDeterministicWallets preparedWallets,
  ) {
    final reservation = _bip85Registry.lightningAddressWalletSeed;
    final policy = _materializationPolicy(reservation);
    final preparedWallet = preparedWallets.wallets.single;
    return _keychainManifest.recordReservedDerivation(
      KeychainManifestReservedDerivationRequest(
        reservationId: reservation.id,
        parentFingerprint: preparedWallets.parentFingerprint,
        materializations: [
          KeychainManifestWalletMaterializationRequest(
            walletId: preparedWallet.walletId,
            childSeedFingerprint: preparedWallets.childSeedFingerprint,
            network: preparedWallet.network,
            walletPurpose: policy.walletPurpose,
            scriptType: preparedWallet.scriptType,
          ),
        ],
      ),
    );
  }

  Future<void> _applyLightningAddressWalletDefaults(String walletId) async {
    try {
      await _applyWalletBehaviorDefaults.execute(
        walletId: walletId,
        hideOnHome: true,
        autoSweepEnabled: true,
      );
    } catch (e) {
      throw const LightningAddressException.localPreparationFailed(
        code: 'WalletDefaultsFailed',
        retryable: true,
      );
    }
  }

  Bip85WalletMaterializationPolicy _materializationPolicy(
    Bip85Reservation reservation,
  ) {
    final policy = reservation.walletMaterializationPolicy;
    if (policy == null) {
      throw const LightningAddressException.unexpected();
    }
    return policy;
  }

  Future<void> _rollbackPreparedWalletsBestEffort(
    PreparedDeterministicWallets preparedWallets,
  ) async {
    try {
      await _deterministicWallets.rollbackCreatedWallets(preparedWallets);
    } catch (_) {
      // The caller still receives the original failure; cleanup is best effort.
    }
  }

  bool _isRetryableManifestFailure(KeychainManifestException error) {
    return switch (error.type) {
      KeychainManifestExceptionType.generic ||
      KeychainManifestExceptionType.fileParse ||
      KeychainManifestExceptionType.emptyInventory => true,
      KeychainManifestExceptionType.invalidEntry ||
      KeychainManifestExceptionType.reservationMismatch ||
      KeychainManifestExceptionType.conflict ||
      KeychainManifestExceptionType.duplicate => false,
    };
  }
}
