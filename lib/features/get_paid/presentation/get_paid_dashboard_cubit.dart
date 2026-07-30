import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_btcpay_connection_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/get_get_paid_fiat_settlement_summary_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_invoices_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/load_get_paid_product_overview_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Assembles the Get Paid hub snapshot from Get Paid's own use cases, each of
/// which wraps one foreign public boundary. It reads each product's current
/// status to render a chip + subtitle; it never touches balances, protocol
/// internals or money logic. Once a wallet-owned nym exists, it also invokes the
/// idempotent automatic-fallback setup use-case.
///
/// The Donation Page and Point of Sale rows are keyed by the wallet nym, which
/// is resolved from the Lightning Address registration — so those two are only
/// probed once a nym exists (mirroring how the product screens resolve their
/// own identity). The invoices boundary contributes only wallet readiness and
/// a read-only automatic-fallback attention count.
class GetPaidDashboardCubit extends Cubit<GetPaidDashboardState> {
  final LoadGetPaidProductOverviewUsecase _loadProductOverview;
  final GetGetPaidBtcpayConnectionUsecase _getBtcpayConnection;
  final LoadGetPaidInvoicesOverviewUsecase _loadInvoicesOverview;

  /// The mainnet-only fiat-settlement summary read for the slots. Required: the
  /// use case itself decides that settlement does not apply (non-mainnet), so
  /// presentation never has to hold a dependency that may be absent.
  final GetGetPaidFiatSettlementSummaryUsecase _fiatSettlementSummary;
  int _refreshGeneration = 0;

  GetPaidDashboardCubit({
    required this._loadProductOverview,
    required this._getBtcpayConnection,
    required this._loadInvoicesOverview,
    required this._fiatSettlementSummary,
  }) : super(const GetPaidDashboardState());

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        lightningStatus: GetPaidProductStatus.loading,
        paymentPageStatus: GetPaidProductStatus.loading,
        posStatus: GetPaidProductStatus.loading,
        invoicesStatus: GetPaidDashboardCardStatus.loading,
        invoicesUnavailable: false,
        btcpayStatus: GetPaidDashboardCardStatus.loading,
        clearBtcpayConnection: true,
        btcpayUnavailable: false,
        // Settlement is server-read-only: drop any prior summary so a stale
        // badge is never shown while the fresh read is in flight.
        clearFiatSettlement: true,
        fiatSettlementUnavailable: false,
        // Wallet self-heal warnings are recomputed each refresh.
        lightningWalletWarning: false,
        paymentPageWalletWarning: false,
        posWalletWarning: false,
      ),
    );

    var failed = false;
    // The use cases log the failure detail; this only records that the snapshot
    // is incomplete so the hub can show its retry banner.
    void recordFailure(String message) {
      failed = true;
      log.warning(message);
    }

    final invoicesFuture = () async {
      final overview = await _loadInvoicesOverview.execute();
      if (_isStale(generation)) return;
      switch (overview) {
        case GetPaidInvoicesOverviewKnown(
          :final walletReady,
          :final fallbackAttentionCount,
        ):
          emit(
            state.copyWith(
              invoicesWalletReady: walletReady,
              fallbackAttentionCount: fallbackAttentionCount,
              clearFallbackAttention: fallbackAttentionCount == null,
              invoicesUnavailable: false,
              invoicesStatus: GetPaidDashboardCardStatus.loaded,
            ),
          );
        case GetPaidInvoicesOverviewUnavailable():
          recordFailure('Get Paid dashboard could not load invoice readiness');
          emit(
            state.copyWith(
              invoicesWalletReady: false,
              clearFallbackAttention: true,
              invoicesUnavailable: true,
              invoicesStatus: GetPaidDashboardCardStatus.loaded,
            ),
          );
      }
    }();

    final btcpayFuture = () async {
      final probe = await _getBtcpayConnection.execute();
      if (_isStale(generation)) return;
      switch (probe) {
        case GetPaidProductFound(:final row):
          emit(
            state.copyWith(
              btcpayConnection: row,
              btcpayStatus: GetPaidDashboardCardStatus.loaded,
              btcpayUnavailable: false,
            ),
          );
        case GetPaidProductAbsent():
          emit(
            state.copyWith(
              clearBtcpayConnection: true,
              btcpayStatus: GetPaidDashboardCardStatus.loaded,
              btcpayUnavailable: false,
            ),
          );
        case GetPaidProductUnavailable():
          recordFailure(
            'Get Paid dashboard could not load the BTCPay connection',
          );
          emit(
            state.copyWith(
              clearBtcpayConnection: true,
              btcpayStatus: GetPaidDashboardCardStatus.loaded,
              btcpayUnavailable: true,
            ),
          );
      }
    }();

    final productOverviewFuture = _applyProductOverview(
      generation,
      recordFailure,
    );

    // Fiat-settlement badges: mainnet-only, server-read-only truth. A confirmed
    // read populates the per-product config; a mainnet read FAILURE clears the
    // map and flags it unavailable so active slots show an honest "unavailable"
    // badge (never a stale or guessed Bitcoin-only). Never marks the refresh as
    // failed (settlement presentation is independent of the rest of the hub).
    final fiatSettlementFuture = () async {
      final summary = await _fiatSettlementSummary.execute();
      // A null summary means settlement does not apply — no badge at all.
      if (summary == null || _isStale(generation)) return;
      emit(
        summary.isUnavailable
            ? state.copyWith(
                clearFiatSettlement: true,
                fiatSettlementUnavailable: true,
              )
            : state.copyWith(
                fiatSettlement: summary.configs,
                fiatSettlementUnavailable: false,
              ),
      );
    }();

    await Future.wait([
      invoicesFuture,
      btcpayFuture,
      productOverviewFuture,
      fiatSettlementFuture,
    ]);
    if (_isStale(generation)) return;
    emit(
      state.copyWith(
        isLoading: false,
        error: failed ? 'Something went wrong. Please try again.' : null,
        clearError: !failed,
      ),
    );
  }

  Future<void> _applyProductOverview(
    int generation,
    void Function(String message) recordFailure,
  ) async {
    await for (final event in _loadProductOverview.execute(
      isCurrent: () => !_isStale(generation),
    )) {
      if (_isStale(generation)) return;
      switch (event) {
        case GetPaidRegistrationUnavailable():
          recordFailure('Get Paid dashboard Lightning Address lookup failed');
          emit(
            state.copyWith(
              lightningStatus: GetPaidProductStatus.unavailable,
              paymentPageStatus: GetPaidProductStatus.unavailable,
              posStatus: GetPaidProductStatus.unavailable,
            ),
          );
        case GetPaidRegistrationResolved(:final registration):
          final nym = registration.nym;
          final address = registration.address;
          emit(
            state.copyWith(
              lightningAddress: address,
              clearLightningAddress: address == null,
              lightningActive: registration.active,
              nym: nym,
              clearNym: nym == null,
              lightningStatus: nym == null
                  ? GetPaidProductStatus.absent
                  : GetPaidProductStatus.active,
            ),
          );
        case GetPaidPaymentPageResolved(:final probe):
          _applyPaymentPageProbe(probe, recordFailure);
        case GetPaidPosResolved(:final probe):
          _applyPosProbe(probe, recordFailure);
        case GetPaidProductWalletResolved(:final product, :final outcome):
          _applyWalletOutcome(product, outcome);
        case GetPaidAutomaticFallbackResolved(:final ready):
          if (!ready) {
            recordFailure('Get Paid automatic fallback setup failed');
          }
        case GetPaidProductOverviewUnavailable():
          recordFailure('Get Paid product overview failed unexpectedly');
          emit(
            state.copyWith(
              lightningStatus: GetPaidProductStatus.unavailable,
              paymentPageStatus: GetPaidProductStatus.unavailable,
              posStatus: GetPaidProductStatus.unavailable,
            ),
          );
      }
    }
  }

  void _applyPaymentPageProbe(
    GetPaidProductProbe<GetPaidPaymentPageSnapshot> probe,
    void Function(String message) recordFailure,
  ) {
    switch (probe) {
      case GetPaidProductAbsent():
        emit(
          state.copyWith(
            clearPaymentPage: true,
            paymentPageStatus: GetPaidProductStatus.absent,
          ),
        );
      case GetPaidProductUnavailable():
        recordFailure('Get Paid dashboard Donation Page lookup failed');
        emit(
          state.copyWith(paymentPageStatus: GetPaidProductStatus.unavailable),
        );
      case GetPaidProductFound(:final row):
        emit(
          state.copyWith(
            paymentPage: row,
            paymentPageStatus: row.isArchived
                ? GetPaidProductStatus.archived
                : GetPaidProductStatus.active,
          ),
        );
    }
  }

  void _applyPosProbe(
    GetPaidProductProbe<GetPaidPosTerminalSnapshot> probe,
    void Function(String message) recordFailure,
  ) {
    switch (probe) {
      case GetPaidProductAbsent():
        emit(
          state.copyWith(
            clearPos: true,
            posStatus: GetPaidProductStatus.absent,
          ),
        );
      case GetPaidProductUnavailable():
        recordFailure('Get Paid dashboard Point of Sale lookup failed');
        emit(state.copyWith(posStatus: GetPaidProductStatus.unavailable));
      case GetPaidProductFound(:final row):
        emit(
          state.copyWith(
            posTerminal: row,
            posStatus: row.isArchived
                ? GetPaidProductStatus.archived
                : GetPaidProductStatus.active,
          ),
        );
    }
  }

  void _applyWalletOutcome(
    GetPaidWalletBackedProduct product,
    GetPaidProductWalletOutcome outcome,
  ) {
    final warning = outcome == GetPaidProductWalletOutcome.failed;
    emit(switch (product) {
      GetPaidWalletBackedProduct.lightningAddress => state.copyWith(
        lightningWalletWarning: warning,
      ),
      GetPaidWalletBackedProduct.paymentPage => state.copyWith(
        paymentPageWalletWarning: warning,
      ),
      GetPaidWalletBackedProduct.pos => state.copyWith(
        posWalletWarning: warning,
      ),
    });
  }

  bool _isStale(int generation) {
    return isClosed || generation != _refreshGeneration;
  }
}
