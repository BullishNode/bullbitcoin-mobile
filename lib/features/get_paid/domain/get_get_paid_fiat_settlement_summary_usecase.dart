import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';

/// The hub's read-only fiat-settlement summary: either a server-confirmed
/// configuration for every product, or [unavailable].
///
/// There is no third "assume Bitcoin-only" state — a failed read must render as
/// unavailable, never as a guessed settlement split.
class GetPaidFiatSettlementSummary {
  /// Server-confirmed configuration per product. Empty when [isUnavailable].
  final Map<GetPaidDashboardSettlementProduct, GetPaidDashboardSettlementConfig>
  configs;

  /// True when a mainnet read was attempted and failed.
  final bool isUnavailable;

  const GetPaidFiatSettlementSummary.confirmed(this.configs)
    : isUnavailable = false;

  const GetPaidFiatSettlementSummary.unavailable()
    : configs = const {},
      isUnavailable = true;
}

/// Get Paid's narrow wrapper over the fiat-settlement boundary for the hub
/// badges. It owns the mainnet-only gate and the per-product projection, and
/// keeps the settlement failure family behind the boundary.
///
/// Returns null when settlement does not apply (non-mainnet), which leaves the
/// slots without any settlement badge at all.
class GetGetPaidFiatSettlementSummaryUsecase {
  final FiatSettlementFacade _fiatSettlement;
  final GetSettingsUsecase _getSettings;

  const GetGetPaidFiatSettlementSummaryUsecase({
    required this._fiatSettlement,
    required this._getSettings,
  });

  Future<GetPaidFiatSettlementSummary?> execute() async {
    try {
      final settings = await _getSettings.execute();
      if (settings.environment != Environment.mainnet) return null;
      return switch (await _fiatSettlement.configuration()) {
        Ok(:final value) => GetPaidFiatSettlementSummary.confirmed({
          for (final product in GetPaidDashboardSettlementProduct.values)
            product: _mapConfig(value.configFor(_foreignProduct(product))),
        }),
        Err(:final failure) => _reportUnavailable(failure),
      };
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid fiat-settlement summary lookup failed',
        error: error,
        trace: trace,
      );
      return const GetPaidFiatSettlementSummary.unavailable();
    }
  }

  GetPaidFiatSettlementSummary _reportUnavailable(Object failure) {
    log.warning(
      'Get Paid could not load the fiat-settlement summary',
      error: failure,
    );
    return const GetPaidFiatSettlementSummary.unavailable();
  }

  FiatSettlementProduct _foreignProduct(
    GetPaidDashboardSettlementProduct product,
  ) => switch (product) {
    GetPaidDashboardSettlementProduct.lightningAddress =>
      FiatSettlementProduct.lightningAddress,
    GetPaidDashboardSettlementProduct.paymentPage =>
      FiatSettlementProduct.paymentPage,
    GetPaidDashboardSettlementProduct.pos => FiatSettlementProduct.pos,
  };

  GetPaidDashboardSettlementConfig _mapConfig(
    FiatSettlementProductConfig config,
  ) => GetPaidDashboardSettlementConfig(
    fiatPercentage: config.fiatPercentage,
    currencyCode: config.currency?.code,
  );
}
