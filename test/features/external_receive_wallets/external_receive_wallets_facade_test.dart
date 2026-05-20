import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/create_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/delete_created_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/restore_reserved_external_receive_wallets_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/resolve_external_receive_wallet_ids_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/sweep_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/data/external_receive_wallet_settings_datasource.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetExternalReceiveWalletUsecase extends Mock
    implements GetExternalReceiveWalletUsecase {}

class _MockCreateExternalReceiveWalletUsecase extends Mock
    implements CreateExternalReceiveWalletUsecase {}

class _MockDeleteCreatedExternalReceiveWalletUsecase extends Mock
    implements DeleteCreatedExternalReceiveWalletUsecase {}

class _MockSweepExternalReceiveWalletUsecase extends Mock
    implements SweepExternalReceiveWalletUsecase {}

class _MockRestoreReservedExternalReceiveWalletsUsecase extends Mock
    implements RestoreReservedExternalReceiveWalletsUsecase {}

class _MockWalletManifestFacade extends Mock implements WalletManifestFacade {}

class _MockReceiveWalletSettings extends Mock
    implements ExternalReceiveWalletSettingsDatasource {}

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.lightningAddress);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
        isTestnet: false,
      ),
    );
  });

  late _MockGetExternalReceiveWalletUsecase getWallet;
  late _MockCreateExternalReceiveWalletUsecase createWallet;
  late _MockDeleteCreatedExternalReceiveWalletUsecase deleteCreatedWallet;
  late _MockRestoreReservedExternalReceiveWalletsUsecase restoreReservedWallets;
  late _MockSweepExternalReceiveWalletUsecase sweepWallet;
  late _MockWalletManifestFacade walletManifest;
  late _MockReceiveWalletSettings settings;
  late ResolveExternalReceiveWalletIdsUsecase resolveWalletIds;
  late ExternalReceiveWalletsFacade facade;

  setUp(() {
    getWallet = _MockGetExternalReceiveWalletUsecase();
    createWallet = _MockCreateExternalReceiveWalletUsecase();
    deleteCreatedWallet = _MockDeleteCreatedExternalReceiveWalletUsecase();
    restoreReservedWallets =
        _MockRestoreReservedExternalReceiveWalletsUsecase();
    sweepWallet = _MockSweepExternalReceiveWalletUsecase();
    walletManifest = _MockWalletManifestFacade();
    settings = _MockReceiveWalletSettings();
    resolveWalletIds = ResolveExternalReceiveWalletIdsUsecase(
      walletManifest: walletManifest,
      settings: settings,
    );
    when(() => settings.getAutoSweepForAccount(any())).thenAnswer((
      invocation,
    ) async {
      final accountKey =
          invocation.positionalArguments[0] as ExternalReceiveWalletAccountKey;
      return accountKey.network.isLiquid;
    });
    when(() => settings.getHideWalletForAccount(any())).thenAnswer((
      invocation,
    ) async {
      final accountKey =
          invocation.positionalArguments[0] as ExternalReceiveWalletAccountKey;
      return accountKey.network.isLiquid;
    });
    facade = ExternalReceiveWalletsFacade(
      getWallet: getWallet,
      createWallet: createWallet,
      deleteCreatedWallet: deleteCreatedWallet,
      restoreReservedWallets: restoreReservedWallets,
      sweepWallet: sweepWallet,
      resolveWalletIds: resolveWalletIds,
      settings: settings,
    );
  });

  test('sweeps the requested external receive wallet purpose', () async {
    when(
      () => sweepWallet.execute(
        isTestnet: any(named: 'isTestnet'),
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
        expectedWalletId: any(named: 'expectedWalletId'),
      ),
    ).thenAnswer((_) async => 'la-txid');
    final txid = await facade.sweep(
      isTestnet: true,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
      expectedWalletId: 'la-wallet',
    );

    expect(txid, 'la-txid');
    verify(
      () => sweepWallet.execute(
        isTestnet: true,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
        expectedWalletId: 'la-wallet',
      ),
    ).called(1);
    verifyNoMoreInteractions(sweepWallet);
  });

  test(
    'restores reserved Get Paid wallets through the restore usecase',
    () async {
      const result = <ExternalReceiveWalletRestoreOutcome>[];
      when(
        () => restoreReservedWallets.execute(environment: Environment.mainnet),
      ).thenAnswer((_) async => result);

      final restored = await facade.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      );

      expect(restored, result);
      verify(
        () => restoreReservedWallets.execute(environment: Environment.mainnet),
      ).called(1);
      verifyNoMoreInteractions(restoreReservedWallets);
    },
  );

  test('classifies external receive wallets by manifest origin id', () async {
    when(
      () => settings.getHideWalletForAccount(
        ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
          isTestnet: false,
        ),
      ),
    ).thenAnswer((_) async => false);
    when(() => walletManifest.fetchOrigins()).thenAnswer(
      (_) async => [
        WalletManifestOrigin(
          walletId: 'renamed-la',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 75),
          network: WalletManifestNetwork.liquid,
          createdAt: 100,
          updatedAt: 100,
        ),
        WalletManifestOrigin(
          walletId: 'manual-wallet',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 1),
          network: WalletManifestNetwork.liquid,
          createdAt: 100,
          updatedAt: 100,
        ),
      ],
    );

    final ids = await facade.idsForWallets([
      _wallet('Renamed Lightning Address', id: 'renamed-la'),
      _wallet(
        ReservedExternalReceiveWalletLabel.paymentPageLiquid,
        id: 'manual-wallet',
      ),
    ]);

    expect(ids.isExternalReceiveWallet('renamed-la'), isTrue);
    expect(
      ids.purposeForWalletId('renamed-la'),
      ExternalReceiveWalletPurpose.lightningAddress,
    );
    expect(ids.isExternalReceiveWallet('manual-wallet'), isFalse);
    expect(ids.hiddenOnHomeWalletIds, isEmpty);
  });

  test('keeps valid ids when a manifest origin network mismatches', () async {
    when(() => walletManifest.fetchOrigins()).thenAnswer(
      (_) async => [
        WalletManifestOrigin(
          walletId: 'renamed-la',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 75),
          network: WalletManifestNetwork.liquid,
          createdAt: 100,
          updatedAt: 100,
        ),
        WalletManifestOrigin(
          walletId: 'btcpay',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 77),
          network: WalletManifestNetwork.bitcoin,
          createdAt: 100,
          updatedAt: 100,
        ),
      ],
    );

    final ids = await facade.idsForWallets([
      _wallet('Renamed Lightning Address', id: 'renamed-la'),
      _wallet('BTCPay-LBTC', id: 'btcpay', network: Network.liquidMainnet),
    ]);

    expect(ids.isExternalReceiveWallet('renamed-la'), isTrue);
    expect(
      ids.purposeForWalletId('renamed-la'),
      ExternalReceiveWalletPurpose.lightningAddress,
    );
    expect(ids.isExternalReceiveWallet('btcpay'), isFalse);
  });

  test('marks Liquid external receive wallets hidden by settings', () async {
    when(() => walletManifest.fetchOrigins()).thenAnswer(
      (_) async => [
        WalletManifestOrigin(
          walletId: 'lightning-address',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 75),
          network: WalletManifestNetwork.liquid,
          createdAt: 100,
          updatedAt: 100,
        ),
        WalletManifestOrigin(
          walletId: 'payment-page',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 76),
          network: WalletManifestNetwork.liquid,
          createdAt: 100,
          updatedAt: 100,
        ),
        WalletManifestOrigin(
          walletId: 'btcpay-liquid',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 77),
          network: WalletManifestNetwork.liquid,
          createdAt: 100,
          updatedAt: 100,
        ),
        WalletManifestOrigin(
          walletId: 'btcpay-bitcoin',
          rootFingerprint: '73c5da0a',
          bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 77),
          network: WalletManifestNetwork.bitcoin,
          createdAt: 100,
          updatedAt: 100,
        ),
      ],
    );

    final ids = await facade.idsForWallets([
      _wallet('Lightning Address-LBTC', id: 'lightning-address'),
      _wallet('Payment Page-LBTC', id: 'payment-page'),
      _wallet('BTCPay-LBTC', id: 'btcpay-liquid'),
      _wallet(
        'BTCPay-BTC',
        id: 'btcpay-bitcoin',
        network: Network.bitcoinMainnet,
      ),
    ]);

    expect(ids.isExternalReceiveWallet('lightning-address'), isTrue);
    expect(ids.isExternalReceiveWallet('payment-page'), isTrue);
    expect(ids.isExternalReceiveWallet('btcpay-liquid'), isTrue);
    expect(ids.isExternalReceiveWallet('btcpay-bitcoin'), isTrue);
    expect(ids.hiddenOnHomeWalletIds, {
      'lightning-address',
      'payment-page',
      'btcpay-liquid',
    });
  });
}

Wallet _wallet(
  String label, {
  String? id,
  Network network = Network.liquidMainnet,
}) => Wallet(
  origin: id ?? label,
  label: label,
  network: network,
  xpubFingerprint: '',
  scriptType: ScriptType.bip84,
  xpub: '',
  externalPublicDescriptor: '',
  internalPublicDescriptor: '',
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: BigInt.zero,
);
