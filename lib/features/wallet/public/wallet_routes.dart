/// Stable route names and paths exposed by the wallet feature.
enum WalletRoute {
  walletHome('/wallet'),
  walletDetail('/wallet/:walletId');

  const WalletRoute(this.path);

  final String path;
}
