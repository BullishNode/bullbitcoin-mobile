import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/application/usecases/cancel_invoice_usecase.dart';
import 'package:bb_mobile/features/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/invoices/application/usecases/get_invoice_usecase.dart';
import 'package:bb_mobile/features/invoices/application/usecases/get_merchant_invoice_usecase.dart';
import 'package:bb_mobile/features/invoices/application/usecases/list_invoices_usecase.dart';
import 'package:bb_mobile/features/invoices/application/usecases/list_invoice_fallback_supervision_usecase.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_commands.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_fallback_supervision.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_quote.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_results.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_supported_currency.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/payment_method.dart';
import 'package:bb_mobile/features/invoices/domain/usecases/get_invoice_supported_currencies_usecase.dart';
import 'package:bb_mobile/features/invoices/domain/usecases/get_private_invoice_link_usecase.dart';
import 'package:bb_mobile/features/invoices/domain/invoices_failure.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/private_invoice_link.dart';
import 'package:meta/meta.dart';

export 'package:bb_mobile/features/invoices/domain/entities/invoice_commands.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_results.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_supported_currency.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_fallback_supervision.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_payment_event.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_payment_summary.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_payer_amount.dart';
export 'package:bb_mobile/features/invoices/domain/entities/private_invoice_presentation.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_status_snapshot.dart';
export 'package:bb_mobile/features/invoices/domain/entities/invoice_quote.dart';
export 'package:bb_mobile/features/invoices/domain/invoices_failure.dart';
export 'package:bb_mobile/features/invoices/domain/primitives/invoice_status.dart';
export 'package:bb_mobile/features/invoices/domain/primitives/payment_method.dart';
export 'package:bb_mobile/features/invoices/domain/value_objects/invoice_id.dart';
export 'package:bb_mobile/features/invoices/domain/value_objects/private_invoice_link.dart';

/// The public entry to the invoices feature. Thin delegations to the usecases;
/// `supportedCurrencies` reuses the shared bullnym currency plumbing.
class InvoicesFacade {
  final CreateInvoiceUsecase _create;
  final CancelInvoiceUsecase _cancel;
  final ListInvoicesUsecase _list;
  final ListInvoiceFallbackSupervisionUsecase _listFallbackSupervision;
  final GetInvoiceUsecase _getStatus;
  final GetMerchantInvoiceUsecase _getMerchantInvoice;
  final GetPrivateInvoiceLinkUsecase _getPrivateLink;
  final GetInvoiceSupportedCurrenciesUsecase _getSupportedCurrencies;

  const InvoicesFacade({
    required this._create,
    required this._cancel,
    required this._list,
    required this._listFallbackSupervision,
    required this._getStatus,
    required this._getMerchantInvoice,
    required this._getPrivateLink,
    required this._getSupportedCurrencies,
  });

  @useResult
  Future<Result<CreateInvoiceResult, InvoicesFailure>> create(
    CreateInvoiceCommand command,
  ) => _create.execute(command);

  @useResult
  Future<Result<CreateInvoiceResult?, InvoicesFailure>> resumeCreate() =>
      _create.resumePending();

  @useResult
  Future<Result<CancelInvoiceResult, InvoicesFailure>> cancel(
    CancelInvoiceCommand command,
  ) => _cancel.execute(command);

  @useResult
  Future<Result<ListInvoicesResult, InvoicesFailure>> list(
    ListInvoicesCommand command,
  ) => _list.execute(command);

  @useResult
  Future<Result<Invoice?, InvoicesFailure>> merchantInvoice(
    InvoiceId invoiceId,
  ) => _getMerchantInvoice.execute(invoiceId);

  @useResult
  Future<Result<InvoiceFallbackOverview, InvoicesFailure>>
  fallbackSupervision() => _listFallbackSupervision.execute();

  @useResult
  Future<Result<InvoiceStatusSnapshot, InvoicesFailure>> status(
    InvoiceId invoiceId,
  ) => _getStatus.execute(invoiceId);

  Future<PrivateInvoiceLink?> privateLink(InvoiceId invoiceId) =>
      _getPrivateLink.execute(invoiceId);

  @useResult
  Future<Result<InvoiceQuote, InvoicesFailure>> quote({
    required InvoiceId invoiceId,
    required PaymentMethod rail,
  }) => _getStatus.quote(invoiceId: invoiceId, rail: rail);

  @useResult
  Future<Result<InvoiceSupportedCurrencies, InvoicesFailure>>
  supportedCurrencies() => _getSupportedCurrencies.execute();

  @override
  String toString() => 'InvoicesFacade';
}
