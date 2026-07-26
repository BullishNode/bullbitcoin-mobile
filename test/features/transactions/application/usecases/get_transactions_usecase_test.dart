import 'package:bb_mobile/core/exchange/domain/entity/order.dart';
import 'package:bb_mobile/core/exchange/domain/repositories/exchange_order_repository.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/label_exchange_orders_usecase.dart';
import 'package:bb_mobile/core/payjoin/domain/entity/payjoin.dart';
import 'package:bb_mobile/core/payjoin/domain/repositories/payjoin_repository.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/swaps/data/repository/boltz_swap_repository.dart';
import 'package:bb_mobile/core/swaps/domain/entity/swap.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_transaction.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_transaction_repository.dart';
import 'package:bb_mobile/features/transactions/application/usecases/get_transactions_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// The incoming amount a wallet reports for a Get Paid split settlement is the
// wallet's own descriptor total, never the whole transaction. That property is
// guaranteed upstream of this usecase, not in our mapping code, so it is not
// re-tested here with a fake chain backend:
//   - Bitcoin: bdk_wallet_datasource.dart computes the net amount from
//     `bdkWallet.sentAndReceived(tx)`, which sums only outputs owned by the
//     wallet descriptor.
//   - Liquid: lwk_wallet_datasource.dart takes the net amount from
//     `tx.balances` (the L-BTC balance delta for this wallet), again scoped to
//     the wallet's descriptor.
// A foreign sibling output paid to Bull Bitcoin's sell deposit in the same
// transaction therefore never inflates this wallet's incoming amount, which is
// exactly why the direction guard below can keep such a receive standalone.

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockWalletTransactionRepository extends Mock
    implements WalletTransactionRepository {}

class _MockBoltzSwapRepository extends Mock implements BoltzSwapRepository {}

class _MockPayjoinRepository extends Mock implements PayjoinRepository {}

class _MockExchangeOrderRepository extends Mock
    implements ExchangeOrderRepository {}

class _MockLabelExchangeOrdersUsecase extends Mock
    implements LabelExchangeOrdersUsecase {}

WalletTransaction _walletTx({
  required String txId,
  WalletTransactionDirection direction = WalletTransactionDirection.incoming,
}) {
  return WalletTransaction(
    walletId: 'w1',
    network: Network.bitcoinMainnet,
    direction: direction,
    status: WalletTransactionStatus.confirmed,
    txId: txId,
    amountSat: 100000,
    feeSat: 0,
    vsize: 110,
    inputs: const [],
    outputs: const [],
    isRbf: false,
  );
}

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

Order _buyOrder({required String txId}) => Order.buy(
  orderId: 'order_buy',
  orderType: OrderType.buy,
  message: OrderMessage(code: 'ok', message: 'ok'),
  orderNumber: 2,
  payinAmount: 50,
  payinCurrency: 'CAD',
  payoutAmount: 0.001,
  payoutCurrency: 'BTC',
  payinMethod: OrderPaymentMethod.eTransfer,
  payoutMethod: OrderPaymentMethod.bitcoin,
  orderStatus: OrderStatus.completed,
  payinStatus: OrderPayinStatus.completed,
  payoutStatus: OrderPayoutStatus.completed,
  confirmationDeadline: DateTime.utc(2026, 7, 1),
  createdAt: DateTime.utc(2026, 7, 1),
  bitcoinTransactionId: txId,
  isTestnet: false,
);

PayjoinReceiver _receiver(PayjoinStatus status) =>
    Payjoin.receiver(
          status: status,
          id: 'pj1',
          isTestnet: false,
          walletId: 'w1',
          pjUri: 'bitcoin:bc1qtest?pj=https://payjo.in',
          createdAt: DateTime(2026),
          expiresAt: DateTime(2026).add(const Duration(minutes: 1)),
          originalTxId: 'original-txid',
        )
        as PayjoinReceiver;

void main() {
  late _MockSettingsRepository settings;
  late _MockWalletTransactionRepository walletTxs;
  late _MockBoltzSwapRepository swaps;
  late _MockPayjoinRepository payjoins;
  late _MockExchangeOrderRepository mainnetOrders;
  late _MockExchangeOrderRepository testnetOrders;
  late _MockLabelExchangeOrdersUsecase labeler;
  late GetTransactionsUsecase usecase;

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    settings = _MockSettingsRepository();
    walletTxs = _MockWalletTransactionRepository();
    swaps = _MockBoltzSwapRepository();
    payjoins = _MockPayjoinRepository();
    mainnetOrders = _MockExchangeOrderRepository();
    testnetOrders = _MockExchangeOrderRepository();
    labeler = _MockLabelExchangeOrdersUsecase();
    usecase = GetTransactionsUsecase(
      settingsRepository: settings,
      walletTransactionRepository: walletTxs,
      boltzSwapRepository: swaps,
      payjoinRepository: payjoins,
      mainnetExchangeOrderRepository: mainnetOrders,
      testnetExchangeOrderRepository: testnetOrders,
      labelExchangeOrdersUsecase: labeler,
    );

    when(() => settings.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
    when(
      () => walletTxs.getWalletTransactions(
        walletId: any(named: 'walletId'),
        sync: any(named: 'sync'),
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async => <WalletTransaction>[]);
    when(
      () => payjoins.getPayjoins(
        walletId: any(named: 'walletId'),
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async => <Payjoin>[]);
    when(
      () => swaps.getAllSwaps(walletId: any(named: 'walletId')),
    ).thenAnswer((_) async => <Swap>[]);
    when(() => mainnetOrders.getOrders()).thenAnswer((_) async => <Order>[]);
    when(() => testnetOrders.getOrders()).thenAnswer((_) async => <Order>[]);
    when(
      () => labeler.execute(walletFundedTxIds: any(named: 'walletFundedTxIds')),
    ).thenAnswer((_) async {});
  });

  void stubWalletTxs(List<WalletTransaction> txs) {
    when(
      () => walletTxs.getWalletTransactions(
        walletId: any(named: 'walletId'),
        sync: any(named: 'sync'),
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async => txs);
  }

  test(
    'hides an aborted Payjoin until its original wallet tx is synced',
    () async {
      when(
        () => payjoins.getPayjoins(
          walletId: any(named: 'walletId'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => [_receiver(PayjoinStatus.aborted)]);

      final transactions = await usecase.execute();

      expect(transactions, isEmpty);
    },
  );

  test('keeps a genuinely pending Payjoin in the transaction list', () async {
    when(
      () => payjoins.getPayjoins(
        walletId: any(named: 'walletId'),
        environment: any(named: 'environment'),
      ),
    ).thenAnswer((_) async => [_receiver(PayjoinStatus.requested)]);

    final transactions = await usecase.execute();

    expect(transactions, hasLength(1));
    expect(transactions.single.payjoin?.status, PayjoinStatus.requested);
  });

  test('sell order + incoming wallet tx with same txid stays split: a plain '
      'receive plus a standalone order row', () async {
    const txid = 'shared_txid';
    stubWalletTxs([
      _walletTx(txId: txid, direction: WalletTransactionDirection.incoming),
    ]);
    when(
      () => mainnetOrders.getOrders(),
    ).thenAnswer((_) async => [_sellOrder(txId: txid)]);

    final result = await usecase.execute();

    expect(result.length, 2);
    final walletRow = result.firstWhere((t) => t.walletTransaction != null);
    expect(walletRow.order, isNull, reason: 'receive is not merged');
    final orderRow = result.firstWhere((t) => t.order != null);
    expect(orderRow.walletTransaction, isNull);
    expect(orderRow.order, isA<SellOrder>());
  });

  test(
    'sell order + outgoing wallet tx with same txid merges into one row',
    () async {
      const txid = 'sell_txid';
      stubWalletTxs([
        _walletTx(txId: txid, direction: WalletTransactionDirection.outgoing),
      ]);
      when(
        () => mainnetOrders.getOrders(),
      ).thenAnswer((_) async => [_sellOrder(txId: txid)]);

      final result = await usecase.execute();

      expect(result.length, 1);
      expect(result.single.walletTransaction, isNotNull);
      expect(result.single.order, isA<SellOrder>());
    },
  );

  test(
    'buy order + incoming wallet tx with same txid merges into one row',
    () async {
      const txid = 'buy_txid';
      stubWalletTxs([
        _walletTx(txId: txid, direction: WalletTransactionDirection.incoming),
      ]);
      when(
        () => mainnetOrders.getOrders(),
      ).thenAnswer((_) async => [_buyOrder(txId: txid)]);

      final result = await usecase.execute();

      expect(result.length, 1);
      expect(result.single.walletTransaction, isNotNull);
      expect(result.single.order, isA<BuyOrder>());
    },
  );

  test(
    'only outgoing wallet txids are passed as wallet-funded to the labeler',
    () async {
      stubWalletTxs([
        _walletTx(txId: 'out', direction: WalletTransactionDirection.outgoing),
        _walletTx(txId: 'in', direction: WalletTransactionDirection.incoming),
      ]);
      // A non-empty order list is required for the labeling pass to run.
      when(
        () => mainnetOrders.getOrders(),
      ).thenAnswer((_) async => [_sellOrder(txId: 'out')]);

      await usecase.execute();

      final captured =
          verify(
                () => labeler.execute(
                  walletFundedTxIds: captureAny(named: 'walletFundedTxIds'),
                ),
              ).captured.single
              as Set<String>;
      expect(captured, contains('out'));
      expect(captured, isNot(contains('in')));
    },
  );
}
