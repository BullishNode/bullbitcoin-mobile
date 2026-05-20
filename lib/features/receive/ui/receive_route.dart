enum ReceiveRoute {
  receiveBitcoin('/receive/bitcoin'),
  receiveLightning('/receive/lightning'),
  receiveLiquid('/receive/liquid'),
  bitcoinAmount('amount'),
  lightningAmount('amount'),
  liquidAmount('amount'),
  lightningQr('qr'),
  payjoinInProgress('payjoin'),
  lightningPaymentInProgress('in-progress'),
  lightningPaymentReceived('received');

  final String path;

  const ReceiveRoute(this.path);
}
