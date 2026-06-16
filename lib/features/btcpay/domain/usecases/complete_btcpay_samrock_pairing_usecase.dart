import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_wallet_behavior_defaults_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_error.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection_repository.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';

class CompleteBtcpaySamRockPairingUsecase {
  final GetSettingsUsecase _getSettings;
  final SamRockPairingRequestParser _parser;
  final DeterministicWalletsFacade _deterministicWallets;
  final SamRockPairingServicePort _pairingService;
  final BtcpayConnectionRepository _connectionRepository;
  final ApplyWalletBehaviorDefaultsUsecase _applyWalletBehaviorDefaults;
  final Bip85RegistryFacade _bip85Registry;
  final KeychainManifestFacade _keychainManifest;

  const CompleteBtcpaySamRockPairingUsecase({
    required this._getSettings,
    required this._parser,
    required this._deterministicWallets,
    required this._pairingService,
    required this._connectionRepository,
    required this._applyWalletBehaviorDefaults,
    required this._bip85Registry,
    required this._keychainManifest,
  });

  Future<BtcpayConnection> execute({required String pairingUrl}) async {
    final SamRockPairingRequest request;
    try {
      request = _parser.parse(pairingUrl);
    } on SamRockPairingRequestException catch (e) {
      throw BtcpayPairingException.invalidRequest(e.message);
    }

    var submitAttempted = false;
    PreparedDeterministicWallets? preparedWallets;
    BtcpayConnection? submittedConnection;
    try {
      final settings = await _getSettings.execute();
      preparedWallets = await _deterministicWallets.prepare(
        _btcpayWalletsRequest(settings.environment),
      );
      await _recordBtcpayKeychainManifestEntries(preparedWallets);

      final Map<String, Object?> payload;
      try {
        payload = const SamRockSetupPayloadBuilder().build(
          request: request,
          preparedWallets: preparedWallets,
        );
      } on SamRockSetupPayloadException {
        rethrow;
      }

      final now = DateTime.now().toUtc();
      submittedConnection = BtcpayConnection.fromPairing(
        environment: settings.environment,
        request: request,
        walletNetworks: _walletNetworks(preparedWallets),
        walletIds: _walletIds(preparedWallets),
        status: BtcpayConnectionStatus.uncertain,
        updatedAt: now,
      );
      submitAttempted = true;
      final response = await _pairingService.submitSetup(
        request: request,
        payload: payload,
      );
      if (!response.success) {
        if (response.serverFailure) {
          await _saveUncertainBestEffort(
            submittedConnection.copyWith(
              updatedAt: DateTime.now().toUtc(),
              lastError: _safeUncertainMessage,
            ),
          );
          throw BtcpayPairingException.uncertain(response.message);
        }
        throw BtcpayPairingException.rejected(response.message);
      }
      await _applyBtcpayWalletBehaviorDefaults(preparedWallets);
    } on BtcpayPairingException {
      rethrow;
    } catch (e, stack) {
      if (submitAttempted) {
        if (submittedConnection != null) {
          log.warning(
            'BTCPay setup was submitted but completion failed',
            error: e,
            trace: stack,
          );
          await _saveUncertainBestEffort(
            submittedConnection.copyWith(
              updatedAt: DateTime.now().toUtc(),
              lastError: _safeUncertainMessage,
            ),
          );
        }
        throw BtcpayPairingException.uncertain(
          'BTCPay setup was submitted, but completion could not be confirmed',
        );
      }
      log.warning(
        preparedWallets == null
            ? 'BTCPay pairing failed before wallet materialization completed'
            : 'BTCPay pairing failed before descriptor submission; '
                  'prepared wallets were kept for retry',
        error: e,
        trace: stack,
      );
      if (preparedWallets != null) {
        throw BtcpayPairingException.localSetup();
      }
      if (e is SamRockSetupPayloadException) {
        throw BtcpayPairingException.generic(e.message);
      }
      throw BtcpayPairingException.generic();
    }

    final pairedAt = DateTime.now().toUtc();
    final connection = BtcpayConnection.fromPairing(
      environment: submittedConnection.environment,
      request: request,
      walletNetworks: _walletNetworks(preparedWallets),
      walletIds: _walletIds(preparedWallets),
      status: BtcpayConnectionStatus.paired,
      pairedAt: pairedAt,
      updatedAt: pairedAt,
    );
    try {
      await _connectionRepository.saveConnection(connection);
    } catch (e) {
      await _saveUncertainBestEffort(
        submittedConnection.copyWith(
          updatedAt: DateTime.now().toUtc(),
          lastError: _safeLocalSaveMessage,
        ),
      );
      throw BtcpayPairingException.uncertain(
        'BTCPay setup was submitted, but local pairing state could not be saved',
      );
    }
    return connection;
  }

  Future<void> _saveUncertainBestEffort(BtcpayConnection connection) async {
    try {
      await _connectionRepository.saveConnection(
        connection.copyWith(status: BtcpayConnectionStatus.uncertain),
      );
    } catch (e, stack) {
      log.warning(
        'BTCPay pairing uncertainty state could not be saved',
        error: e,
        trace: stack,
      );
    }
  }

  Future<void> _recordBtcpayKeychainManifestEntries(
    PreparedDeterministicWallets preparedWallets,
  ) async {
    await _keychainManifest.recordReservedDerivation(
      _btcpayKeychainManifestRequest(preparedWallets),
    );
  }

  KeychainManifestReservedDerivationRequest _btcpayKeychainManifestRequest(
    PreparedDeterministicWallets preparedWallets,
  ) {
    final reservation = _bip85Registry.btcpayWalletSeed;
    return KeychainManifestReservedDerivationRequest(
      reservationId: reservation.id,
      parentFingerprint: preparedWallets.parentFingerprint,
      materializations: preparedWallets.wallets
          .map((prepared) {
            final network = BtcpayWalletNetwork.fromSpecId(prepared.specId);
            return KeychainManifestWalletMaterializationRequest(
              walletId: prepared.walletId,
              childSeedFingerprint: preparedWallets.childSeedFingerprint,
              network: prepared.network,
              walletPurpose: network.name,
              scriptType: prepared.scriptType,
            );
          })
          .toList(growable: false),
    );
  }

  DeterministicWalletsRequest _btcpayWalletsRequest(Environment environment) {
    final reservation = _bip85Registry.btcpayWalletSeed;
    return DeterministicWalletsRequest(
      bip85Index: reservation.walletIndex,
      bip85Alias: BtcpayWalletConstants.bip85Alias,
      environment: environment,
      walletSpecs: BtcpayWalletNetwork.values.map((btcpayNetwork) {
        return DeterministicWalletSpec(
          id: btcpayNetwork.specId,
          network: btcpayNetwork.networkForEnvironment(environment),
          scriptType: ScriptType.bip84,
          label: btcpayNetwork.walletLabel,
          isDefault: false,
          sync: false,
        );
      }).toList(),
    );
  }

  List<BtcpayWalletNetwork> _walletNetworks(
    PreparedDeterministicWallets preparedWallets,
  ) {
    return preparedWallets.wallets
        .map((wallet) => BtcpayWalletNetwork.fromSpecId(wallet.specId))
        .toList();
  }

  Map<BtcpayWalletNetwork, String> _walletIds(
    PreparedDeterministicWallets preparedWallets,
  ) {
    return {
      for (final wallet in preparedWallets.wallets)
        BtcpayWalletNetwork.fromSpecId(wallet.specId): wallet.walletId,
    };
  }

  /// Applies the BTCPay wallet behavior defaults best-effort: the server has
  /// already accepted the descriptors at this point, so a local
  /// defaults-application failure must not degrade a successful pairing.
  Future<void> _applyBtcpayWalletBehaviorDefaults(
    PreparedDeterministicWallets preparedWallets,
  ) async {
    for (final prepared in preparedWallets.wallets) {
      final network = BtcpayWalletNetwork.fromSpecId(prepared.specId);
      try {
        await _applyWalletBehaviorDefaults.execute(
          walletId: prepared.walletId,
          hideOnHome: network == BtcpayWalletNetwork.liquid,
          autoSweepEnabled: network == BtcpayWalletNetwork.liquid,
        );
      } catch (e, stack) {
        log.warning(
          'BTCPay wallet behavior defaults could not be applied',
          error: e,
          trace: stack,
        );
      }
    }
  }
}

const _safeUncertainMessage =
    'BTCPay setup was submitted, but completion could not be confirmed';
const _safeLocalSaveMessage =
    'BTCPay setup was submitted, but local pairing state could not be saved';
