import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';

class Invoice {
  final InvoiceId id;
  final String? nymOwner;
  final String origin;
  final InvoiceStatus status;
  final int amountSat;
  final int remainingAmountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? recipientName;
  final String? invoiceNumber;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final String? bitcoinAddress;
  final String? liquidAddress;
  final DateTime createdAt;
  final DateTime expiresAt;
  final PaymentMethod? paidVia;
  final DateTime? paidAt;
  final int? paidAmountSat;
  final InvoiceUrl? shareUrl;

  const Invoice({
    required this.id,
    required this.nymOwner,
    required this.origin,
    required this.status,
    required this.amountSat,
    required this.remainingAmountSat,
    required this.fiatAmountMinor,
    required this.fiatCurrency,
    required this.publicDescription,
    required this.recipientName,
    required this.invoiceNumber,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.bitcoinAddress,
    required this.liquidAddress,
    required this.createdAt,
    required this.expiresAt,
    required this.paidVia,
    required this.paidAt,
    required this.paidAmountSat,
    required this.shareUrl,
  });

  bool isPayable(DateTime now) {
    if (!expiresAt.isAfter(now)) return false;
    return status == InvoiceStatus.unpaid ||
        status == InvoiceStatus.partiallyPaid;
  }

  bool get isCancellable => status == InvoiceStatus.unpaid;

  Duration timeUntilExpiry(DateTime now) {
    final remaining = expiresAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  InvoiceUrl publicUrlFor({required String domain}) {
    return invoicePublicUrlFor(nym: nymOwner, id: id, domain: domain);
  }
}

InvoiceUrl invoicePublicUrlFor({
  required String? nym,
  required InvoiceId id,
  required String domain,
}) {
  final path = nym == null ? '/invoice/$id' : '/$nym/i/$id';
  return InvoiceUrl('https://$domain$path');
}
