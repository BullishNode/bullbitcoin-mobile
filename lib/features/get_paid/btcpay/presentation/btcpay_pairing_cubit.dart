import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BtcpayPairingCubit extends Cubit<BtcpayPairingState> {
  final CompleteBtcpaySamRockPairingUsecase _completePairing;
  final GetBtcpayConnectionUsecase _getConnection;

  BtcpayPairingCubit({
    required CompleteBtcpaySamRockPairingUsecase completePairing,
    required GetBtcpayConnectionUsecase getConnection,
  }) : _completePairing = completePairing,
       _getConnection = getConnection,
       super(const BtcpayPairingState());

  Future<void> load() async {
    if (state.isSubmitting || state.connection != null) return;
    try {
      final connection = await _getConnection.execute();
      if (isClosed || connection == null) return;
      emit(state.copyWith(connection: connection));
    } on Exception catch (e, stack) {
      log.warning('Failed to load BTCPay connection', error: e, trace: stack);
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
          connection: connection,
          showPairingForm: false,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BtcpayPairingStatus.failure,
          failure: _failureFor(e),
          failureMessage: _failureMessageFor(e),
          showPairingForm: true,
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
      _ => BtcpayPairingFailure.generic,
    };
  }

  String? _failureMessageFor(Object error) {
    return switch (error) {
      BtcpayPairingException(type: BtcpayPairingExceptionType.rejected) =>
        error.message,
      _ => null,
    };
  }
}
