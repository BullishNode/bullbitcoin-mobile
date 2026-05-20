import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/wallet/ui/widgets/wallet_cards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home list hides external receive wallets configured as hidden', () {
    final visible = WalletCards.visibleWallets(
      wallets: [
        _wallet('Instant Payments', id: 'default-liquid'),
        _wallet('Renamed Lightning Address', id: 'la-wallet'),
        _wallet('Renamed Payment Page', id: 'payment-wallet'),
        _wallet('Renamed BTCPay', id: 'btcpay-lbtc'),
        _wallet(
          'Renamed BTCPay BTC',
          id: 'btcpay-btc',
          network: Network.bitcoinMainnet,
        ),
      ],
      localSignersOnly: false,
      externalReceiveWalletIds: ExternalReceiveWalletIds(
        purposeByWalletId: {
          'la-wallet': ExternalReceiveWalletPurpose.lightningAddress,
          'payment-wallet': ExternalReceiveWalletPurpose.paymentPage,
          'btcpay-lbtc': ExternalReceiveWalletPurpose.btcpay,
          'btcpay-btc': ExternalReceiveWalletPurpose.btcpay,
        },
        hiddenOnHomeWalletIds: {'payment-wallet', 'btcpay-lbtc'},
      ),
    );

    expect(visible.map((w) => w.label), [
      'Instant Payments',
      'Renamed Lightning Address',
      'Renamed BTCPay BTC',
    ]);
  });

  test('home list hides Lightning Address wallet by hidden wallet id', () {
    final visible = WalletCards.visibleWallets(
      wallets: [
        _wallet('Instant Payments'),
        _wallet(ReservedExternalReceiveWalletLabel.lightningAddressLiquid),
        _wallet(ReservedExternalReceiveWalletLabel.paymentPageLiquid),
      ],
      localSignersOnly: false,
      externalReceiveWalletIds: ExternalReceiveWalletIds(
        purposeByWalletId: {
          ReservedExternalReceiveWalletLabel.lightningAddressLiquid:
              ExternalReceiveWalletPurpose.lightningAddress,
          ReservedExternalReceiveWalletLabel.paymentPageLiquid:
              ExternalReceiveWalletPurpose.paymentPage,
        },
        hiddenOnHomeWalletIds: {
          ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
          ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        },
      ),
    );

    expect(visible.map((w) => w.label), ['Instant Payments']);
  });

  test(
    'home list does not classify reserved-looking labels without manifest ids',
    () {
      final visible = WalletCards.visibleWallets(
        wallets: [
          _wallet(ReservedExternalReceiveWalletLabel.paymentPageLiquid),
          _wallet(ReservedExternalReceiveWalletLabel.btcpayLiquid),
        ],
        localSignersOnly: false,
        externalReceiveWalletIds: ExternalReceiveWalletIds.empty,
      );

      expect(visible.map((w) => w.label), [
        ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        ReservedExternalReceiveWalletLabel.btcpayLiquid,
      ]);
    },
  );

  test('home list preserves known ids when classification later fails', () {
    final visible = WalletCards.visibleWallets(
      wallets: [
        _wallet('Instant Payments', id: 'default-liquid'),
        _wallet('Renamed Lightning Address', id: 'la-wallet'),
        _wallet('Renamed Payment Page', id: 'payment-wallet'),
      ],
      localSignersOnly: false,
      externalReceiveWalletIds: ExternalReceiveWalletIds(
        purposeByWalletId: {
          'la-wallet': ExternalReceiveWalletPurpose.lightningAddress,
          'payment-wallet': ExternalReceiveWalletPurpose.paymentPage,
        },
        hiddenOnHomeWalletIds: {'payment-wallet'},
      ),
    );

    expect(visible.map((w) => w.label), [
      'Instant Payments',
      'Renamed Lightning Address',
    ]);
  });
}

Wallet _wallet(
  String label, {
  String? id,
  Network network = Network.liquidMainnet,
  bool isDefault = false,
}) => Wallet(
  origin: id ?? label,
  label: label,
  network: network,
  isDefault: isDefault || label == 'Instant Payments',
  xpubFingerprint: '',
  scriptType: ScriptType.bip84,
  xpub: '',
  externalPublicDescriptor: '',
  internalPublicDescriptor: '',
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: BigInt.zero,
);
