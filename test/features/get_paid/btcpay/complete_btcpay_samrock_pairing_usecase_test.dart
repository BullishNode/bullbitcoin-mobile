import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/btcpay_pairing_exception.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/ports/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPrepareWallets extends Mock
    implements PrepareBtcpayPairingWalletsUsecase {}

class _MockPairingService extends Mock implements SamRockPairingServicePort {}

class _MockWalletManifest extends Mock implements WalletManifestFacade {}

void main() {
  late _MockPrepareWallets prepareWallets;
  late _MockPairingService pairingService;
  late _MockWalletManifest walletManifest;
  late CompleteBtcpaySamRockPairingUsecase usecase;

  setUpAll(() {
    registerFallbackValue(
      const SamRockPairingRequestParser().parse(
        'https://btcpay.example/plugins/x/samrock/protocol?setup=liquid-chain&otp=otp',
      ),
    );
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(_preparedWallets());
  });

  setUp(() {
    prepareWallets = _MockPrepareWallets();
    pairingService = _MockPairingService();
    walletManifest = _MockWalletManifest();
    usecase = CompleteBtcpaySamRockPairingUsecase(
      parser: const SamRockPairingRequestParser(),
      prepareWallets: prepareWallets,
      payloadBuilder: const SamRockSetupPayloadBuilder(),
      pairingService: pairingService,
      walletManifest: walletManifest,
    );

    when(
      () => prepareWallets.execute(request: any(named: 'request')),
    ).thenAnswer((_) async => _preparedWallets());
    when(
      () => prepareWallets.rollbackCreatedWallets(any()),
    ).thenAnswer((_) async {});
    when(() => walletManifest.publishLocalManifest()).thenAnswer((_) async {});
    when(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer(
      (_) async => const SamRockPairingResponse(
        success: true,
        message: 'Wallet setup successfully.',
      ),
    );
  });

  test('parses, prepares wallets, builds payload, and submits setup', () async {
    await usecase.execute(
      pairingUrl:
          'https://btcpay.example/plugins/store/samrock/protocol?setup=btc-chain,liquid-chain,btc-ln&otp=abc',
    );

    final capturedRequest =
        verify(
              () =>
                  prepareWallets.execute(request: captureAny(named: 'request')),
            ).captured.single
            as SamRockPairingRequest;
    expect(capturedRequest.otp, 'abc');
    final capturedPayload =
        verify(
              () => pairingService.submitSetup(
                request: any(named: 'request'),
                payload: captureAny(named: 'payload'),
              ),
            ).captured.single
            as Map<String, Object?>;
    expect(capturedPayload.keys, containsAll(['BTC', 'LBTC', 'BTCLN']));
    verify(() => walletManifest.publishLocalManifest()).called(1);
    verifyNever(() => prepareWallets.rollbackCreatedWallets(any()));
  });

  test('does not fail pairing when manifest publish fails', () async {
    when(
      () => walletManifest.publishLocalManifest(),
    ).thenThrow(Exception('nostr unavailable'));

    await usecase.execute(
      pairingUrl:
          'https://btcpay.example/plugins/store/samrock/protocol?setup=liquid-chain&otp=abc',
    );

    verify(() => walletManifest.publishLocalManifest()).called(1);
    verifyNever(() => prepareWallets.rollbackCreatedWallets(any()));
  });

  test('throws when the server rejects setup', () async {
    when(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer(
      (_) async =>
          const SamRockPairingResponse(success: false, message: 'OTP expired'),
    );

    await expectLater(
      usecase.execute(
        pairingUrl:
            'https://btcpay.example/plugins/store/samrock/protocol?setup=liquid-chain&otp=abc',
      ),
      throwsA(
        isA<BtcpayPairingException>()
            .having(
              (error) => error.type,
              'type',
              BtcpayPairingExceptionType.rejected,
            )
            .having((error) => error.message, 'message', 'OTP expired'),
      ),
    );
    verifyNever(() => prepareWallets.rollbackCreatedWallets(any()));
    verify(() => walletManifest.publishLocalManifest()).called(1);
  });

  test('maps SamRock server failures to generic errors', () async {
    when(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer(
      (_) async => const SamRockPairingResponse(
        success: false,
        serverFailure: true,
        message: 'BTCPay SamRock server returned HTTP 502',
      ),
    );

    await expectLater(
      usecase.execute(
        pairingUrl:
            'https://btcpay.example/plugins/store/samrock/protocol?setup=liquid-chain&otp=abc',
      ),
      throwsA(
        isA<BtcpayPairingException>()
            .having(
              (error) => error.type,
              'type',
              BtcpayPairingExceptionType.generic,
            )
            .having(
              (error) => error.message,
              'message',
              'BTCPay SamRock server returned HTTP 502',
            ),
      ),
    );
    verifyNever(() => prepareWallets.rollbackCreatedWallets(any()));
    verify(() => walletManifest.publishLocalManifest()).called(1);
  });

  test('maps invalid SamRock URLs to application failures', () async {
    await expectLater(
      usecase.execute(pairingUrl: 'not a url'),
      throwsA(
        isA<BtcpayPairingException>().having(
          (error) => error.type,
          'type',
          BtcpayPairingExceptionType.invalidRequest,
        ),
      ),
    );

    verifyNever(() => prepareWallets.execute(request: any(named: 'request')));
    verifyNever(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    );
  });
}

PrepareBtcpayPairingWalletsResult _preparedWallets() {
  return PrepareBtcpayPairingWalletsResult(
    wallets: [
      PrepareBtcpayPairingWalletResult(
        network: BtcpayPairingWalletNetwork.bitcoin,
        accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: false,
        ),
        created: true,
        wallet: _wallet(
          'BTCPay-BTC',
          network: Network.bitcoinMainnet,
          descriptor: 'wpkh(xpub/0/*)#btc',
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
