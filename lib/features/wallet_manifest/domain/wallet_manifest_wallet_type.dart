enum WalletManifestWalletType {
  lightningAddress,
  paymentPage,
  btcpay,
  manual;

  String get value => switch (this) {
    WalletManifestWalletType.lightningAddress => 'lightning_address',
    WalletManifestWalletType.paymentPage => 'payment_page',
    WalletManifestWalletType.btcpay => 'btcpay',
    WalletManifestWalletType.manual => 'manual',
  };

  static WalletManifestWalletType? tryParse(String? value) {
    return switch (value) {
      'lightning_address' => WalletManifestWalletType.lightningAddress,
      'payment_page' => WalletManifestWalletType.paymentPage,
      'btcpay' => WalletManifestWalletType.btcpay,
      'manual' => WalletManifestWalletType.manual,
      _ => null,
    };
  }
}
