import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart'
    show BullnymAuthSigner;
import 'package:bb_mobile/features/invoices/domain/entities/invoice_commands.dart';
import 'package:bb_mobile/features/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/invoices/domain/invoices_failure.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/invoice_id.dart';
import 'package:meta/meta.dart';

/// Reads one authenticated merchant invoice from the signed paginated
/// projection. It deliberately bypasses fallback-supervision enrichment: an
/// incident-only synthetic row must never stand in for authoritative payment
/// accounting.
class GetMerchantInvoiceUsecase {
  const GetMerchantInvoiceUsecase(this._identity, this._payService);

  final InvoicesIdentityPort _identity;
  final InvoicesPayServicePort _payService;

  @useResult
  Future<Result<Invoice?, InvoicesFailure>> execute(InvoiceId invoiceId) async {
    final signerResult = await _identity.getSigningHandle();
    return switch (signerResult) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => _find(value, invoiceId),
    };
  }

  Future<Result<Invoice?, InvoicesFailure>> _find(
    BullnymAuthSigner signer,
    InvoiceId invoiceId,
  ) async {
    var page = 1;
    while (true) {
      final result = await _payService.listInvoices(
        signer: signer,
        command: ListInvoicesCommand(page: page),
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          for (final invoice in value.invoices) {
            if (invoice.id == invoiceId) return Ok(invoice);
          }
          if (!value.hasMore || value.invoices.isEmpty) return const Ok(null);
      }
      page++;
    }
  }
}
