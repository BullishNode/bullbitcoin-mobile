import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/ensure_get_paid_automatic_fallback_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_fallback_attention_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Assembles the Get Paid hub snapshot from the public facades only. It reads
/// each product's current status to render a chip + subtitle; it never touches
/// balances, protocol internals or money logic. Once a wallet-owned nym exists,
/// it also invokes the idempotent automatic-fallback setup use-case.
///
/// The Donation Page and Point of Sale rows are keyed by the wallet nym, which
/// is resolved from the Lightning Address registration — so those two are only
/// probed once a nym exists (mirroring how the product screens resolve their
/// own identity). The invoices boundary contributes only wallet readiness and
/// a read-only automatic-fallback attention count.
class GetPaidDashboardCubit extends Cubit<GetPaidDashboardState> {
  static const _nymNotFoundCode = 'NymNotFound';

  final LightningAddressFacade _lightningAddress;
  final PaymentPageFacade _paymentPage;
  final PosFacade _pos;
  final BtcpayFacade _btcpay;
  final GetWalletsUsecase _getWallets;
  final EnsureGetPaidAutomaticFallbackUsecase _ensureAutomaticFallback;
  final EnsureGetPaidProductWalletUsecase _ensureProductWallet;
  final GetPaidFallbackAttentionUsecase _fallbackAttention;

  /// Optional, mainnet-only fiat-settlement summaries for the slots. Both are
  /// null in isolated tests / environments where fiat settlement is not wired,
  /// in which case no settlement summary is shown.
  final FiatSettlementFacade? _fiatSettlement;
  final GetSettingsUsecase? _getSettings;
  int _refreshGeneration = 0;

  GetPaidDashboardCubit({
    required this._lightningAddress,
    required this._paymentPage,
    required this._pos,
    required this._btcpay,
    required this._getWallets,
    required this._ensureAutomaticFallback,
    required this._ensureProductWallet,
    required this._fallbackAttention,
    this._fiatSettlement,
    this._getSettings,
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
        btcpayStatus: GetPaidDashboardCardStatus.loading,
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
    void recordFailure(String message, {Object? error, StackTrace? trace}) {
      failed = true;
      log.warning(message, error: error, trace: trace);
    }

    final invoicesFuture = () async {
      final ready = await _hasDefaultWallet();
      int? fallbackAttentionCount;
      if (ready) {
        try {
          fallbackAttentionCount = await _fallbackAttention.execute();
        } on Exception catch (error, trace) {
          log.warning(
            'Get Paid fallback attention lookup failed unexpectedly',
            error: error,
            trace: trace,
          );
        }
      }
      if (_isStale(generation)) return;
      emit(
        state.copyWith(
          invoicesWalletReady: ready,
          fallbackAttentionCount: fallbackAttentionCount,
          clearFallbackAttention: fallbackAttentionCount == null,
          invoicesStatus: GetPaidDashboardCardStatus.loaded,
        ),
      );
    }();

    final btcpayFuture = () async {
      try {
        final result = await _btcpay.connection();
        if (_isStale(generation)) return;
        switch (result) {
          case Ok(:final value):
            emit(
              state.copyWith(
                btcpayConnection: value,
                clearBtcpayConnection: value == null,
                btcpayStatus: GetPaidDashboardCardStatus.loaded,
              ),
            );
          case Err(:final failure):
            recordFailure(
              'Get Paid dashboard could not load the BTCPay connection',
              error: failure.runtimeType,
            );
            emit(
              state.copyWith(btcpayStatus: GetPaidDashboardCardStatus.loaded),
            );
        }
      } on Exception catch (error, trace) {
        if (_isStale(generation)) return;
        recordFailure(
          'Get Paid dashboard BTCPay lookup failed',
          error: error,
          trace: trace,
        );
        emit(state.copyWith(btcpayStatus: GetPaidDashboardCardStatus.loaded));
      }
    }();

    final lightningAndSurfacesFuture = () async {
      LightningAddressStatus registration;
      try {
        registration = await _lightningAddress.lookupWalletOwnedRegistration();
      } on LightningAddressException catch (error, trace) {
        if (error.code == _nymNotFoundCode) {
          registration = const LightningAddressStatus(nym: '', active: false);
        } else {
          if (_isStale(generation)) return;
          recordFailure(
            'Get Paid dashboard Lightning Address lookup failed',
            error: error,
            trace: trace,
          );
          // The nym drives the Page/POS queries, so a failed lookup leaves ALL
          // three products UNAVAILABLE (truth unknown) — never absent.
          emit(
            state.copyWith(
              lightningStatus: GetPaidProductStatus.unavailable,
              paymentPageStatus: GetPaidProductStatus.unavailable,
              posStatus: GetPaidProductStatus.unavailable,
            ),
          );
          return;
        }
      } on Exception catch (error, trace) {
        if (_isStale(generation)) return;
        recordFailure(
          'Get Paid dashboard Lightning Address lookup failed',
          error: error,
          trace: trace,
        );
        emit(
          state.copyWith(
            lightningStatus: GetPaidProductStatus.unavailable,
            paymentPageStatus: GetPaidProductStatus.unavailable,
            posStatus: GetPaidProductStatus.unavailable,
          ),
        );
        return;
      }
      if (_isStale(generation)) return;

      final nym = registration.nym.isEmpty ? null : registration.nym;
      final address = (registration.lightningAddress?.isEmpty ?? true)
          ? null
          : registration.lightningAddress;
      emit(
        state.copyWith(
          lightningAddress: address,
          clearLightningAddress: address == null,
          lightningActive: registration.active,
          nym: nym,
          clearNym: nym == null,
          // A resolved registration (active or inactive) is a present card;
          // no nym is a CONFIRMED empty account (absent).
          lightningStatus: nym == null
              ? GetPaidProductStatus.absent
              : GetPaidProductStatus.active,
        ),
      );

      if (nym == null) {
        // Confirmed empty account: no Page/POS products yet (absent, not
        // unavailable). The manifest never creates a product card.
        emit(
          state.copyWith(
            clearPaymentPage: true,
            clearPos: true,
            paymentPageStatus: GetPaidProductStatus.absent,
            posStatus: GetPaidProductStatus.absent,
          ),
        );
        return;
      }

      // Self-heal the Lightning Address wallet (101) only while it is active.
      final lightningHealFuture = registration.active
          ? _healProductWallet(
              generation,
              GetPaidWalletBackedProduct.lightningAddress,
            )
          : Future<void>.value();

      final fallbackFuture = () async {
        try {
          final ready = await _ensureAutomaticFallback.execute();
          if (_isStale(generation)) return;
          if (!ready) {
            recordFailure('Get Paid automatic fallback setup failed');
          }
        } on Exception catch (error, trace) {
          if (_isStale(generation)) return;
          recordFailure(
            'Get Paid automatic fallback setup threw unexpectedly',
            error: error,
            trace: trace,
          );
        }
      }();

      final pageFuture = () async {
        try {
          final page = await _paymentPage.find(nym: nym);
          if (_isStale(generation)) return;
          if (page == null) {
            emit(
              state.copyWith(
                clearPaymentPage: true,
                paymentPageStatus: GetPaidProductStatus.absent,
              ),
            );
            return;
          }
          if (page.isArchived) {
            // Archived => keep the object for a status-only card; not active.
            emit(
              state.copyWith(
                paymentPage: page,
                paymentPageStatus: GetPaidProductStatus.archived,
              ),
            );
            return;
          }
          emit(
            state.copyWith(
              paymentPage: page,
              paymentPageStatus: GetPaidProductStatus.active,
            ),
          );
          await _healProductWallet(
            generation,
            GetPaidWalletBackedProduct.paymentPage,
          );
        } on Exception catch (error, trace) {
          if (_isStale(generation)) return;
          recordFailure(
            'Get Paid dashboard Donation Page lookup failed',
            error: error,
            trace: trace,
          );
          emit(
            state.copyWith(paymentPageStatus: GetPaidProductStatus.unavailable),
          );
        }
      }();
      final posFuture = () async {
        try {
          final terminal = await _pos.find(nym: nym);
          if (_isStale(generation)) return;
          if (terminal == null) {
            emit(
              state.copyWith(
                clearPos: true,
                posStatus: GetPaidProductStatus.absent,
              ),
            );
            return;
          }
          if (terminal.isArchived) {
            emit(
              state.copyWith(
                posTerminal: terminal,
                posStatus: GetPaidProductStatus.archived,
              ),
            );
            return;
          }
          emit(
            state.copyWith(
              posTerminal: terminal,
              posStatus: GetPaidProductStatus.active,
            ),
          );
          await _healProductWallet(generation, GetPaidWalletBackedProduct.pos);
        } on Exception catch (error, trace) {
          if (_isStale(generation)) return;
          recordFailure(
            'Get Paid dashboard Point of Sale lookup failed',
            error: error,
            trace: trace,
          );
          emit(state.copyWith(posStatus: GetPaidProductStatus.unavailable));
        }
      }();
      await Future.wait([
        lightningHealFuture,
        fallbackFuture,
        pageFuture,
        posFuture,
      ]);
    }();

    // Fiat-settlement badges: mainnet-only, server-read-only truth. A confirmed
    // read populates the per-product config; a mainnet read FAILURE clears the
    // map and flags it unavailable so active slots show an honest "unavailable"
    // badge (never a stale or guessed Bitcoin-only). Never marks the refresh as
    // failed (settlement presentation is independent of the rest of the hub).
    final fiatSettlementFuture = () async {
      final facade = _fiatSettlement;
      final getSettings = _getSettings;
      if (facade == null || getSettings == null) return;
      try {
        final settings = await getSettings.execute();
        if (settings.environment != Environment.mainnet) return;
        final result = await facade.configuration();
        if (_isStale(generation)) return;
        switch (result) {
          case Ok(:final value):
            emit(
              state.copyWith(
                fiatSettlement: {
                  for (final product in FiatSettlementProduct.values)
                    product: value.configFor(product),
                },
                fiatSettlementUnavailable: false,
              ),
            );
          case Err():
            emit(
              state.copyWith(
                clearFiatSettlement: true,
                fiatSettlementUnavailable: true,
              ),
            );
        }
      } on Exception catch (error, trace) {
        log.warning(
          'Get Paid dashboard fiat-settlement summary lookup failed',
          error: error,
          trace: trace,
        );
        if (_isStale(generation)) return;
        emit(
          state.copyWith(
            clearFiatSettlement: true,
            fiatSettlementUnavailable: true,
          ),
        );
      }
    }();

    await Future.wait([
      invoicesFuture,
      btcpayFuture,
      lightningAndSurfacesFuture,
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

  /// Contract #4 Q9/Q9b self-heal for an ACTIVE product: re-derive its
  /// fixed-path wallet if missing, recording it in the manifest. Idempotent (a
  /// present wallet is a no-op). Only a re-derivation FAILURE raises the
  /// product's missing-wallet warning; success clears it. The usecase never
  /// throws, and every emit is generation-guarded.
  Future<void> _healProductWallet(
    int generation,
    GetPaidWalletBackedProduct product,
  ) async {
    final outcome = await _ensureProductWallet.execute(product);
    if (_isStale(generation)) return;
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

  /// Whether the user has at least one default wallet — the Invoices product
  /// pays out from the default wallet, mirroring [CreateInvoiceUsecase]'s
  /// `onlyDefaults: true` resolution. Never throws: a missing-wallet failure
  /// simply means "not ready", and it must not abort the dashboard refresh.
  Future<bool> _hasDefaultWallet() async {
    try {
      final wallets = await _getWallets.execute(onlyDefaults: true);
      return wallets.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _isStale(int generation) {
    return isClosed || generation != _refreshGeneration;
  }
}
