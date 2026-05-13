class InvoiceId {
  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final String value;

  InvoiceId(String value) : value = _validate(value);

  static String _validate(String value) {
    if (!_uuidRegex.hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'must be a UUID');
    }
    return value;
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
