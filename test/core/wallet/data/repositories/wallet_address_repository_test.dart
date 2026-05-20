import 'package:bb_mobile/core/storage/tables/wallet_metadata_table.dart';
import 'package:bb_mobile/core/wallet/data/datasources/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/datasources/lwk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/datasources/wallet_metadata_datasource.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/wallet_metadata_service.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletMetadataDatasource extends Mock
    implements WalletMetadataDatasource {}

class _MockBdkWalletDatasource extends Mock implements BdkWalletDatasource {}

class _MockLwkWalletDatasource extends Mock implements LwkWalletDatasource {}

class _MockLabelsFacade extends Mock implements LabelsFacade {}

void main() {
  late _MockWalletMetadataDatasource walletMetadataDatasource;
  late _MockBdkWalletDatasource bdkWalletDatasource;
  late _MockLwkWalletDatasource lwkWalletDatasource;
  late _MockLabelsFacade labelsFacade;
  late WalletAddressRepository repository;

  setUpAll(() {
    registerFallbackValue(_liquidWalletModel());
  });

  setUp(() {
    walletMetadataDatasource = _MockWalletMetadataDatasource();
    bdkWalletDatasource = _MockBdkWalletDatasource();
    lwkWalletDatasource = _MockLwkWalletDatasource();
    labelsFacade = _MockLabelsFacade();
    repository = WalletAddressRepository(
      walletMetadataDatasource: walletMetadataDatasource,
      bdkWalletDatasource: bdkWalletDatasource,
      lwkWalletDatasource: lwkWalletDatasource,
      labelsFacade: labelsFacade,
    );
  });

  test(
    'generates Liquid receive address with the matching blinding key',
    () async {
      when(
        () => walletMetadataDatasource.fetch(_liquidWalletId),
      ).thenAnswer((_) async => _liquidMetadata());
      when(
        () => lwkWalletDatasource.getLastUnusedAddress(
          wallet: any(named: 'wallet'),
        ),
      ).thenAnswer(
        (_) async => (standard: 'ex1last', confidential: 'lq1last', index: 7),
      );
      when(
        () => lwkWalletDatasource.getAddressWithBlindingKeyByIndex(
          8,
          wallet: any(named: 'wallet'),
        ),
      ).thenAnswer(
        (_) async => (
          standard: 'ex1invoice',
          confidential: 'lq1invoice',
          index: 8,
          blindingKey: _key,
        ),
      );
      when(
        () => labelsFacade.fetchByReference('lq1invoice'),
      ).thenAnswer((_) async => []);

      final result = await repository
          .generateNewLiquidReceiveAddressWithBlindingKey(
            walletId: _liquidWalletId,
          );

      expect(result.address, 'lq1invoice');
      expect(result.blindingKey, _key);
      verify(
        () => lwkWalletDatasource.getAddressWithBlindingKeyByIndex(
          8,
          wallet: any(named: 'wallet'),
        ),
      ).called(1);
      verifyNever(
        () => lwkWalletDatasource.getAddressByIndex(
          any(),
          wallet: any(named: 'wallet'),
        ),
      );
    },
  );

  test('skips system-labeled Liquid addresses with matching keys', () async {
    when(
      () => walletMetadataDatasource.fetch(_liquidWalletId),
    ).thenAnswer((_) async => _liquidMetadata());
    when(
      () => lwkWalletDatasource.getLastUnusedAddress(
        wallet: any(named: 'wallet'),
      ),
    ).thenAnswer(
      (_) async => (standard: 'ex1last', confidential: 'lq1last', index: 7),
    );
    when(
      () => lwkWalletDatasource.getAddressWithBlindingKeyByIndex(
        8,
        wallet: any(named: 'wallet'),
      ),
    ).thenAnswer(
      (_) async => (
        standard: 'ex1reserved',
        confidential: 'lq1reserved',
        index: 8,
        blindingKey: '22' * 32,
      ),
    );
    when(
      () => lwkWalletDatasource.getAddressWithBlindingKeyByIndex(
        9,
        wallet: any(named: 'wallet'),
      ),
    ).thenAnswer(
      (_) async => (
        standard: 'ex1invoice',
        confidential: 'lq1invoice',
        index: 9,
        blindingKey: _key,
      ),
    );
    when(() => labelsFacade.fetchByReference('lq1reserved')).thenAnswer(
      (_) async => [
        Label.addr(
          id: 1,
          address: 'lq1reserved',
          label: LabelSystem.swaps.label,
        ),
      ],
    );
    when(
      () => labelsFacade.fetchByReference('lq1invoice'),
    ).thenAnswer((_) async => []);

    final result = await repository
        .generateNewLiquidReceiveAddressWithBlindingKey(
          walletId: _liquidWalletId,
        );

    expect(result.address, 'lq1invoice');
    expect(result.blindingKey, _key);
    verify(
      () => lwkWalletDatasource.getAddressWithBlindingKeyByIndex(
        8,
        wallet: any(named: 'wallet'),
      ),
    ).called(1);
    verify(
      () => lwkWalletDatasource.getAddressWithBlindingKeyByIndex(
        9,
        wallet: any(named: 'wallet'),
      ),
    ).called(1);
  });
}

final _key = '11' * 32;

final _liquidWalletId = WalletMetadataService.encodeOrigin(
  fingerprint: '73c5da0a',
  network: Network.liquidMainnet,
  scriptType: ScriptType.bip84,
);

WalletModel _liquidWalletModel() => WalletModel.publicLwk(
  id: _liquidWalletId,
  combinedCtDescriptor: 'ct(slip77(xprv),elwpkh(xpub/0/*))',
  isTestnet: false,
);

WalletMetadataModel _liquidMetadata() => WalletMetadataModel(
  id: _liquidWalletId,
  masterFingerprint: '73c5da0a',
  xpubFingerprint: '73c5da0a',
  isEncryptedVaultTested: false,
  isPhysicalBackupTested: false,
  xpub: 'xpubFAKE',
  externalPublicDescriptor: 'ct(slip77(xprv),elwpkh(xpub/0/*))',
  internalPublicDescriptor: 'ct(slip77(xprv),elwpkh(xpub/1/*))',
  signer: Signer.local,
  isDefault: true,
);
