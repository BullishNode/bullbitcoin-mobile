import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/ports/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';

class CompleteBtcpaySamRockPairingUsecase {
  final SamRockPairingRequestParser _parser;
  final PrepareBtcpayPairingWalletsUsecase _prepareWallets;
  final SamRockSetupPayloadBuilder _payloadBuilder;
  final SamRockPairingServicePort _pairingService;
  final WalletManifestFacade _walletManifest;
  final BtcpayConnectionStore _connectionStore;

  const CompleteBtcpaySamRockPairingUsecase({
    required SamRockPairingRequestParser parser,
    required PrepareBtcpayPairingWalletsUsecase prepareWallets,
    required SamRockSetupPayloadBuilder payloadBuilder,
    required SamRockPairingServicePort pairingService,
    required WalletManifestFacade walletManifest,
    required BtcpayConnectionStore connectionStore,
  }) : _parser = parser,
       _prepareWallets = prepareWallets,
       _payloadBuilder = payloadBuilder,
       _pairingService = pairingService,
       _walletManifest = walletManifest,
       _connectionStore = connectionStore;

  Future<BtcpayConnection> execute({required String pairingUrl}) async {
    final SamRockPairingRequest request;
    try {
      request = _parser.parse(pairingUrl);
    } on SamRockPairingRequestException catch (e) {
      throw BtcpayPairingException.invalidRequest(e.message);
    }

    var submitAttempted = false;
    PrepareBtcpayPairingWalletsResult? preparedWallets;
    try {
      preparedWallets = await _prepareWallets.execute(request: request);
      final Map<String, Object?> payload;
      try {
        payload = _payloadBuilder.build(
          request: request,
          preparedWallets: preparedWallets,
        );
      } on SamRockSetupPayloadException {
        await _rollbackPreparedWalletsBestEffort(preparedWallets);
        rethrow;
      }
      submitAttempted = true;
      final response = await _pairingService.submitSetup(
        request: request,
        payload: payload,
      );
      if (!response.success) {
        await _publishManifestBestEffort(
          'BTCPay pairing failed after descriptor submission and wallet manifest publish failed',
        );
        if (response.serverFailure) {
          throw BtcpayPairingException.generic(response.message);
        }
        throw BtcpayPairingException.rejected(response.message);
      }
    } on BtcpayPairingException {
      rethrow;
    } on SamRockSetupPayloadException catch (e) {
      throw BtcpayPairingException.generic(e.message);
    } catch (e) {
      if (submitAttempted) {
        await _publishManifestBestEffort(
          'BTCPay pairing errored after descriptor submission and wallet manifest publish failed',
        );
      }
      throw BtcpayPairingException.generic(e.toString());
    }

    await _publishManifestBestEffort(
      'BTCPay paired but wallet manifest publish failed',
    );
    final connection = BtcpayConnection.fromPairing(
      request: request,
      preparedWallets: preparedWallets,
      pairedAt: DateTime.now().toUtc(),
    );
    await _connectionStore.saveConnection(connection);
    return connection;
  }

  Future<void> _publishManifestBestEffort(String message) async {
    try {
      await _walletManifest.publishLocalManifest();
    } catch (e, stack) {
      log.warning(message, error: e, trace: stack);
    }
  }

  Future<void> _rollbackPreparedWalletsBestEffort(
    PrepareBtcpayPairingWalletsResult preparedWallets,
  ) async {
    try {
      await _prepareWallets.rollbackCreatedWallets(preparedWallets);
    } catch (e, stack) {
      log.warning(
        'BTCPay pairing failed but created wallet cleanup failed',
        error: e,
        trace: stack,
      );
    }
  }
}
