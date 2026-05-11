import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/screens/payment_page_editor_screen.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:bb_mobile/features/settings/ui/settings_router.dart';
import 'package:bb_mobile/locator.dart';
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
                    actionLabel: state.hasLightningAddress
                        ? 'Manage'
                        : 'Set up',
                    onPressed: () => _openLightningAddress(context),
                  ),
                  const SizedBox(height: 12),
                  GetPaidSlotCard(
                    icon: Icons.storefront,
                    title: 'Payment Page',
                    subtitle: _paymentPageSubtitle(state),
                    actionLabel: state.hasPaymentPage ? 'Edit' : 'Create',
                    onPressed: state.nym == null
                        ? null
                        : () => _openPaymentPage(context, state.nym!),
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
    if (!state.hasLightningAddress) {
      return 'Create a Lightning Address first';
    }
    final page = state.paymentPage;
    if (page == null) return 'Not set up';
    return page.enabled ? page.publicUrl : '${page.publicUrl} (disabled)';
  }

  Future<void> _openLightningAddress(BuildContext context) async {
    await context.pushNamed(SettingsRoute.lightningAddress.name);
    if (!mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }

  Future<void> _openPaymentPage(BuildContext context, String nym) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => locator<PaymentPageCubit>(),
          child: PaymentPageEditorScreen(nym: nym),
        ),
      ),
    );
    if (changed != true || !mounted) return;
    await context.read<GetPaidDashboardCubit>().refresh();
  }
}
