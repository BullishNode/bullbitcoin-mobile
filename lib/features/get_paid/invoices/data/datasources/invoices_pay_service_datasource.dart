import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_client.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/bullnym_errors.dart';
import 'package:bb_mobile/features/get_paid/shared/bullnym/models/bullnym_models.dart';

class InvoicesPayServiceDatasource implements InvoicesPayServicePort {
  final BullnymClient _bullnymClient;

  const InvoicesPayServiceDatasource({required BullnymClient bullnymClient})
    : _bullnymClient = bullnymClient;

  @override
  Future<CreateInvoiceResult> createInvoice({
    required CreateInvoiceCommand command,
    required NostrKeychainHandle handle,
    required String? bitcoinAddress,
    required String? liquidAddress,
  }) async {
    try {
      final dto = await _bullnymClient.createInvoice(
        handle: handle,
        nym: command.linkToPageNym,
        amountSat: command.amountSat,
        fiatAmountMinor: command.fiatAmountMinor,
        fiatCurrency: command.fiatCurrency,
        publicDescription: command.publicDescription,
        recipientName: command.recipientName,
        invoiceNumber: command.invoiceNumber,
        acceptBtc: command.acceptBtc,
        acceptLn: command.acceptLn,
        acceptLiquid: command.acceptLiquid,
        bitcoinAddress: bitcoinAddress,
        liquidAddress: liquidAddress,
        expiresAt: command.expiresAt,
      );
      return dto.toCreateResult();
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    } on ArgumentError {
      throw const InvoicesUnexpectedError('Unexpected invoice response');
    }
  }

  @override
  Future<CancelInvoiceResult> cancelInvoice({
    required CancelInvoiceCommand command,
    required NostrKeychainHandle handle,
  }) async {
    try {
      final dto = await _bullnymClient.cancelInvoice(
        handle: handle,
        invoiceId: command.invoiceId.value,
        nym: command.nymOwner,
      );
      return dto.toCancelResult();
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    } on ArgumentError {
      throw const InvoicesUnexpectedError('Unexpected invoice response');
    }
  }

  @override
  Future<List<Invoice>> listInvoices({
    required ListInvoicesCommand command,
    required NostrKeychainHandle handle,
  }) async {
    try {
      final dto = await _bullnymClient.listInvoices(
        handle: handle,
        sinceUnix: _toUnixSecondsOrNull(command.since),
        limit: command.limit,
        status: command.status?.value,
      );
      return dto.invoices.map((invoice) => invoice.toEntity()).toList();
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    } on ArgumentError {
      throw const InvoicesUnexpectedError('Unexpected invoice response');
    }
  }

  @override
  Future<InvoiceStatusSnapshot> getInvoiceStatus({
    required InvoiceId id,
  }) async {
    try {
      final dto = await _bullnymClient.getInvoiceStatus(invoiceId: id.value);
      return dto.toStatusSnapshot(id);
    } on BullnymException catch (e) {
      throw _mapBullnymError(e);
    } on ArgumentError {
      throw const InvoicesUnexpectedError('Unexpected invoice response');
    }
  }

  InvoicesApplicationError _mapBullnymError(BullnymException e) {
    return InvoicesApplicationError.fromCode(code: e.code, reason: e.reason);
  }
}

DateTime _fromUnixSeconds(int seconds) {
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

int? _toUnixSecondsOrNull(DateTime? dateTime) {
  if (dateTime == null) return null;
  return dateTime.toUtc().millisecondsSinceEpoch ~/ 1000;
}

PaymentMethod? _paymentMethodOrNull(String? value) {
  if (value == null) return null;
  return PaymentMethod.fromValue(value);
}

extension on BullnymCreateInvoiceResponseDto {
  CreateInvoiceResult toCreateResult() {
    return CreateInvoiceResult(
      invoiceId: InvoiceId(invoiceId),
      shareUrl: InvoiceUrl(shareUrl),
    );
  }
}

extension on BullnymCancelInvoiceResponseDto {
  CancelInvoiceResult toCancelResult() {
    return CancelInvoiceResult(
      invoiceId: InvoiceId(invoiceId),
      status: InvoiceStatus.fromValue(status),
    );
  }
}

extension on BullnymInvoiceListItemDto {
  Invoice toEntity() {
    return Invoice(
      id: InvoiceId(id),
      nymOwner: nymOwner,
      origin: origin,
      status: InvoiceStatus.fromValue(status),
      amountSat: amountSat,
      fiatAmountMinor: fiatAmountMinor,
      fiatCurrency: fiatCurrency,
      publicDescription: publicDescription,
      recipientName: recipientName,
      invoiceNumber: invoiceNumber,
      acceptBtc: acceptBtc,
      acceptLn: acceptLn,
      acceptLiquid: acceptLiquid,
      bitcoinAddress: bitcoinAddress,
      liquidAddress: liquidAddress,
      createdAt: _fromUnixSeconds(createdAtUnix),
      expiresAt: _fromUnixSeconds(expiresAtUnix),
      paidVia: _paymentMethodOrNull(paidVia),
      paidAt: paidAtUnix == null ? null : _fromUnixSeconds(paidAtUnix!),
      paidAmountSat: paidAmountSat,
      shareUrl: null,
    );
  }
}

extension on BullnymInvoiceStatusDto {
  InvoiceStatusSnapshot toStatusSnapshot(InvoiceId invoiceId) {
    return InvoiceStatusSnapshot(
      invoiceId: invoiceId,
      status: InvoiceStatus.fromValue(status),
      amountSat: amountSat,
      rateMinorPerBtc: rateMinorPerBtc,
      rateLocksUntil: _fromUnixSeconds(rateLocksUntilUnix),
      expiresAt: _fromUnixSeconds(expiresAtUnix),
      paidVia: _paymentMethodOrNull(paidVia),
      paidAt: paidAtUnix == null ? null : _fromUnixSeconds(paidAtUnix!),
      paidAmountSat: paidAmountSat,
      lightningPr: lightningPr,
      liquidAddress: liquidAddress,
      bitcoinAddress: bitcoinAddress,
      acceptBtc: acceptBtc,
      acceptLn: acceptLn,
      acceptLiquid: acceptLiquid,
      rateStale: rateStale,
    );
  }
}
