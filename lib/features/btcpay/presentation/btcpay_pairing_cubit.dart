import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_error.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/preview_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BtcpayPairingCubit extends Cubit<BtcpayPairingState> {
  final CompleteBtcpaySamRockPairingUsecase _completePairing;
  final GetBtcpayConnectionUsecase _getConnection;
  final PreviewBtcpaySamRockPairingUsecase _previewPairing;

  BtcpayPairingCubit({
    required this._completePairing,
    required this._getConnection,
    required this._previewPairing,
  }) : super(const BtcpayPairingState());

  Future<void> load() async {
    if (state.isSubmitting || state.connection != null) return;
    try {
      final connection = await _getConnection.execute();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.idle,
          connection: connection == null ? null : _connectionView(connection),
          clearConnection: connection == null,
        ),
      );
    } on Exception catch (e, stack) {
      log.warning('Failed to load BTCPay connection', error: e, trace: stack);
      if (isClosed) return;
      emit(state.copyWith(status: BtcpayPairingStatus.idle));
    }
  }

  BtcpayPairingPreview? preview(String pairingUrl) {
    try {
      final preview = _previewPairing.execute(pairingUrl);
      return BtcpayPairingPreview(
        serverUrl: preview.serverUrl,
        supportsBitcoinChain: preview.supportsBitcoinChain,
        supportsLiquidChain: preview.supportsLiquidChain,
        supportsLightning: preview.supportsLightning,
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.failure,
          failure: _failureFor(e),
          failureMessage: _failureMessageFor(e),
          clearConnection: true,
          showPairingForm: true,
        ),
      );
      return null;
    }
  }

  void pairNew() {
    if (state.isSubmitting) return;
    emit(
      state.copyWith(
        status: BtcpayPairingStatus.idle,
        clearFailure: true,
        clearFailureMessage: true,
        showPairingForm: true,
      ),
    );
  }

  Future<void> submit(String pairingUrl) async {
    if (state.isSubmitting) return;
    emit(
      state.copyWith(
        status: BtcpayPairingStatus.submitting,
        clearFailure: true,
        clearFailureMessage: true,
        showPairingForm: true,
      ),
    );

    try {
      final connection = await _completePairing.execute(pairingUrl: pairingUrl);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.success,
          connection: _connectionView(connection),
          showPairingForm: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      final connection = await _connectionAfterUncertainFailure(e);
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.failure,
          failure: _failureFor(e),
          failureMessage: _failureMessageFor(e),
          connection: connection == null ? null : _connectionView(connection),
          clearConnection: connection == null,
          showPairingForm: connection == null,
        ),
      );
    }
  }

  BtcpayPairingFailure _failureFor(Object error) {
    return switch (error) {
      BtcpayPairingException(type: BtcpayPairingExceptionType.invalidRequest) =>
        BtcpayPairingFailure.invalidRequest,
      BtcpayPairingException(type: BtcpayPairingExceptionType.rejected) =>
        BtcpayPairingFailure.rejected,
      BtcpayPairingException(type: BtcpayPairingExceptionType.uncertain) =>
        BtcpayPairingFailure.uncertain,
      _ => BtcpayPairingFailure.generic,
    };
  }

  String? _failureMessageFor(Object error) {
    return switch (error) {
      BtcpayPairingException(type: BtcpayPairingExceptionType.rejected) =>
        error.message,
      BtcpayPairingException(type: BtcpayPairingExceptionType.uncertain) =>
        error.message,
      _ => null,
    };
  }

  Future<BtcpayConnection?> _connectionAfterUncertainFailure(
    Object error,
  ) async {
    if (error case BtcpayPairingException(
      type: BtcpayPairingExceptionType.uncertain,
    )) {
      try {
        return _getConnection.execute();
      } on Exception catch (e, stack) {
        log.warning(
          'Failed to load uncertain BTCPay connection',
          error: e,
          trace: stack,
        );
      }
    }
    return null;
  }

  BtcpayConnectionViewModel _connectionView(BtcpayConnection connection) {
    return BtcpayConnectionViewModel(
      serverUrl: connection.serverUrl,
      storeId: connection.storeId,
      rails: [
        if (connection.supportsBitcoinChain) BtcpayPairingRail.bitcoin,
        if (connection.supportsLiquidChain) BtcpayPairingRail.liquid,
        if (connection.supportsLightning) BtcpayPairingRail.lightning,
      ],
      wallets: connection.walletNetworks.map((network) {
        return switch (network) {
          BtcpayWalletNetwork.bitcoin => BtcpayPairingWallet.bitcoin,
          BtcpayWalletNetwork.liquid => BtcpayPairingWallet.liquid,
        };
      }).toList(),
      isUncertain: connection.isUncertain,
      isPaired: connection.isPaired,
      displayDate: connection.pairedAt ?? connection.updatedAt,
    );
  }
}
