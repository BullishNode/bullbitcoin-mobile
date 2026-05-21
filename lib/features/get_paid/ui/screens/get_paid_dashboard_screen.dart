import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/payment_page_router.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/get_paid/ui/get_paid_router.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class GetPaidDashboardScreen extends StatefulWidget {
  final VoidCallback? onExternalReceiveWalletsCreated;

  const GetPaidDashboardScreen({
    super.key,
    this.onExternalReceiveWalletsCreated,
  });

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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(WalletRoute.walletHome.name),
        ),
        title: Text(context.loc.getPaidDashboardTitle),
        actions: [
          IconButton(
            tooltip: context.loc.getPaidSettingsTitle,
            icon: const Icon(Icons.settings),
            onPressed: () =>
                context.pushNamed(GetPaidRoute.getPaidSettings.name),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<GetPaidDashboardCubit, GetPaidDashboardState>(
          builder: (context, state) {
            if (state.isLoading && !state.hasLightningAddress) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: context.read<GetPaidDashboardCubit>().refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.error != null) ...[
                    Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  GetPaidSlotCard(
                    icon: Icons.alternate_email,
                    title: context.loc.getPaidDashboardLightningAddressTitle,
                    subtitle:
                        context.loc.getPaidDashboardLightningAddressSubtitle,
                    statusLabel: state.hasLightningAddress
                        ? context.loc.getPaidDashboardActive
                        : null,
                    statusActive: state.hasLightningAddress,
                    onPressed: () => _openLightningAddress(context),
                  ),
                  const SizedBox(height: 12),
                  GetPaidSlotCard(
                    icon: Icons.storefront,
                    title: context.loc.getPaidDashboardPaymentPageTitle,
                    subtitle: _paymentPageSubtitle(context, state),
                    statusLabel: _paymentPageStatusLabel(context, state),
                    statusActive: state.paymentPage?.enabled ?? false,
                    onPressed: () => _openPaymentPage(context, state.nym),
                  ),
                  const SizedBox(height: 12),
                  GetPaidSlotCard(
                    icon: Icons.receipt_long,
                    title: context.loc.getPaidDashboardInvoicesTitle,
                    subtitle: context.loc.getPaidDashboardInvoicesSubtitle,
                    onPressed: () => _openInvoices(context),
                  ),
                  const SizedBox(height: 12),
                  GetPaidSlotCard(
                    icon: Icons.point_of_sale,
                    title: context.loc.getPaidDashboardBtcpayTitle,
                    subtitle: context.loc.getPaidDashboardBtcpaySubtitle,
                    statusLabel: state.hasBtcpayConnection
                        ? context.loc.getPaidDashboardActive
                        : null,
                    statusActive: state.hasBtcpayConnection,
                    onPressed: () => _openBtcpay(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _paymentPageSubtitle(
    BuildContext context,
    GetPaidDashboardState state,
  ) {
    final page = state.paymentPage;
    if (page == null) return context.loc.getPaidDashboardPaymentPageSubtitle;
    return page.publicUrl;
  }

  String? _paymentPageStatusLabel(
    BuildContext context,
    GetPaidDashboardState state,
  ) {
    final page = state.paymentPage;
    if (page == null) return null;
    return page.enabled
        ? context.loc.getPaidDashboardActive
        : context.loc.getPaidDashboardNotPublished;
  }

  Future<void> _openLightningAddress(BuildContext context) async {
    await context.pushNamed(LightningAddressFacade.manageRouteName);
    if (!mounted) return;
    widget.onExternalReceiveWalletsCreated?.call();
    await context.read<GetPaidDashboardCubit>().refresh();
  }

  Future<void> _openPaymentPage(BuildContext context, String? nym) async {
    if (nym == null || nym.isEmpty) {
      final changed = await context.pushNamed<bool>(
        PaymentPageRoute.createPaymentPage.name,
      );
      if (!mounted) return;
      widget.onExternalReceiveWalletsCreated?.call();
      if (changed != true) return;
      await context.read<GetPaidDashboardCubit>().refresh();
      return;
    }
    final changed = await context.pushNamed<bool>(
      PaymentPageRoute.editor.name,
      pathParameters: {'nym': nym},
    );
    if (changed != true || !mounted) return;
    widget.onExternalReceiveWalletsCreated?.call();
    await context.read<GetPaidDashboardCubit>().refresh();
  }

  Future<void> _openInvoices(BuildContext context) async {
    final changed = await context.pushNamed<bool>(InvoicesRoute.home.name);
    if (changed != true || !mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }

  Future<void> _openBtcpay(BuildContext context) async {
    final changed = await context.pushNamed<bool>(
      GetPaidRoute.btcpayPairing.name,
    );
    if (changed != true || !mounted) return;
    widget.onExternalReceiveWalletsCreated?.call();
    await context.read<GetPaidDashboardCubit>().refresh();
  }
}
