import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';

class InvoiceStatusSnapshot {
  final InvoiceId invoiceId;
  final InvoiceStatus status;
  final int amountSat;
  final int? rateMinorPerBtc;
  final DateTime rateLocksUntil;
  final DateTime expiresAt;
  final PaymentMethod? paidVia;
  final DateTime? paidAt;
  final int? paidAmountSat;
  final String? lightningPr;
  final String? liquidAddress;
  final String? bitcoinAddress;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final bool rateStale;

  const InvoiceStatusSnapshot({
    required this.invoiceId,
    required this.status,
    required this.amountSat,
    required this.rateMinorPerBtc,
    required this.rateLocksUntil,
    required this.expiresAt,
    required this.paidVia,
    required this.paidAt,
    required this.paidAmountSat,
    required this.lightningPr,
    required this.liquidAddress,
    required this.bitcoinAddress,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.rateStale,
  });
}
