import 'package:bb_mobile/core/exchange/domain/entity/order.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:intl/intl.dart';

class FormatAmount {
  static String sats(int satsAmount) {
    final currencyFormatter = NumberFormat.currency(
      name: 'sats',
      decimalDigits: 0,
      customPattern: '#,##0 ¤',
    );
    return currencyFormatter.format(satsAmount);
  }

  /// Format a fractional satoshi count for preview display (rate × vsize
  /// products etc.). Shows up to 2 decimals, drops trailing zeros, and
  /// kills IEEE 754 noise like `78.96000000000001` → `78.96`. The actual
  /// broadcast fee is always an integer sat — this is a preview format.
  static String satsApprox(num satsAmount) {
    return NumberFormat('#,##0.##').format(satsAmount);
  }

  static String btc(double btcAmount) {
    const maxDecimals = 8;
    if (btcAmount >= 0.1 || btcAmount == 0.0) {
      // Format without trailing zero's with a maximum of 8 if the amount is
      // bigger or equal to 0.1 BTC. Also 0 should be formatted without trailing
      // zero's.
      final amountFormatter = NumberFormat('0.${'#' * maxDecimals}');
      final formattedAmount = amountFormatter.format(btcAmount);
      final amountWithCurrencyCode = '$formattedAmount ${BitcoinUnit.btc.code}';

      return amountWithCurrencyCode;
    } else {
      // Keep all decimal digits for lower amounts
      final currencyFormatter = NumberFormat.currency(
        name: 'BTC',
        decimalDigits: maxDecimals,
        customPattern: '#,##0.00000000 ¤',
      );
      final formatted = currencyFormatter.format(btcAmount);
      return formatted;
    }
  }

  static String fiat(
    double fiat,
    String currencyCode, {
    bool simpleFormat = false,
  }) {
    final decimals = FiatCurrency.tryFromCode(currencyCode)?.decimals ?? 2;
    final currencyFormatter = simpleFormat
        ? NumberFormat.simpleCurrency(
            name: currencyCode,
            decimalDigits: decimals,
          )
        : NumberFormat.currency(
            name: currencyCode,
            decimalDigits: decimals,
            customPattern: decimals == 0
                ? '#,##0 ¤'
                : '#,##0.${'0' * decimals} ¤',
          );

    return currencyFormatter.format(fiat);
  }

  /// Formats an integer minor-unit amount using the canonical exponent for the
  /// supported currency.
  static String fiatMinor(
    int minor,
    String currencyCode, {
    bool simpleFormat = false,
  }) {
    final currency = FiatCurrency.tryFromCode(currencyCode);
    if (currency == null) {
      throw ArgumentError.value(currencyCode, 'currencyCode');
    }
    final factor = _pow10(currency.decimals);
    return fiat(minor / factor, currency.code, simpleFormat: simpleFormat);
  }

  /// Integer-only, locale-independent minor-to-major formatting for CSV and
  /// other wire-like output. It never rounds through binary floating point.
  static String fiatMinorValue(int minor, String currencyCode) {
    final currency = FiatCurrency.tryFromCode(currencyCode);
    if (currency == null) {
      throw ArgumentError.value(currencyCode, 'currencyCode');
    }
    final decimals = currency.decimals;
    if (decimals == 0) return minor.toString();

    final factor = _pow10(decimals);
    final magnitude = minor.abs();
    final major = magnitude ~/ factor;
    final fraction = (magnitude % factor).toString().padLeft(decimals, '0');
    return '${minor < 0 ? '-' : ''}$major.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
