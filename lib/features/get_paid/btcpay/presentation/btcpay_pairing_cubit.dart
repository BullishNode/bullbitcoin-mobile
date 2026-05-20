import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BtcpayPairingCubit extends Cubit<BtcpayPairingState> {
  final CompleteBtcpaySamRockPairingUsecase _completePairing;

  BtcpayPairingCubit({
    required CompleteBtcpaySamRockPairingUsecase completePairing,
  }) : _completePairing = completePairing,
       super(const BtcpayPairingState());

  Future<void> submit(String pairingUrl) async {
    if (state.isSubmitting) return;
    emit(const BtcpayPairingState(status: BtcpayPairingStatus.submitting));

    try {
      await _completePairing.execute(pairingUrl: pairingUrl);
      if (isClosed) return;
      emit(const BtcpayPairingState(status: BtcpayPairingStatus.success));
    } catch (e) {
      if (isClosed) return;
      emit(
        BtcpayPairingState(
          status: BtcpayPairingStatus.failure,
          failure: _failureFor(e),
          failureMessage: _failureMessageFor(e),
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
