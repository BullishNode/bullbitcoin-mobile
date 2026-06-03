import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_error.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/get_btcpay_wallet_behaviors_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/preview_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/presentation/btcpay_pairing_cubit.dart';
import 'package:bb_mobile/features/btcpay/presentation/btcpay_pairing_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCompleteBtcpaySamRockPairingUsecase extends Mock
    implements CompleteBtcpaySamRockPairingUsecase {}

class _MockGetBtcpayConnectionUsecase extends Mock
    implements GetBtcpayConnectionUsecase {}

class _MockPreviewBtcpaySamRockPairingUsecase extends Mock
    implements PreviewBtcpaySamRockPairingUsecase {}

class _MockGetBtcpayWalletBehaviorsUsecase extends Mock
    implements GetBtcpayWalletBehaviorsUsecase {}

class _MockUpdateWalletBehaviorUsecase extends Mock
    implements UpdateWalletBehaviorUsecase {}

void main() {
  const pairingUrl =
      'https://btcpay.example.com/plugins/store123/samrock/protocol?otp=123&setup=btc';

  late _MockCompleteBtcpaySamRockPairingUsecase completePairing;
  late _MockGetBtcpayConnectionUsecase getConnection;
  late _MockGetBtcpayWalletBehaviorsUsecase getWalletBehaviors;
  late _MockPreviewBtcpaySamRockPairingUsecase previewPairing;
  late _MockUpdateWalletBehaviorUsecase updateWalletBehavior;
  late BtcpayPairingCubit cubit;

  setUpAll(() {
    registerFallbackValue(
      BtcpayConnection(
        environment: Environment.mainnet,
        serverUrl: 'https://btcpay.example.com',
        storeId: 'store123',
        capabilities: const [],
        walletNetworks: const [BtcpayWalletNetwork.bitcoin],
        status: BtcpayConnectionStatus.uncertain,
        pairedAt: null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  });

  setUp(() {
    completePairing = _MockCompleteBtcpaySamRockPairingUsecase();
    getConnection = _MockGetBtcpayConnectionUsecase();
    getWalletBehaviors = _MockGetBtcpayWalletBehaviorsUsecase();
    previewPairing = _MockPreviewBtcpaySamRockPairingUsecase();
    updateWalletBehavior = _MockUpdateWalletBehaviorUsecase();
    when(
      () => getWalletBehaviors.execute(connection: any(named: 'connection')),
    ).thenAnswer((_) async => const []);
    cubit = BtcpayPairingCubit(
      completePairing: completePairing,
      getConnection: getConnection,
      getWalletBehaviors: getWalletBehaviors,
      previewPairing: previewPairing,
      updateWalletBehavior: updateWalletBehavior,
    );
  });

  tearDown(() => cubit.close());

  BtcpayConnection connection() {
    return BtcpayConnection(
      environment: Environment.mainnet,
      serverUrl: 'https://btcpay.example.com',
      storeId: 'store123',
      capabilities: const [SamRockSetupCapability.bitcoinChain],
      walletNetworks: const [BtcpayWalletNetwork.bitcoin],
      status: BtcpayConnectionStatus.paired,
      pairedAt: DateTime.utc(2026, 5, 23),
      updatedAt: DateTime.utc(2026, 5, 23),
    );
  }

  test('submit success shows the new connection', () async {
    when(
      () => completePairing.execute(pairingUrl: pairingUrl),
    ).thenAnswer((_) async => connection());

    await cubit.submit(pairingUrl);

    expect(cubit.state.isSuccess, isTrue);
    expect(cubit.state.connection, isNotNull);
    expect(cubit.state.showPairingForm, isFalse);
  });

  test('rejected failure keeps the stored connection visible', () async {
    when(
      () => completePairing.execute(pairingUrl: pairingUrl),
    ).thenThrow(BtcpayPairingException.rejected('nope'));
    when(() => getConnection.execute()).thenAnswer((_) async => connection());

    await cubit.submit(pairingUrl);

    expect(cubit.state.isFailure, isTrue);
    expect(cubit.state.failure, BtcpayPairingFailure.rejected);
    expect(cubit.state.connection, isNotNull);
    expect(cubit.state.connection!.storeId, 'store123');
    expect(cubit.state.showPairingForm, isFalse);
  });

  test('invalid request failure keeps the stored connection visible', () async {
    when(
      () => completePairing.execute(pairingUrl: pairingUrl),
    ).thenThrow(BtcpayPairingException.invalidRequest());
    when(() => getConnection.execute()).thenAnswer((_) async => connection());

    await cubit.submit(pairingUrl);

    expect(cubit.state.isFailure, isTrue);
    expect(cubit.state.failure, BtcpayPairingFailure.invalidRequest);
    expect(cubit.state.connection, isNotNull);
    expect(cubit.state.showPairingForm, isFalse);
  });

  test('uncertain failure reloads the stored connection', () async {
    when(
      () => completePairing.execute(pairingUrl: pairingUrl),
    ).thenThrow(BtcpayPairingException.uncertain());
    when(() => getConnection.execute()).thenAnswer(
      (_) async =>
          connection().copyWith(status: BtcpayConnectionStatus.uncertain),
    );

    await cubit.submit(pairingUrl);

    expect(cubit.state.isFailure, isTrue);
    expect(cubit.state.failure, BtcpayPairingFailure.uncertain);
    expect(cubit.state.connection, isNotNull);
    expect(cubit.state.connection!.isUncertain, isTrue);
  });

  test('failure without a stored connection returns to the form', () async {
    when(
      () => completePairing.execute(pairingUrl: pairingUrl),
    ).thenThrow(BtcpayPairingException.generic());
    when(() => getConnection.execute()).thenAnswer((_) async => null);

    await cubit.submit(pairingUrl);

    expect(cubit.state.isFailure, isTrue);
    expect(cubit.state.failure, BtcpayPairingFailure.generic);
    expect(cubit.state.connection, isNull);
    expect(cubit.state.showPairingForm, isTrue);
  });

  test('failure still surfaces when the stored connection reload throws', () async {
    when(
      () => completePairing.execute(pairingUrl: pairingUrl),
    ).thenThrow(BtcpayPairingException.rejected());
    when(() => getConnection.execute()).thenThrow(Exception('storage down'));

    await cubit.submit(pairingUrl);

    expect(cubit.state.isFailure, isTrue);
    expect(cubit.state.failure, BtcpayPairingFailure.rejected);
    expect(cubit.state.connection, isNull);
    expect(cubit.state.showPairingForm, isTrue);
  });
}
