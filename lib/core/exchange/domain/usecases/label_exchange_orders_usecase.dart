import 'package:bb_mobile/core/exchange/domain/entity/order.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/list_all_orders_usecase.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';

class LabelExchangeOrdersUsecase {
  final LabelsFacade _labelsFacade;
  final ListAllOrdersUsecase _listAllOrdersUsecase;

  LabelExchangeOrdersUsecase({
    required this._labelsFacade,
    required this._listAllOrdersUsecase,
  });

  /// [walletFundedTxIds] holds the txids of OUTGOING wallet transactions. A
  /// non-buy order's payin can be funded by any source, so its transaction is
  /// only this wallet's sell when the wallet actually funded it. The "Sell" tx
  /// label is therefore stamped only for a txid in this set — otherwise the
  /// wallet merely received a sibling output of a transaction it did not fund
  /// (e.g. a Get Paid mixed settlement) and must not be labelled a sell.
  Future<void> execute({required Set<String> walletFundedTxIds}) async {
    try {
      final hasExchangeLabels = await _hasExistingExchangeSystemLabels();
      if (hasExchangeLabels) return; // orders likely already labeled

      final orders = await _listAllOrdersUsecase.execute();
      if (orders.isEmpty) return; // no orders to label

      log.config('$LabelExchangeOrdersUsecase is labeling exchange orders');

      final labels = <NewLabel>[];
      for (final order in orders) {
        try {
          final isBuyOrder = order is BuyOrder;
          final systemLabel = isBuyOrder
              ? LabelSystem.exchangeBuy.label
              : LabelSystem.exchangeSell.label;

          if (isBuyOrder && order.toAddress != null) {
            final label = NewLabel.addr(
              address: order.toAddress!,
              label: systemLabel,
              origin: null,
            );
            labels.add(label);
          }

          if (order.transactionId != null &&
              (isBuyOrder || walletFundedTxIds.contains(order.transactionId))) {
            final label = NewLabel.tx(
              transactionId: order.transactionId!,
              label: systemLabel,
              origin: null,
            );
            labels.add(label);
          }
        } catch (e) {
          log.warning('$LabelExchangeOrdersUsecase order ${order.orderId}: $e');
        }
      }

      for (final label in labels) {
        await _labelsFacade.store(label);
      }

      log.fine(
        '$LabelExchangeOrdersUsecase labeled ${orders.length} exchange orders',
      );
    } catch (e) {
      log.severe(error: e, trace: StackTrace.current);
    }
  }

  Future<bool> _hasExistingExchangeSystemLabels() async {
    try {
      final allLabels = await _labelsFacade.fetchAll();
      return allLabels.any(
        (label) =>
            LabelSystem.isSystemLabel(label.label) &&
            LabelSystem.fromLabel(label.label).isExchangeRelated(),
      );
    } catch (e) {
      log.warning('$LabelExchangeOrdersUsecase: $e');
      return false;
    }
  }
}
