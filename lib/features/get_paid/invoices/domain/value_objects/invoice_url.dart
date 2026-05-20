class InvoiceUrl {
  final String value;

  InvoiceUrl(String value) : value = _validate(value);

  static String _validate(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must be an HTTPS URL');
    }
    return value;
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceUrl &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
