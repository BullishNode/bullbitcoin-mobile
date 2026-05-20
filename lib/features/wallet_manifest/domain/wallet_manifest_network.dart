enum WalletManifestNetwork {
  bitcoin,
  testnet3,
  liquid,
  liquidTestnet;

  String get value => switch (this) {
    WalletManifestNetwork.bitcoin => 'bitcoin',
    WalletManifestNetwork.testnet3 => 'testnet3',
    WalletManifestNetwork.liquid => 'liquid',
    WalletManifestNetwork.liquidTestnet => 'liquid_testnet',
  };

  bool get isBitcoin =>
      this == WalletManifestNetwork.bitcoin ||
      this == WalletManifestNetwork.testnet3;

  bool get isLiquid =>
      this == WalletManifestNetwork.liquid ||
      this == WalletManifestNetwork.liquidTestnet;

  String get displaySuffix => isBitcoin ? 'BTC' : 'LBTC';

  static WalletManifestNetwork? tryParse(String? value) {
    return switch (value) {
      'bitcoin' => WalletManifestNetwork.bitcoin,
      'testnet3' => WalletManifestNetwork.testnet3,
      'liquid' => WalletManifestNetwork.liquid,
      'liquid_testnet' => WalletManifestNetwork.liquidTestnet,
      _ => null,
    };
  }
}
