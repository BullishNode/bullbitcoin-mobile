import 'package:bb_mobile/core/errors/bull_exception.dart';

class WalletLabelReservationPolicy {
  final List<String> reservedLabels;

  const WalletLabelReservationPolicy({this.reservedLabels = const []});

  bool isReserved(String label) {
    final normalized = label.trim().toLowerCase();

    return reservedLabels.any(
      (reservedLabel) => reservedLabel.toLowerCase() == normalized,
    );
  }

  void throwIfReserved(String? label) {
    if (label == null) return;
    if (!isReserved(label)) return;

    throw ReservedWalletLabelException();
  }
}

class ReservedWalletLabelException extends BullException {
  ReservedWalletLabelException() : super('This wallet label is reserved');
}
