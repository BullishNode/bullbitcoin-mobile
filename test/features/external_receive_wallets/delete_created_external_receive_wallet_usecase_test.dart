import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/delete_created_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallet extends Mock implements GetExternalReceiveWalletUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.btcpay);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: false),
    );
  });

  late _MockGetWallet getWallet;
  late _MockWalletRepository walletRepository;
  late DeleteCreatedExternalReceiveWalletUsecase usecase;

  setUp(() {
    getWallet = _MockGetWallet();
    walletRepository = _MockWalletRepository();
    usecase = DeleteCreatedExternalReceiveWalletUsecase(
      getWallet: getWallet,
      walletRepository: walletRepository,
    );

    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
      ),
    ).thenAnswer((_) async => _wallet('BTCPay-BTC', Network.bitcoinMainnet));
    when(
      () => walletRepository.deleteWallet(walletId: any(named: 'walletId')),
    ).thenAnswer((_) async {});
  });

  test('deletes only the expected local wallet', () async {
    await usecase.execute(
      environment: Environment.mainnet,
      purpose: ExternalReceiveWalletPurpose.btcpay,
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
      expectedWalletId: 'BTCPay-BTC',
    );

    verify(
      () => walletRepository.deleteWallet(walletId: 'BTCPay-BTC'),
    ).called(1);
    verifyNoMoreInteractions(walletRepository);
  });

  test('does nothing when the expected wallet id does not match', () async {
    await usecase.execute(
      environment: Environment.mainnet,
      purpose: ExternalReceiveWalletPurpose.btcpay,
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
      expectedWalletId: 'different-wallet',
    );

    verifyNever(
      () => walletRepository.deleteWallet(walletId: any(named: 'walletId')),
    );
  });

  test('does nothing when no wallet exists', () async {
    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
      ),
    ).thenAnswer((_) async => null);

    await usecase.execute(
      environment: Environment.mainnet,
      purpose: ExternalReceiveWalletPurpose.btcpay,
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
      expectedWalletId: 'BTCPay-BTC',
    );

    verifyNever(
      () => walletRepository.deleteWallet(walletId: any(named: 'walletId')),
    );
  });
}

Wallet _wallet(String id, Network network, {bool isDefault = false}) {
  return Wallet(
    origin: id,
    label: id,
    network: network,
    isDefault: isDefault,
    masterFingerprint: '73c5da0a',
    xpubFingerprint: '73c5da0a',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'wpkh(xpub/0/*)',
    internalPublicDescriptor: 'wpkh(xpub/1/*)',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
