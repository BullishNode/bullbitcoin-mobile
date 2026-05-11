import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';

class CreateInvoiceCommand {
  static const Duration minExpiry = Duration(seconds: 60);
  static const Duration maxExpiry = Duration(days: 7);

  final int? amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? recipientName;
  final String? invoiceNumber;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final DateTime expiresAt;
  final String? linkToPageNym;
  final String? privateMemo;

  CreateInvoiceCommand({
    required this.amountSat,
    required this.fiatAmountMinor,
    required this.fiatCurrency,
    required this.publicDescription,
    required this.recipientName,
    required this.invoiceNumber,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.expiresAt,
    required this.linkToPageNym,
    required this.privateMemo,
    DateTime? now,
  }) {
    _validate(now ?? DateTime.now().toUtc());
  }

  void _validate(DateTime now) {
    final hasSatAmount = amountSat != null;
    final hasFiatAmount = fiatAmountMinor != null || fiatCurrency != null;
    if (hasSatAmount == hasFiatAmount) {
      throw const InvoicesValidationError(
        'invoice amount must be sats or fiat, but not both',
      );
    }
    if (amountSat != null && amountSat! <= 0) {
      throw const InvoicesValidationError('amountSat must be positive');
    }
    if (fiatAmountMinor != null && fiatAmountMinor! <= 0) {
      throw const InvoicesValidationError('fiatAmountMinor must be positive');
    }
    if (fiatAmountMinor != null && fiatCurrency == null) {
      throw const InvoicesValidationError(
        'fiatCurrency is required with fiatAmountMinor',
      );
    }
    if (fiatAmountMinor == null && fiatCurrency != null) {
      throw const InvoicesValidationError(
        'fiatAmountMinor is required with fiatCurrency',
      );
    }
    if (!acceptBtc && !acceptLn && !acceptLiquid) {
      throw const InvoicesValidationError(
        'at least one payment rail must be enabled',
      );
    }
    final expiry = expiresAt.toUtc().difference(now.toUtc());
    if (expiry < minExpiry || expiry > maxExpiry) {
      throw const InvoicesValidationError(
        'expiresAt must be between 60 seconds and 7 days',
      );
    }
  }
}
