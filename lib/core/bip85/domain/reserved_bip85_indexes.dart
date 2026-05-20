class ReservedBip85Indexes {
  const ReservedBip85Indexes._();

  static const lightningAddress = 75;
  static const paymentPage = 76;
  static const btcpay = 77;

  static const manuallyUnavailable = {lightningAddress, paymentPage, btcpay};
}
