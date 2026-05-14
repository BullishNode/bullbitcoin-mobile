import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/payment_page_router.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Get paid')),
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
                    title: 'Lightning Address',
                    subtitle: state.lightningAddress ?? 'Not set up',
                    statusLabel: state.hasLightningAddress ? 'Active' : null,
                    statusActive: state.hasLightningAddress,
                    onPressed: () => _openLightningAddress(context),
                  ),
                  const SizedBox(height: 12),
                  GetPaidSlotCard(
                    icon: Icons.storefront,
                    title: 'Payment Page',
                    subtitle: _paymentPageSubtitle(state),
                    statusLabel: _paymentPageStatusLabel(state),
                    statusActive: state.paymentPage?.enabled ?? false,
                    onPressed: state.nym == null
                        ? null
                        : () => _openPaymentPage(context, state.nym!),
                  ),
                  const SizedBox(height: 12),
                  GetPaidSlotCard(
                    icon: Icons.receipt_long,
                    title: 'Invoices',
                    subtitle: 'Create and manage invoices',
                    onPressed: () => _openInvoices(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _paymentPageSubtitle(GetPaidDashboardState state) {
    if (state.nym == null) {
      return 'Choose a Bullnym name first';
    }
    final page = state.paymentPage;
    if (page == null) return 'Not set up';
    return page.publicUrl;
  }

  String? _paymentPageStatusLabel(GetPaidDashboardState state) {
    final page = state.paymentPage;
    if (page == null) return null;
    return page.enabled ? 'Active' : 'Not published';
  }

  Future<void> _openLightningAddress(BuildContext context) async {
    await context.pushNamed(LightningAddressFacade.manageRouteName);
    if (!mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }

  Future<void> _openPaymentPage(BuildContext context, String nym) async {
    final changed = await context.pushNamed<bool>(
      PaymentPageRoute.editor.name,
      pathParameters: {'nym': nym},
    );
    if (changed != true || !mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }

  Future<void> _openInvoices(BuildContext context) async {
    final changed = await context.pushNamed<bool>(InvoicesRoute.home.name);
    if (changed != true || !mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }
}
