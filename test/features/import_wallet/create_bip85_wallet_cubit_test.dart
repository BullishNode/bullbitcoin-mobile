import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_cubit.dart';
import 'package:bb_mobile/features/import_wallet/create_bip85_wallet_state.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletManifestFacade extends Mock implements WalletManifestFacade {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.liquid,
        liquidLabel: 'Liquid',
      ),
    );
  });

  test('emits success with created wallet result', () async {
    final walletManifest = _MockWalletManifestFacade();
    const result = CreateManualBip85WalletsResult(
      wallets: [],
      index: 2,
      manifestPublishFailed: false,
    );
    when(
      () => walletManifest.createManualBip85Wallets(any()),
    ).thenAnswer((_) async => result);
    final cubit = CreateBip85WalletCubit(walletManifest: walletManifest);
    addTearDown(cubit.close);

    await cubit.submit(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.liquid,
        liquidLabel: 'Liquid',
      ),
    );

    expect(cubit.state.status, CreateBip85WalletStatus.succeeded);
    expect(cubit.state.result, result);
  });

  test('maps reserved or existing index failures', () async {
    final walletManifest = _MockWalletManifestFacade();
    when(() => walletManifest.createManualBip85Wallets(any())).thenThrow(
      const CreateManualBip85WalletsException(
        CreateManualBip85WalletsFailure.indexUnavailable,
      ),
    );
    final cubit = CreateBip85WalletCubit(walletManifest: walletManifest);
    addTearDown(cubit.close);

    await cubit.submit(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.liquid,
        index: 75,
        liquidLabel: 'Liquid',
      ),
    );

    expect(cubit.state.status, CreateBip85WalletStatus.failed);
    expect(
      cubit.state.failure,
      CreateManualBip85WalletsFailure.indexUnavailable,
    );
  });
}
