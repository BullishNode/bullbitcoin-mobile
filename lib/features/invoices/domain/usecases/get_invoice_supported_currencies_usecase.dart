import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/invoices/domain/bullnym_failure_mapping.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_supported_currency.dart';
import 'package:bb_mobile/features/invoices/domain/invoices_failure.dart';

/// Maps the payment service's public currency contract into invoice-owned
/// values at the invoices domain boundary.
final class GetInvoiceSupportedCurrenciesUsecase {
  final BullnymFacade _bullnym;

  const GetInvoiceSupportedCurrenciesUsecase(this._bullnym);

  Future<Result<InvoiceSupportedCurrencies, InvoicesFailure>> execute() async {
    final result = await _bullnym.getSupportedCurrencies();
    return result
        .map(
          (value) => InvoiceSupportedCurrencies(
            currencies: [
              for (final currency in value.currencies)
                InvoiceSupportedCurrency(
                  code: currency.code,
                  precision: currency.precision,
                ),
            ],
          ),
        )
        .mapErr(mapBullnymFailureToInvoices);
  }
}
