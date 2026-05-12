import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final InvoiceId invoiceId;
  final String? nymOwner;
  final String? shareUrl;

  const InvoiceDetailScreen({
    super.key,
    required this.invoiceId,
    required this.nymOwner,
    this.shareUrl,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<InvoiceDetailCubit>().load(
      id: widget.invoiceId,
      nymOwner: widget.nymOwner,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: SafeArea(
        child: BlocBuilder<InvoiceDetailCubit, InvoiceDetailState>(
          builder: (context, state) {
            if (state.isLoading && state.snapshot == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: context.read<InvoiceDetailCubit>().refresh,
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
                  if (state.snapshot == null)
                    const _MissingInvoiceView()
                  else
                    _InvoiceDetailBody(state: state, shareUrl: widget.shareUrl),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InvoiceDetailBody extends StatelessWidget {
  final InvoiceDetailState state;
  final String? shareUrl;

  const _InvoiceDetailBody({required this.state, required this.shareUrl});

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot!;
    final status = state.cancelResult?.status ?? snapshot.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailRow(label: 'Status', value: _statusLabel(status)),
        _DetailRow(label: 'Amount', value: '${snapshot.amountSat} sats'),
        _DetailRow(label: 'Expires', value: _expiryLabel(snapshot.expiresAt)),
        if (shareUrl != null) ...[
          const Gap(12),
          const Text('Invoice URL'),
          const Gap(6),
          CopyInput(text: shareUrl!),
        ],
        if (snapshot.bitcoinAddress != null) ...[
          const Gap(12),
          const Text('Bitcoin address'),
          const Gap(6),
          CopyInput(text: snapshot.bitcoinAddress!),
        ],
        if (snapshot.lightningPr != null) ...[
          const Gap(12),
          const Text('Lightning invoice'),
          const Gap(6),
          CopyInput(
            text: snapshot.lightningPr!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            canShowValueModal: true,
            modalTitle: 'Lightning invoice',
          ),
        ],
        if (snapshot.liquidAddress != null) ...[
          const Gap(12),
          const Text('Liquid address'),
          const Gap(6),
          CopyInput(text: snapshot.liquidAddress!),
        ],
        if (snapshot.paidVia != null)
          _DetailRow(label: 'Paid via', value: snapshot.paidVia!.value),
        if (snapshot.paidAmountSat != null)
          _DetailRow(
            label: 'Paid amount',
            value: '${snapshot.paidAmountSat} sats',
          ),
        const Gap(24),
        if (status == InvoiceStatus.unpaid)
          BBButton.big(
            label: state.isCancelling ? 'Cancelling...' : 'Cancel invoice',
            disabled: state.isBusy,
            onPressed: () => _confirmCancel(context),
            bgColor: context.appColors.transparent,
            textColor: context.appColors.onSurface,
            outlined: true,
            borderColor: context.appColors.onSurface,
          ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel invoice?'),
        content: const Text('This invoice will no longer be payable.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep invoice'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel invoice'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<InvoiceDetailCubit>().cancel();
  }

  String _statusLabel(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.inProgress => 'in progress',
      _ => status.value,
    };
  }

  String _expiryLabel(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours % 24}h';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}min';
    }
    return '${remaining.inMinutes}min';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: context.font.bodyMedium?.copyWith(
                color: context.appColors.textMuted,
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: context.font.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingInvoiceView extends StatelessWidget {
  const _MissingInvoiceView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: Text('Invoice not found')),
    );
  }
}
