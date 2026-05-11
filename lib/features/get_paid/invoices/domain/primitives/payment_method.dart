enum PaymentMethod {
  btc('bitcoin'),
  lightning('lightning'),
  liquid('liquid');

  final String value;

  const PaymentMethod(this.value);

  factory PaymentMethod.fromValue(String value) {
    return PaymentMethod.values.firstWhere(
      (method) => method.value == value,
      orElse: () => throw ArgumentError.value(value, 'value'),
    );
  }
}
