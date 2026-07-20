import 'package:bb_mobile/features/fiat_settlement/domain/usecases/is_fiat_settlement_available_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_routes.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Offers the fiat-settlement chooser immediately after a Get Paid product's
/// activation succeeds, by pushing the shared editor in its "activated" variant
/// (a success header above the "How do you want to receive the funds?" chooser,
/// with Bitcoin shown as the currently-active choice).
///
/// Gated identically to [FiatSettlementEntryTile]: locator-only reads and only
/// on mainnet. Fiat is an offer, never a gate — the product is already live
/// Bitcoin-only before this is called, so dismissing or choosing Bitcoin sends
/// nothing.
Future<void> offerFiatSettlementAfterActivation(
  BuildContext context,
  FiatSettlementProduct product,
) async {
  if (!await locator<IsFiatSettlementAvailableUsecase>().execute()) return;
  if (!context.mounted) return;
  await context.pushNamed(
    FiatSettlementRoute.fiatSettlementEditor.name,
    pathParameters: {'product': product.pathId},
    queryParameters: {'activated': '1'},
  );
}
