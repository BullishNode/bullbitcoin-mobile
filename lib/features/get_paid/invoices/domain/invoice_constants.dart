const invoicePublicDescriptionMaxBytes = 1000;
const invoiceRecipientNameMaxBytes = 100;
const invoiceNumberMaxBytes = 50;
const invoiceMaxFiatAmountMinor = 1000000000;

const invoiceSupportedFiatCurrencies = {
  'USD',
  'CAD',
  'EUR',
  'CRC',
  'MXN',
  'ARS',
  'COP',
  'INR',
};

int invoiceFiatCurrencyPrecision(String currency) {
  return switch (currency.trim().toUpperCase()) {
    'COP' => 0,
    _ => 2,
  };
}

String invoiceFiatMinorToMajorString(int amount, String currency) {
  final precision = invoiceFiatCurrencyPrecision(currency);
  if (precision == 0) return amount.toString();
  final factor = _minorUnitFactor(precision);
  final major = amount ~/ factor;
  final minor = (amount % factor).toString().padLeft(precision, '0');
  return '$major.$minor';
}

int invoiceMajorToMinorUnitFactor(String currency) {
  return _minorUnitFactor(invoiceFiatCurrencyPrecision(currency));
}

int _minorUnitFactor(int precision) {
  var factor = 1;
  for (var i = 0; i < precision; i++) {
    factor *= 10;
  }
  return factor;
}
