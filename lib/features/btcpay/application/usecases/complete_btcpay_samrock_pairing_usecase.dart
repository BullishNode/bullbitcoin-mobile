import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/btcpay/application/application_errors.dart';
import 'package:bb_mobile/features/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/btcpay/application/ports/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/application/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';

class CompleteBtcpaySamRockPairingUsecase {
  final GetSettingsUsecase _getSettings;
  final SamRockPairingRequestParser _parser;
  final DeterministicWalletsFacade _deterministicWallets;
  final SamRockPairingServicePort _pairingService;
  final BtcpayConnectionStore _connectionStore;

  const CompleteBtcpaySamRockPairingUsecase({
    required GetSettingsUsecase getSettings,
    required SamRockPairingRequestParser parser,
    required DeterministicWalletsFacade deterministicWallets,
    required SamRockPairingServicePort pairingService,
    required BtcpayConnectionStore connectionStore,
  }) : _getSettings = getSettings,
       _parser = parser,
       _deterministicWallets = deterministicWallets,
       _pairingService = pairingService,
       _connectionStore = connectionStore;

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
      final Map<String, Object?> payload;
      try {
        payload = const SamRockSetupPayloadBuilder().build(
          request: request,
          preparedWallets: preparedWallets,
        );
      } on SamRockSetupPayloadException {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
        rethrow;
      }

      final now = DateTime.now().toUtc();
      submittedConnection = BtcpayConnection.fromPairing(
        environment: settings.environment,
        request: request,
        walletNetworks: _walletNetworks(preparedWallets),
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
    } on BtcpayPairingException {
      rethrow;
    } on SamRockSetupPayloadException catch (e) {
      throw BtcpayPairingException.generic(e.message);
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
      if (preparedWallets != null) {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
      }
      log.warning(
        'BTCPay pairing failed before submission',
        error: e,
        trace: stack,
      );
      throw BtcpayPairingException.generic();
    }

    final pairedAt = DateTime.now().toUtc();
    final connection = BtcpayConnection.fromPairing(
      environment: submittedConnection.environment,
      request: request,
      walletNetworks: _walletNetworks(preparedWallets),
      status: BtcpayConnectionStatus.paired,
      pairedAt: pairedAt,
      updatedAt: pairedAt,
    );
    try {
      await _connectionStore.saveConnection(connection);
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
      await _connectionStore.saveConnection(
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

  Future<void> _rollbackPreparedWalletsBestEffort(
    PreparedDeterministicWallets preparedWallets,
  ) async {
    try {
      await _deterministicWallets.rollbackCreatedWallets(preparedWallets);
    } catch (e, stack) {
      log.warning(
        'BTCPay pairing failed before descriptor submission and created '
        'wallet cleanup failed',
        error: e,
        trace: stack,
      );
    }
  }

  DeterministicWalletsRequest _btcpayWalletsRequest(Environment environment) {
    return DeterministicWalletsRequest(
      bip85Index: BtcpayWalletConstants.bip85Index,
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
}

const _safeUncertainMessage =
    'BTCPay setup was submitted, but completion could not be confirmed';
const _safeLocalSaveMessage =
    'BTCPay setup was submitted, but local pairing state could not be saved';
