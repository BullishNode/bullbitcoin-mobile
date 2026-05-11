enum InvoiceStatus {
  unpaid('unpaid'),
  inProgress('in_progress'),
  paid('paid'),
  underpaid('underpaid'),
  overpaid('overpaid'),
  expired('expired'),
  cancelled('cancelled');

  final String value;

  const InvoiceStatus(this.value);

  factory InvoiceStatus.fromValue(String value) {
    return InvoiceStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError.value(value, 'value'),
    );
  }
}
