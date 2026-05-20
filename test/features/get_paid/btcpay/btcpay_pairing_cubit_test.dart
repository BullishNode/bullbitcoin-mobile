import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompleteBtcpaySamRockPairingUsecase extends Mock
    implements CompleteBtcpaySamRockPairingUsecase {}

void main() {
  test('emits success after pairing completes', () async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) async {});
    final cubit = BtcpayPairingCubit(completePairing: completePairing);
    addTearDown(cubit.close);

    await cubit.submit('https://btcpay.example/plugins/samrock/protocol');

    expect(cubit.state.status, BtcpayPairingStatus.success);
    verify(
      () => completePairing.execute(
        pairingUrl: 'https://btcpay.example/plugins/samrock/protocol',
      ),
    ).called(1);
  });

  test('maps invalid pairing request failures', () async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenThrow(BtcpayPairingException.invalidRequest('invalid'));
    final cubit = BtcpayPairingCubit(completePairing: completePairing);
    addTearDown(cubit.close);

    await cubit.submit('invalid');

    expect(cubit.state.status, BtcpayPairingStatus.failure);
    expect(cubit.state.failure, BtcpayPairingFailure.invalidRequest);
    expect(cubit.state.failureMessage, isNull);
  });

  test('maps server rejection failures', () async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenThrow(BtcpayPairingException.rejected('OTP expired'));
    final cubit = BtcpayPairingCubit(completePairing: completePairing);
    addTearDown(cubit.close);

    await cubit.submit('https://btcpay.example/plugins/samrock/protocol');

    expect(cubit.state.status, BtcpayPairingStatus.failure);
    expect(cubit.state.failure, BtcpayPairingFailure.rejected);
    expect(cubit.state.failureMessage, 'OTP expired');
  });
}
