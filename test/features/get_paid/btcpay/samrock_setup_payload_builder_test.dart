import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = SamRockSetupPayloadBuilder();

  test('builds BTC, LBTC, and BTCLN payload entries', () {
    final payload = builder.build(
      request: _request('btc-chain,liquid-chain,btc-ln'),
      preparedWallets: PrepareBtcpayPairingWalletsResult(
        wallets: [
          PrepareBtcpayPairingWalletResult(
            network: BtcpayPairingWalletNetwork.bitcoin,
            accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
              isTestnet: false,
            ),
            created: false,
            wallet: _wallet(
              'BTCPay-BTC',
              network: Network.bitcoinMainnet,
              descriptor: 'wpkh([abcd1234/84h/0h/0h]xpub/0/*)#btc',
            ),
          ),
          PrepareBtcpayPairingWalletResult(
            network: BtcpayPairingWalletNetwork.liquid,
            accountKey: ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
              isTestnet: false,
            ),
            created: false,
            wallet: _wallet(
              'BTCPay-LBTC',
              network: Network.liquidMainnet,
              descriptor: 'ct(slip77(hex),elwpkh(xpub/0/*))#lbtc',
            ),
          ),
        ],
      ),
    );

    expect(payload['BTC'], {
      'Descriptor': 'wpkh([abcd1234/84h/0h/0h]xpub/0/*)#btc',
    });
    expect(payload['LBTC'], {
      'Descriptor': 'ct(slip77(hex),elwpkh(xpub/0/*))#lbtc',
    });
    expect(payload['BTCLN'], {
      'Type': 'Boltz',
      'LBTC': {'Descriptor': 'ct(slip77(hex),elwpkh(xpub/0/*))#lbtc'},
    });
  });

  test('uses the Liquid descriptor for Lightning-only setup', () {
    final payload = builder.build(
      request: _request('btc-ln'),
      preparedWallets: PrepareBtcpayPairingWalletsResult(
        wallets: [
          PrepareBtcpayPairingWalletResult(
            network: BtcpayPairingWalletNetwork.liquid,
            accountKey: ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
              isTestnet: false,
            ),
            created: false,
            wallet: _wallet(
              'BTCPay-LBTC',
              network: Network.liquidMainnet,
              descriptor: 'ct(slip77(hex),elwpkh(xpub/0/*))#lbtc',
            ),
          ),
        ],
      ),
    );

    expect(payload.keys, ['BTCLN']);
    expect(payload['BTCLN'], {
      'Type': 'Boltz',
      'LBTC': {'Descriptor': 'ct(slip77(hex),elwpkh(xpub/0/*))#lbtc'},
    });
  });

  test('rejects missing descriptors', () {
    expect(
      () => builder.build(
        request: _request('btc-chain'),
        preparedWallets: PrepareBtcpayPairingWalletsResult(
          wallets: [
            PrepareBtcpayPairingWalletResult(
              network: BtcpayPairingWalletNetwork.bitcoin,
              accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
                isTestnet: false,
              ),
              created: false,
              wallet: _wallet(
                'BTCPay-BTC',
                network: Network.bitcoinMainnet,
                descriptor: '',
              ),
            ),
          ],
        ),
      ),
      throwsA(isA<SamRockSetupPayloadException>()),
    );
  });
}

SamRockPairingRequest _request(String setup) {
  return const SamRockPairingRequestParser().parse(
    'https://btcpay.example/plugins/x/samrock/protocol?setup=$setup&otp=otp',
  );
}

Wallet _wallet(
  String label, {
  required Network network,
  required String descriptor,
}) {
  return Wallet(
    origin: label,
    label: label,
    network: network,
    xpubFingerprint: '',
    scriptType: ScriptType.bip84,
    xpub: '',
    externalPublicDescriptor: descriptor,
    internalPublicDescriptor: '',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
