import 'package:bb_mobile/core/exchange/domain/entity/order.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/label_exchange_orders_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/list_all_orders_usecase.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLabelsFacade extends Mock implements LabelsFacade {}

class _MockListAllOrdersUsecase extends Mock implements ListAllOrdersUsecase {}

class _FakeLabel extends Fake implements Label {}

class _FakeNewLabel extends Fake implements NewLabel {}

Order _sellOrder({required String txId}) => Order.sell(
  orderId: 'order_sell',
  orderType: OrderType.sell,
  message: OrderMessage(code: 'ok', message: 'ok'),
  orderNumber: 1,
  payinAmount: 0.001,
  payinCurrency: 'BTC',
  payoutAmount: 50,
  payoutCurrency: 'CAD',
  payinMethod: OrderPaymentMethod.liquid,
  payoutMethod: OrderPaymentMethod.eTransfer,
  orderStatus: OrderStatus.completed,
  payinStatus: OrderPayinStatus.completed,
  payoutStatus: OrderPayoutStatus.completed,
  confirmationDeadline: DateTime.utc(2026, 7, 1),
  createdAt: DateTime.utc(2026, 7, 1),
  bitcoinTransactionId: txId,
  isTestnet: false,
);

void main() {
  late _MockLabelsFacade facade;
  late _MockListAllOrdersUsecase listOrders;
  late LabelExchangeOrdersUsecase usecase;

  setUpAll(() {
    registerFallbackValue(_FakeNewLabel());
  });

  setUp(() {
    facade = _MockLabelsFacade();
    listOrders = _MockListAllOrdersUsecase();
    usecase = LabelExchangeOrdersUsecase(
      labelsFacade: facade,
      listAllOrdersUsecase: listOrders,
    );
    // No pre-existing exchange labels, so the pass runs.
    when(() => facade.fetchAll()).thenAnswer((_) async => <Label>[]);
    when(() => facade.store(any())).thenAnswer(
      (_) async => Ok<Label, LabelFailure>(_FakeLabel()),
    );
  });

  test('a sell tx not funded by the wallet is not stamped "Sell"', () async {
    when(
      () => listOrders.execute(),
    ).thenAnswer((_) async => [_sellOrder(txId: 'foreign_txid')]);

    await usecase.execute(walletFundedTxIds: <String>{});

    verifyNever(() => facade.store(any()));
  });

  test('a sell tx the wallet funded is stamped "Sell"', () async {
    when(
      () => listOrders.execute(),
    ).thenAnswer((_) async => [_sellOrder(txId: 'wallet_txid')]);

    await usecase.execute(walletFundedTxIds: <String>{'wallet_txid'});

    final stored = verify(() => facade.store(captureAny())).captured;
    expect(stored, hasLength(1));
    final label = stored.single as NewLabel;
    expect(label.type, LabelType.transaction);
    expect(label.reference, 'wallet_txid');
    expect(label.label, LabelSystem.exchangeSell.label);
  });
}
