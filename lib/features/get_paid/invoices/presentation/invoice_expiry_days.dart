const invoiceMinExpiryDays = 1;
const invoiceMaxExpiryDays = 7;

int invoiceExpiryDaysFrom({
  required DateTime expiresAt,
  required DateTime now,
}) {
  final remaining = expiresAt.difference(now);
  if (remaining <= Duration.zero) return invoiceMinExpiryDays;
  return (remaining.inSeconds / Duration.secondsPerDay)
      .ceil()
      .clamp(invoiceMinExpiryDays, invoiceMaxExpiryDays)
      .toInt();
}

DateTime invoiceExpiresAtForDays({required int days, required DateTime now}) {
  return now.add(
    Duration(days: days.clamp(invoiceMinExpiryDays, invoiceMaxExpiryDays)),
  );
}
