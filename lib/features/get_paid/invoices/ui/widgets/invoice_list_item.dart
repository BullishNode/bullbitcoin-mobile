import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/text/text.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/invoice_constants.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:timeago/timeago.dart' as timeago;

class InvoiceListItem extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;

  const InvoiceListItem({
    super.key,
    required this.invoice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: context.appColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                border: Border.all(color: context.appColors.border),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Icon(Icons.receipt_long, color: context.appColors.text),
            ),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BBText(_amountLabel(invoice), style: context.font.bodyLarge),
                  if (invoice.publicDescription != null) ...[
                    const Gap(4),
                    BBText(
                      invoice.publicDescription!,
                      style: context.font.labelSmall?.copyWith(
                        color: context.appColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context, invoice.status),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: BBText(
                    _statusLabel(invoice.status),
                    style: context.font.labelSmall?.copyWith(
                      color: _statusTextColor(context, invoice.status),
                    ),
                  ),
                ),
                const Gap(4),
                BBText(
                  timeago.format(invoice.createdAt),
                  style: context.font.labelSmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _amountLabel(Invoice invoice) {
    final fiatAmount = invoice.fiatAmountMinor;
    final fiatCurrency = invoice.fiatCurrency;
    if (fiatAmount != null && fiatCurrency != null) {
      return '${invoiceFiatMinorToMajorString(fiatAmount, fiatCurrency)} $fiatCurrency';
    }
    return '${invoice.amountSat} sats';
  }

  String _statusLabel(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.inProgress => 'in progress',
      InvoiceStatus.partiallyPaid => 'partially paid',
      _ => status.value,
    };
  }

  Color _statusColor(BuildContext context, InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.paid => context.appColors.success,
      InvoiceStatus.unpaid => context.appColors.border,
      InvoiceStatus.inProgress ||
      InvoiceStatus.partiallyPaid => context.appColors.warningContainer,
      InvoiceStatus.expired ||
      InvoiceStatus.cancelled => context.appColors.textMuted,
      InvoiceStatus.underpaid ||
      InvoiceStatus.overpaid => context.appColors.errorContainer,
    };
  }

  Color _statusTextColor(BuildContext context, InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.paid => context.appColors.onSurfaceFixed,
      InvoiceStatus.expired ||
      InvoiceStatus.cancelled => context.appColors.surface,
      _ => context.appColors.onSurface,
    };
  }
}
