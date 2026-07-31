/// A display currency the Point of Sale can settle its shown amounts in.
final class DisplayCurrency {
  final String code;
  final int precision;

  const DisplayCurrency({required this.code, required this.precision});
}
