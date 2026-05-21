import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/get_paid/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompleteBtcpaySamRockPairingUsecase extends Mock
    implements CompleteBtcpaySamRockPairingUsecase {}

class _MockGetBtcpayConnectionUsecase extends Mock
    implements GetBtcpayConnectionUsecase {}

void main() {
  test('emits success after pairing completes', () async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final getConnection = _MockGetBtcpayConnectionUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenAnswer((_) async => _connection());
    final cubit = BtcpayPairingCubit(
      completePairing: completePairing,
      getConnection: getConnection,
    );
    addTearDown(cubit.close);

    await cubit.submit('https://btcpay.example/plugins/samrock/protocol');

    expect(cubit.state.status, BtcpayPairingStatus.success);
    expect(cubit.state.connection?.serverUrl, 'https://btcpay.example');
    verify(
      () => completePairing.execute(
        pairingUrl: 'https://btcpay.example/plugins/samrock/protocol',
      ),
    ).called(1);
  });

  test('maps invalid pairing request failures', () async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final getConnection = _MockGetBtcpayConnectionUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenThrow(BtcpayPairingException.invalidRequest('invalid'));
    final cubit = BtcpayPairingCubit(
      completePairing: completePairing,
      getConnection: getConnection,
    );
    addTearDown(cubit.close);

    await cubit.submit('invalid');

    expect(cubit.state.status, BtcpayPairingStatus.failure);
    expect(cubit.state.failure, BtcpayPairingFailure.invalidRequest);
    expect(cubit.state.failureMessage, isNull);
  });

  test('maps server rejection failures', () async {
    final completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    final getConnection = _MockGetBtcpayConnectionUsecase();
    when(
      () => completePairing.execute(pairingUrl: any(named: 'pairingUrl')),
    ).thenThrow(BtcpayPairingException.rejected('OTP expired'));
    final cubit = BtcpayPairingCubit(
      completePairing: completePairing,
      getConnection: getConnection,
    );
    addTearDown(cubit.close);

    await cubit.submit('https://btcpay.example/plugins/samrock/protocol');

    expect(cubit.state.status, BtcpayPairingStatus.failure);
    expect(cubit.state.failure, BtcpayPairingFailure.rejected);
    expect(cubit.state.failureMessage, 'OTP expired');
  });
}

BtcpayConnection _connection() {
  return BtcpayConnection(
    serverUrl: 'https://btcpay.example',
    capabilities: const [SamRockSetupCapability.bitcoinChain],
    walletNetworks: const [BtcpayPairingWalletNetwork.bitcoin],
    pairedAt: DateTime.utc(2026, 5, 20, 12),
  );
}
