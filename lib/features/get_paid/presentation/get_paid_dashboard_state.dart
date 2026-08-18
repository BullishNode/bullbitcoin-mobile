import 'package:bb_mobile/features/btcpay/public/btcpay_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';

enum GetPaidDashboardCardStatus { loading, loaded }

/// Per-product truth for the three Bullnym-backed products (Lightning Address,
/// Donation Page, POS), queried on every refresh. A server failure or timeout
/// is [unavailable] (with Retry), never [absent]: the manifest never creates an
/// active product card, so "not configured" is only ever a CONFIRMED empty read.
enum GetPaidProductStatus {
  /// The product query is in flight.
  loading,

  /// The product exists and is live on the server.
  active,

  /// The product exists but is archived (deactivated) — a status-only card;
  /// reactivation lives on the product screen.
  archived,

  /// A confirmed read found no product configured yet.
  absent,

  /// The product query failed/timed out; its truth is unknown. Shown with
  /// Retry; the card stays tappable so the product screen can re-query.
  unavailable,
}

/// Read-only snapshot of every Get Paid product's status, assembled from the
/// public facades. Holds no money logic, no balances and no protocol internals
/// — only what the hub renders (a status chip + a contextual subtitle per
/// product).
class GetPaidDashboardState {
  final bool isLoading;
  final String? lightningAddress;

  /// True when the Lightning Address registration is ACTIVE. Decoupled from
  /// [lightningAddress]: the address may be present while the registration is
  /// inactive (subtitle shows the address; the status dot stays muted).
  final bool lightningActive;
  final String? nym;
  final PaymentPage? paymentPage;
  final PosTerminal? posTerminal;
  final BtcpayConnection? btcpayConnection;

  /// True when the user has a default wallet created — the Invoices product
  /// issues payouts from the default wallet, so this gates its "Active" status.
  final bool invoicesWalletReady;

  /// Authenticated automatic-fallback rows that are not yet settled. `null`
  /// means unavailable or not applicable; zero is a successful empty result.
  final int? fallbackAttentionCount;
  final String? error;
  final GetPaidProductStatus lightningStatus;
  final GetPaidProductStatus paymentPageStatus;
  final GetPaidProductStatus posStatus;
  final GetPaidDashboardCardStatus invoicesStatus;
  final GetPaidDashboardCardStatus btcpayStatus;

  /// True when a product is ACTIVE but its fixed-derivation wallet could not be
  /// re-derived locally (contract #4 Q9/Q9b self-heal failed) — the card shows a
  /// missing-wallet warning and its wallet-dependent controls are disabled.
  final bool lightningWalletWarning;
  final bool paymentPageWalletWarning;
  final bool posWalletWarning;

  /// Server-confirmed fiat-settlement configuration per product, for the slot
  /// badges. Null when not applicable (testnet / feature off) — no badge. On a
  /// mainnet read FAILURE this is cleared and [fiatSettlementUnavailable] is
  /// set so active slots show an honest "unavailable" badge, never a stale or
  /// guessed (e.g. Bitcoin-only) state.
  final Map<FiatSettlementProduct, FiatSettlementProductConfig>? fiatSettlement;

  /// True when a mainnet fiat-settlement read was attempted and failed; active
  /// product slots then render the settlement badge as "unavailable".
  final bool fiatSettlementUnavailable;

  const GetPaidDashboardState({
    this.isLoading = false,
    this.lightningAddress,
    this.lightningActive = false,
    this.nym,
    this.paymentPage,
    this.posTerminal,
    this.btcpayConnection,
    this.invoicesWalletReady = false,
    this.fallbackAttentionCount,
    this.error,
    this.lightningStatus = GetPaidProductStatus.loading,
    this.paymentPageStatus = GetPaidProductStatus.loading,
    this.posStatus = GetPaidProductStatus.loading,
    this.invoicesStatus = GetPaidDashboardCardStatus.loading,
    this.btcpayStatus = GetPaidDashboardCardStatus.loading,
    this.fiatSettlement,
    this.fiatSettlementUnavailable = false,
    this.lightningWalletWarning = false,
    this.paymentPageWalletWarning = false,
    this.posWalletWarning = false,
  });

  bool get hasLightningAddress =>
      lightningAddress != null && lightningAddress!.isNotEmpty;
  bool get hasPaymentPage => paymentPage != null && !paymentPage!.isArchived;
  bool get hasPos => posTerminal != null && !posTerminal!.isArchived;
  bool get hasBtcpayConnection => btcpayConnection != null;
  bool get hasFallbackAttention => (fallbackAttentionCount ?? 0) > 0;

  GetPaidDashboardState copyWith({
    bool? isLoading,
    String? lightningAddress,
    bool clearLightningAddress = false,
    bool? lightningActive,
    String? nym,
    bool clearNym = false,
    PaymentPage? paymentPage,
    bool clearPaymentPage = false,
    PosTerminal? posTerminal,
    bool clearPos = false,
    BtcpayConnection? btcpayConnection,
    bool clearBtcpayConnection = false,
    bool? invoicesWalletReady,
    int? fallbackAttentionCount,
    bool clearFallbackAttention = false,
    String? error,
    bool clearError = false,
    GetPaidProductStatus? lightningStatus,
    GetPaidProductStatus? paymentPageStatus,
    GetPaidProductStatus? posStatus,
    GetPaidDashboardCardStatus? invoicesStatus,
    GetPaidDashboardCardStatus? btcpayStatus,
    Map<FiatSettlementProduct, FiatSettlementProductConfig>? fiatSettlement,
    bool clearFiatSettlement = false,
    bool? fiatSettlementUnavailable,
    bool? lightningWalletWarning,
    bool? paymentPageWalletWarning,
    bool? posWalletWarning,
  }) {
    return GetPaidDashboardState(
      isLoading: isLoading ?? this.isLoading,
      lightningAddress: clearLightningAddress
          ? null
          : lightningAddress ?? this.lightningAddress,
      lightningActive: lightningActive ?? this.lightningActive,
      nym: clearNym ? null : nym ?? this.nym,
      paymentPage: clearPaymentPage ? null : paymentPage ?? this.paymentPage,
      posTerminal: clearPos ? null : posTerminal ?? this.posTerminal,
      btcpayConnection: clearBtcpayConnection
          ? null
          : btcpayConnection ?? this.btcpayConnection,
      invoicesWalletReady: invoicesWalletReady ?? this.invoicesWalletReady,
      fallbackAttentionCount: clearFallbackAttention
          ? null
          : fallbackAttentionCount ?? this.fallbackAttentionCount,
      error: clearError ? null : error ?? this.error,
      lightningStatus: lightningStatus ?? this.lightningStatus,
      paymentPageStatus: paymentPageStatus ?? this.paymentPageStatus,
      posStatus: posStatus ?? this.posStatus,
      invoicesStatus: invoicesStatus ?? this.invoicesStatus,
      btcpayStatus: btcpayStatus ?? this.btcpayStatus,
      fiatSettlement: clearFiatSettlement
          ? null
          : fiatSettlement ?? this.fiatSettlement,
      fiatSettlementUnavailable:
          fiatSettlementUnavailable ?? this.fiatSettlementUnavailable,
      lightningWalletWarning:
          lightningWalletWarning ?? this.lightningWalletWarning,
      paymentPageWalletWarning:
          paymentPageWalletWarning ?? this.paymentPageWalletWarning,
      posWalletWarning: posWalletWarning ?? this.posWalletWarning,
    );
  }
}
