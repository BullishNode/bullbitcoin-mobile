import 'package:bb_mobile/features/wallet_manifest/application/usecases/create_manual_bip85_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/record_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRecordOrigin extends Mock
    implements RecordWalletManifestOriginUsecase {}

class _MockFetchOrigins extends Mock
    implements FetchWalletManifestOriginsUsecase {}

class _MockPublishSnapshot extends Mock
    implements PublishLocalWalletManifestUsecase {}

class _MockCreateManualBip85Wallets extends Mock
    implements CreateManualBip85WalletsUsecase {}

void main() {
  setUpAll(() {
    registerFallbackValue(WalletManifestNetwork.bitcoin);
    registerFallbackValue(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.liquid,
        liquidLabel: 'Liquid',
      ),
    );
  });

  test('publishes the local manifest without caller-supplied xprv', () async {
    final publishSnapshot = _MockPublishSnapshot();
    final facade = _facade(publishSnapshot: publishSnapshot);
    when(() => publishSnapshot.execute()).thenAnswer((_) async => 0);

    await facade.publishLocalManifest();

    verify(() => publishSnapshot.execute()).called(1);
  });

  test('maps manual BIP85 creation errors to public failures', () async {
    final createManualBip85Wallets = _MockCreateManualBip85Wallets();
    final facade = _facade(createManualBip85Wallets: createManualBip85Wallets);
    when(
      () => createManualBip85Wallets.execute(any()),
    ).thenThrow(WalletManifestManualBip85IndexUnavailableException(75));

    await expectLater(
      facade.createManualBip85Wallets(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          index: 75,
          liquidLabel: 'Liquid',
        ),
      ),
      throwsA(
        isA<CreateManualBip85WalletsException>().having(
          (error) => error.failure,
          'failure',
          CreateManualBip85WalletsFailure.indexUnavailable,
        ),
      ),
    );
  });
}

WalletManifestFacade _facade({
  RecordWalletManifestOriginUsecase? recordOrigin,
  FetchWalletManifestOriginsUsecase? fetchOrigins,
  PublishLocalWalletManifestUsecase? publishSnapshot,
  WalletManifestSeedRecoveryStarter? startSeedRecoveryRestore,
  CreateManualBip85WalletsUsecase? createManualBip85Wallets,
}) {
  return WalletManifestFacade(
    recordOrigin: recordOrigin ?? _MockRecordOrigin(),
    fetchOrigins: fetchOrigins ?? _MockFetchOrigins(),
    publishLocalManifest: publishSnapshot ?? _MockPublishSnapshot(),
    startRestoreAfterSeedRecovery:
        startSeedRecoveryRestore ??
        ({void Function()? onWalletStateMayHaveChanged}) {},
    createManualBip85Wallets:
        createManualBip85Wallets ?? _MockCreateManualBip85Wallets(),
  );
}
