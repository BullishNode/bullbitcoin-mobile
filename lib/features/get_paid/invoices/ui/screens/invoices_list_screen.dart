import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_state.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/widgets/invoice_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

class InvoicesListScreen extends StatefulWidget {
  const InvoicesListScreen({super.key});

  @override
  State<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends State<InvoicesListScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<InvoicesListCubit>().load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<InvoicesListCubit>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: SafeArea(
        child: BlocBuilder<InvoicesListCubit, InvoicesListState>(
          builder: (context, state) {
            return RefreshIndicator(
              onRefresh: context.read<InvoicesListCubit>().refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.error != null) ...[
                    Text(
                      state.error!,
                      style: TextStyle(color: context.appColors.error),
                    ),
                    const Gap(16),
                  ],
                  _StatusFilters(state: state),
                  const Gap(16),
                  if (state.isLoading && state.invoices.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (state.filteredInvoices.isEmpty)
                    const _EmptyInvoicesView()
                  else
                    for (final invoice in state.filteredInvoices)
                      InvoiceListItem(
                        invoice: invoice,
                        onTap: () => _openDetail(context, invoice),
                      ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BBButton.big(
            label: 'Create invoice',
            onPressed: () => _openCreate(context),
            bgColor: context.appColors.secondary,
            textColor: context.appColors.onSecondary,
          ),
        ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    final changed = await context.pushNamed<bool>(InvoicesRoute.create.name);
    if (changed == true && context.mounted) {
      await context.read<InvoicesListCubit>().refresh();
    }
  }

  Future<void> _openDetail(BuildContext context, Invoice invoice) async {
    final changed = await context.pushNamed<bool>(
      InvoicesRoute.detail.name,
      pathParameters: {'invoiceId': invoice.id.value},
      queryParameters: {
        if (invoice.nymOwner != null) 'nymOwner': invoice.nymOwner!,
        if (invoice.shareUrl != null) 'shareUrl': invoice.shareUrl!.value,
      },
    );
    if (changed == true && context.mounted) {
      await context.read<InvoicesListCubit>().refresh();
    }
  }
}

class _StatusFilters extends StatelessWidget {
  final InvoicesListState state;

  const _StatusFilters({required this.state});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: const Text('All'),
          selected: state.statusFilter == null,
          onSelected: (_) =>
              context.read<InvoicesListCubit>().setStatusFilter(null),
        ),
        for (final status in InvoiceStatus.values)
          FilterChip(
            label: Text(_statusLabel(status)),
            selected: state.statusFilter == status,
            onSelected: (_) =>
                context.read<InvoicesListCubit>().setStatusFilter(status),
          ),
      ],
    );
  }

  String _statusLabel(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.inProgress => 'In progress',
      InvoiceStatus.partiallyPaid => 'Partially paid',
      _ => status.value[0].toUpperCase() + status.value.substring(1),
    };
  }
}

class _EmptyInvoicesView extends StatelessWidget {
  const _EmptyInvoicesView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: Text('No invoices')),
    );
  }
}
