import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a paired connection to its server URL only', () async {
    final connection = BtcpayConnection.tryCreate(
      environment: Environment.mainnet,
      serverUrl: 'https://btcpay.example',
      storeId: 'store',
      capabilities: const [SamRockSetupCapability.bitcoinChain],
      walletNetworks: const [BtcpayWalletNetwork.bitcoin],
      status: BtcpayConnectionStatus.paired,
      pairedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    )!;
    final usecase = GetGetPaidBtcpayConnectionUsecase(
      btcpay: BtcpayFacade(connection: () async => Ok(connection)),
    );

    final result = await usecase.execute();

    expect(result, isA<GetPaidProductFound<GetPaidBtcpayConnectionSnapshot>>());
    expect(
      (result as GetPaidProductFound<GetPaidBtcpayConnectionSnapshot>)
          .row
          .serverUrl,
      'https://btcpay.example',
    );
  });

  test('keeps absence and provider failure distinct', () async {
    final absent = GetGetPaidBtcpayConnectionUsecase(
      btcpay: BtcpayFacade(
        connection: () async =>
            const Ok<BtcpayConnection?, BtcpayFailure>(null),
      ),
    );
    final unavailable = GetGetPaidBtcpayConnectionUsecase(
      btcpay: BtcpayFacade(
        connection: () async => const Err(BtcpayStorageFailure()),
      ),
    );

    expect(
      await absent.execute(),
      isA<GetPaidProductAbsent<GetPaidBtcpayConnectionSnapshot>>(),
    );
    expect(
      await unavailable.execute(),
      isA<GetPaidProductUnavailable<GetPaidBtcpayConnectionSnapshot>>(),
    );
  });
}
