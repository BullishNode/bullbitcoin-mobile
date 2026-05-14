import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';

class InvoiceStatusSnapshot {
  final InvoiceId invoiceId;
  final InvoiceStatus status;
  final String pricingMode;
  final String settlementStatus;
  final int amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final int remainingAmountSat;
  final int paymentToleranceSat;
  final int? rateMinorPerBtc;
  final String? publicDescription;
  final String? recipientName;
  final String? invoiceNumber;
  final DateTime? createdAt;
  final DateTime rateLocksUntil;
  final DateTime expiresAt;
  final PaymentMethod? paidVia;
  final DateTime? paidAt;
  final int? paidAmountSat;
  final String? lightningPr;
  final String? liquidAddress;
  final String? bitcoinAddress;
  final String? bitcoinChainAddress;
  final String? bitcoinChainBip21;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final InvoiceUrl? shareUrl;

  const InvoiceStatusSnapshot({
    required this.invoiceId,
    required this.status,
    required this.pricingMode,
    required this.settlementStatus,
    required this.amountSat,
    required this.fiatAmountMinor,
    required this.fiatCurrency,
    required this.remainingAmountSat,
    required this.paymentToleranceSat,
    required this.rateMinorPerBtc,
    required this.publicDescription,
    required this.recipientName,
    required this.invoiceNumber,
    required this.createdAt,
    required this.rateLocksUntil,
    required this.expiresAt,
    required this.paidVia,
    required this.paidAt,
    required this.paidAmountSat,
    required this.lightningPr,
    required this.liquidAddress,
    required this.bitcoinAddress,
    required this.bitcoinChainAddress,
    required this.bitcoinChainBip21,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.shareUrl,
  });
}
