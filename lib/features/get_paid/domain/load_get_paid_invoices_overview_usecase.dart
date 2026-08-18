import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_fallback_attention_usecase.dart';

sealed class GetPaidInvoicesOverview {
  const GetPaidInvoicesOverview();
}

final class GetPaidInvoicesOverviewKnown extends GetPaidInvoicesOverview {
  final bool walletReady;
  final int? fallbackAttentionCount;

  const GetPaidInvoicesOverviewKnown({
    required this.walletReady,
    required this.fallbackAttentionCount,
  });
}

final class GetPaidInvoicesOverviewUnavailable extends GetPaidInvoicesOverview {
  const GetPaidInvoicesOverviewUnavailable();
}

/// Resolves the Invoices card without allowing a failed wallet/supervision
/// read to masquerade as "not configured" or "no attention required".
class LoadGetPaidInvoicesOverviewUsecase {
  final GetWalletsUsecase _getWallets;
  final GetPaidFallbackAttentionUsecase _fallbackAttention;

  const LoadGetPaidInvoicesOverviewUsecase({
    required this._getWallets,
    required this._fallbackAttention,
  });

  Future<GetPaidInvoicesOverview> execute() async {
    try {
      final wallets = await _getWallets.execute(onlyDefaults: true);
      if (wallets.isEmpty) {
        return const GetPaidInvoicesOverviewKnown(
          walletReady: false,
          fallbackAttentionCount: null,
        );
      }
      return switch (await _fallbackAttention.execute()) {
        GetPaidFallbackAttentionKnown(:final count) =>
          GetPaidInvoicesOverviewKnown(
            walletReady: true,
            fallbackAttentionCount: count,
          ),
        GetPaidFallbackAttentionUnavailable() =>
          const GetPaidInvoicesOverviewUnavailable(),
      };
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid invoices overview lookup failed',
        error: error,
        trace: trace,
      );
      return const GetPaidInvoicesOverviewUnavailable();
    }
  }
}
