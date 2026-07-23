import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/btcpay/public/btcpay_routes.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/fiat_settlement/ui/fiat_settlement_copy.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/get_paid/public/get_paid_routes.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:bb_mobile/features/invoices/public/invoices_routes.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_routes.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_routes.dart';
import 'package:bb_mobile/features/pos/public/pos_routes.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart'
    show
        AppLifecycleState,
        Icons,
        SliverChildListDelegate,
        SliverList,
        SliverPadding,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The Get Paid hub — the third bottom-nav tab. Draws its own [BullTopBar]
/// (the shell app bar is null for this tab) and lists Get Paid history plus the
/// products as tappable slot cards. Auto-refreshes on init, on app-resume and
/// on pull; reads public facades only.
class GetPaidDashboardScreen extends StatefulWidget {
  const GetPaidDashboardScreen({super.key});

  @override
  State<GetPaidDashboardScreen> createState() => _GetPaidDashboardScreenState();
}

class _GetPaidDashboardScreenState extends State<GetPaidDashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<GetPaidDashboardCubit>().refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<GetPaidDashboardCubit>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BullScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BullTopBar(title: context.loc.getPaidDashboardTitle),
            Expanded(
              child: BlocConsumer<GetPaidDashboardCubit, GetPaidDashboardState>(
                listenWhen: (prev, curr) =>
                    prev.error != curr.error && curr.error != null,
                listener: (context, state) {
                  BullSnackBar.show(
                    context,
                    message: context.loc.getPaidDashboardError,
                  );
                },
                builder: (context, state) {
                  return BullPullableBody(
                    onRefresh: context.read<GetPaidDashboardCubit>().refresh,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            _cards(context, state),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(BuildContext context, GetPaidDashboardState state) {
    final loc = context.loc;
    final page = state.paymentPage;
    final pos = state.posTerminal;
    // Q14: a dedicated settlement badge on all three fiat-capable product cards
    // (Lightning Address, Donation Page, POS), consistently — never appended to
    // the truncatable URL subtitle.
    final lightningSettlement = _settlementBadge(
      context,
      state,
      FiatSettlementProduct.lightningAddress,
      active: state.lightningActive,
    );
    final pageSettlement = _settlementBadge(
      context,
      state,
      FiatSettlementProduct.paymentPage,
      active: state.hasPaymentPage,
    );
    final posSettlement = _settlementBadge(
      context,
      state,
      FiatSettlementProduct.pos,
      active: state.hasPos,
    );
    // Per-product truth chips (active / archived / absent / unavailable). LA is
    // "active" whenever a registration is present; its green dot tracks the
    // registration's own active flag.
    final lightning = _productChip(
      context,
      state.lightningStatus,
      activeGreen: state.lightningActive,
    );
    final pageChip = _productChip(
      context,
      state.paymentPageStatus,
      activeGreen: true,
    );
    final posChip = _productChip(context, state.posStatus, activeGreen: true);
    final refresh = context.read<GetPaidDashboardCubit>().refresh;
    return [
      GetPaidSlotCard(
        icon: Icons.payments_outlined,
        title: loc.getPaidDashboardTransactionsTitle,
        subtitle: loc.getPaidDashboardTransactionsSubtitle,
        onTap: () => _open(GetPaidDashboardRoute.getPaidTransactions.name),
      ),
      const Gap(12),
      GetPaidSlotCard(
        icon: Icons.alternate_email,
        title: loc.getPaidDashboardLightningAddressTitle,
        // Show the address as the subtitle whenever one is present, regardless
        // of the active status (the status dot reflects `active` separately).
        subtitle: state.hasLightningAddress
            ? state.lightningAddress!
            : loc.getPaidDashboardLightningAddressSubtitle,
        isLoading: state.lightningStatus == GetPaidProductStatus.loading,
        statusLabel: lightning.label,
        statusActive: lightning.active,
        settlementLabel: lightningSettlement.label,
        settlementUnavailable: lightningSettlement.unavailable,
        retry: lightning.showRetry
            ? (label: loc.getPaidDashboardRetry, onTap: refresh)
            : null,
        warningLabel: state.lightningWalletWarning
            ? loc.getPaidDashboardWalletWarning
            : null,
        onTap: () => _open(LightningAddressRoute.lightningAddressSettings.name),
      ),
      const Gap(12),
      GetPaidSlotCard(
        icon: Icons.storefront,
        title: loc.getPaidDashboardDonationPageTitle,
        subtitle: page?.publicUrl ?? loc.getPaidDashboardDonationPageSubtitle,
        isLoading: state.paymentPageStatus == GetPaidProductStatus.loading,
        statusLabel: pageChip.label,
        statusActive: pageChip.active,
        settlementLabel: pageSettlement.label,
        settlementUnavailable: pageSettlement.unavailable,
        retry: pageChip.showRetry
            ? (label: loc.getPaidDashboardRetry, onTap: refresh)
            : null,
        warningLabel: state.paymentPageWalletWarning
            ? loc.getPaidDashboardWalletWarning
            : null,
        onTap: () => _open(PaymentPageRoute.paymentPageSettings.name),
      ),
      const Gap(12),
      GetPaidSlotCard(
        icon: Icons.point_of_sale,
        title: loc.getPaidDashboardPosTitle,
        subtitle: pos?.terminalUrl ?? loc.getPaidDashboardPosSubtitle,
        isLoading: state.posStatus == GetPaidProductStatus.loading,
        statusLabel: posChip.label,
        statusActive: posChip.active,
        settlementLabel: posSettlement.label,
        settlementUnavailable: posSettlement.unavailable,
        retry: posChip.showRetry
            ? (label: loc.getPaidDashboardRetry, onTap: refresh)
            : null,
        warningLabel: state.posWalletWarning
            ? loc.getPaidDashboardWalletWarning
            : null,
        onTap: () => _open(PosRoute.posSettings.name),
      ),
      const Gap(12),
      GetPaidSlotCard(
        icon: Icons.receipt_long,
        title: loc.getPaidDashboardInvoicesTitle,
        // Per-invoice settlement is chosen at invoice creation (entry tile), so
        // the hub's Invoices card carries no settlement badge (Q14 scopes the
        // badge to the three product cards above).
        subtitle: loc.getPaidDashboardInvoicesSubtitle,
        isLoading: state.invoicesStatus == GetPaidDashboardCardStatus.loading,
        // Active green once the user's default wallet is created (invoices pay
        // out from the default wallet).
        statusLabel: state.hasFallbackAttention
            ? loc.getPaidDashboardFallbackPending(state.fallbackAttentionCount!)
            : state.invoicesWalletReady
            ? loc.getPaidDashboardActive
            : null,
        statusActive: state.invoicesWalletReady && !state.hasFallbackAttention,
        onTap: () => _open(
          state.hasFallbackAttention
              ? InvoicesRoute.list.name
              : InvoicesRoute.create.name,
        ),
      ),
      const Gap(12),
      GetPaidSlotCard(
        icon: Icons.hub,
        title: loc.getPaidDashboardBtcpayTitle,
        // No store-name field on the connection; the server URL is the most
        // human-readable identifier available.
        subtitle:
            state.btcpayConnection?.serverUrl ??
            loc.getPaidDashboardBtcpaySubtitle,
        isLoading: state.btcpayStatus == GetPaidDashboardCardStatus.loading,
        // Active green when a BTCPay connection exists.
        statusLabel: state.hasBtcpayConnection
            ? loc.getPaidDashboardActive
            : null,
        statusActive: state.hasBtcpayConnection,
        onTap: () => _open(BtcpayRoute.btcpaySettings.name),
      ),
    ];
  }

  /// The dedicated settlement badge for an ACTIVE product slot. A confirmed
  /// config renders the summary ("Bitcoin only" / "100% fiat · CAD" / mixed);
  /// a failed mainnet read renders the muted "unavailable" variant (never a
  /// stale or guessed state). Inactive slots and non-mainnet/feature-off
  /// environments render nothing.
  ({String? label, bool unavailable}) _settlementBadge(
    BuildContext context,
    GetPaidDashboardState state,
    FiatSettlementProduct product, {
    required bool active,
  }) {
    if (!active) return (label: null, unavailable: false);
    final config = state.fiatSettlement?[product];
    if (config != null) {
      return (label: context.fiatSettlementSummary(config), unavailable: false);
    }
    if (state.fiatSettlementUnavailable) {
      return (
        label: context.loc.getPaidDashboardSettlementUnavailable,
        unavailable: true,
      );
    }
    return (label: null, unavailable: false);
  }

  /// Maps a product's queried status to its card chip. [activeGreen] gates the
  /// green "Active" chip (Page/POS: always when active; LA: only when the
  /// registration itself is active). `showRetry` is set for the unavailable
  /// (failed/timed-out) state — the card stays tappable to the product screen
  /// regardless.
  ({String? label, bool active, bool showRetry}) _productChip(
    BuildContext context,
    GetPaidProductStatus status, {
    required bool activeGreen,
  }) {
    final loc = context.loc;
    return switch (status) {
      GetPaidProductStatus.loading => (
        label: null,
        active: false,
        showRetry: false,
      ),
      GetPaidProductStatus.active =>
        activeGreen
            ? (
                label: loc.getPaidDashboardActive,
                active: true,
                showRetry: false,
              )
            : (label: null, active: false, showRetry: false),
      GetPaidProductStatus.archived => (
        label: loc.getPaidDashboardArchived,
        active: false,
        showRetry: false,
      ),
      GetPaidProductStatus.absent => (
        label: loc.getPaidDashboardNotSetUp,
        active: false,
        showRetry: false,
      ),
      GetPaidProductStatus.unavailable => (
        label: loc.getPaidDashboardUnavailable,
        active: false,
        showRetry: true,
      ),
    };
  }

  Future<void> _open(String routeName) async {
    // Each product's screen resolves create-vs-manage internally (single-route
    // model on this base); the hub just returns and re-reads status.
    await context.pushNamed(routeName);
    if (!mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }
}
