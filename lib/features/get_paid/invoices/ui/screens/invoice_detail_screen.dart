import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/string_formatting.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/core/widgets/tables/details_table_item.dart';
import 'package:bb_mobile/core/widgets/timers/countdown.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_state.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<InvoiceDetailCubit>().load(
      id: widget.invoiceId,
      nymOwner: widget.nymOwner,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<InvoiceDetailCubit>().refresh();
    }
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
                    _InvoiceDetailBody(
                      state: state,
                      shareUrl: widget.shareUrl ?? _fallbackShareUrl(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _fallbackShareUrl() {
    return invoicePublicUrlFor(
      nym: widget.nymOwner,
      id: widget.invoiceId,
      domain: bullnymDefaultDomain,
    ).value;
  }
}

class _InvoiceDetailBody extends StatelessWidget {
  final InvoiceDetailState state;
  final String shareUrl;

  const _InvoiceDetailBody({required this.state, required this.shareUrl});

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot!;
    final status = state.cancelResult?.status ?? snapshot.status;
    final amountSat = status == InvoiceStatus.partiallyPaid
        ? snapshot.remainingAmountSat
        : snapshot.amountSat;
    final dateFormat = DateFormat('MMM d, y, h:mm a');
    final resolvedShareUrl = snapshot.shareUrl?.value ?? shareUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(_statusIcon(status), color: context.appColors.primary, size: 40),
        const Gap(16),
        Text(
          _statusLabel(status),
          style: context.font.titleMedium?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(8),
        Text(
          '$amountSat sats',
          style: context.font.displaySmall?.copyWith(
            color: context.appColors.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Gap(24),
        DetailsTable(
          items: [
            DetailsTableItem(
              label: 'Status',
              displayValue: _statusLabel(status),
            ),
            DetailsTableItem(
              label: status == InvoiceStatus.partiallyPaid
                  ? 'Remaining'
                  : 'Amount',
              displayValue: '$amountSat sats',
            ),
            DetailsTableItem(
              label: 'Invoice URL',
              displayValue: resolvedShareUrl,
              copyValue: resolvedShareUrl,
              displayWidget: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openShareUrl(context, resolvedShareUrl),
                child: Text(
                  resolvedShareUrl,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (snapshot.recipientName != null)
              DetailsTableItem(
                label: 'Recipient',
                displayValue: snapshot.recipientName,
              ),
            if (snapshot.publicDescription != null)
              DetailsTableItem(
                label: 'Description',
                displayValue: snapshot.publicDescription,
              ),
            if (snapshot.invoiceNumber != null)
              DetailsTableItem(
                label: 'Invoice number',
                displayValue: snapshot.invoiceNumber,
                copyValue: snapshot.invoiceNumber,
              ),
            if (snapshot.createdAt != null)
              DetailsTableItem(
                label: 'Created',
                displayValue: dateFormat.format(snapshot.createdAt!.toLocal()),
              ),
            if (snapshot.paidAt != null)
              DetailsTableItem(
                label: 'Paid',
                displayValue: dateFormat.format(snapshot.paidAt!.toLocal()),
              ),
            DetailsTableItem(
              label: 'Expires',
              displayValue: status == InvoiceStatus.unpaid
                  ? null
                  : dateFormat.format(snapshot.expiresAt.toLocal()),
              displayWidget: status == InvoiceStatus.unpaid
                  ? Countdown(
                      until: snapshot.expiresAt,
                      format: CountdownFormat.dhm,
                      onTimeout: () {
                        context.read<InvoiceDetailCubit>().refresh();
                      },
                    )
                  : null,
            ),
            if (snapshot.paidVia != null)
              DetailsTableItem(
                label: 'Paid via',
                displayValue: _paymentMethodLabel(snapshot.paidVia!.value),
              ),
            if (snapshot.paidAmountSat != null)
              DetailsTableItem(
                label: 'Paid amount',
                displayValue: '${snapshot.paidAmountSat} sats',
              ),
          ],
        ),
        if (status == InvoiceStatus.unpaid) ...[
          const Gap(24),
          SizedBox(
            width: double.infinity,
            child: BBButton.big(
              label: state.isCancelling ? 'Cancelling...' : 'Cancel invoice',
              disabled: state.isBusy,
              onPressed: () => _confirmCancel(context),
              bgColor: context.appColors.transparent,
              textColor: context.appColors.onSurface,
              outlined: true,
              borderColor: context.appColors.onSurface,
            ),
          ),
        ],
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
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final cancelResult = await context.read<InvoiceDetailCubit>().cancel();
    if (!context.mounted) return;
    if (cancelResult != null) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openShareUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      SnackBarUtils.showSnackBar(context, 'Could not open invoice URL');
    }
  }

  String _statusLabel(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.inProgress => 'In progress',
      InvoiceStatus.partiallyPaid => 'Partially paid',
      _ => StringFormatting.capitalize(status.value),
    };
  }

  IconData _statusIcon(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.paid => Icons.check_circle_outline,
      InvoiceStatus.cancelled => Icons.cancel_outlined,
      InvoiceStatus.expired => Icons.schedule_outlined,
      InvoiceStatus.underpaid || InvoiceStatus.overpaid => Icons.error_outline,
      _ => Icons.receipt_long_outlined,
    };
  }

  String _paymentMethodLabel(String value) {
    return switch (value) {
      'ln' || 'lightning' => 'Lightning',
      'btc' || 'bitcoin' => 'Bitcoin',
      'liquid' => 'Liquid',
      'mixed' => 'Mixed',
      _ => StringFormatting.capitalize(value),
    };
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
