/// Currency metadata supported when creating merchant invoices.
final class InvoiceSupportedCurrency {
  final String code;
  final int precision;

  const InvoiceSupportedCurrency({required this.code, required this.precision});
}

final class InvoiceSupportedCurrencies {
  final List<InvoiceSupportedCurrency> currencies;

  const InvoiceSupportedCurrencies({required this.currencies});
}
