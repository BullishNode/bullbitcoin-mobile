import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locks external receive wallet derivation paths', () {
    expect(ExternalReceiveWalletBip85Index.lightningAddress, 75);
    expect(ExternalReceiveWalletBip85Index.paymentPage, 76);
    expect(ExternalReceiveWalletBip85Index.btcpay, 77);
    expect(ExternalReceiveWalletPurpose.lightningAddress.bip85Index, 75);
    expect(ExternalReceiveWalletPurpose.paymentPage.bip85Index, 76);
    expect(ExternalReceiveWalletPurpose.btcpay.bip85Index, 77);
  });

  test('locks external receive wallet labels', () {
    expect(
      ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
      'Lightning Address-LBTC',
    );
    expect(
      ReservedExternalReceiveWalletLabel.paymentPageLiquid,
      'Payment Page-LBTC',
    );
    expect(ReservedExternalReceiveWalletLabel.btcpayLiquid, 'BTCPay-LBTC');
    expect(ReservedExternalReceiveWalletLabel.btcpayBitcoin, 'BTCPay-BTC');
    expect(
      ExternalReceiveWalletPurpose.lightningAddress.walletLabel,
      'Lightning Address-LBTC',
    );
    expect(
      ExternalReceiveWalletPurpose.paymentPage.walletLabel,
      'Payment Page-LBTC',
    );
    expect(ExternalReceiveWalletPurpose.btcpay.walletLabel, 'BTCPay-LBTC');
  });

  test('maps account keys to network-specific labels', () {
    final lbtc = ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
      isTestnet: false,
    );
    final btc = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
      isTestnet: false,
    );

    expect(lbtc.walletLabel, 'BTCPay-LBTC');
    expect(btc.walletLabel, 'BTCPay-BTC');
    expect(lbtc.bip85Index, 77);
    expect(btc.bip85Index, 77);
  });

  test('rejects Bitcoin account keys for non-BTCPay purposes', () {
    expect(
      () => ExternalReceiveWalletPurpose.lightningAddress.bitcoinAccountKey(
        isTestnet: false,
      ),
      throwsUnsupportedError,
    );
    expect(
      () => ExternalReceiveWalletPurpose.paymentPage.bitcoinAccountKey(
        isTestnet: false,
      ),
      throwsUnsupportedError,
    );
  });
}
