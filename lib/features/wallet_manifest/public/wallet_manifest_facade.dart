import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/record_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/create_manual_bip85_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

typedef WalletManifestSeedRecoveryStarter =
    void Function({void Function()? onWalletStateMayHaveChanged});

class WalletManifestFacade {
  final RecordWalletManifestOriginUsecase _recordOrigin;
  final FetchWalletManifestOriginsUsecase _fetchOrigins;
  final PublishLocalWalletManifestUsecase _publishLocalManifest;
  final WalletManifestSeedRecoveryStarter _startRestoreAfterSeedRecovery;
  final CreateManualBip85WalletsUsecase _createManualBip85Wallets;

  WalletManifestFacade({
    required RecordWalletManifestOriginUsecase recordOrigin,
    required FetchWalletManifestOriginsUsecase fetchOrigins,
    required PublishLocalWalletManifestUsecase publishLocalManifest,
    required WalletManifestSeedRecoveryStarter startRestoreAfterSeedRecovery,
    required CreateManualBip85WalletsUsecase createManualBip85Wallets,
  }) : _recordOrigin = recordOrigin,
       _fetchOrigins = fetchOrigins,
       _publishLocalManifest = publishLocalManifest,
       _startRestoreAfterSeedRecovery = startRestoreAfterSeedRecovery,
       _createManualBip85Wallets = createManualBip85Wallets;

  Future<void> recordOrigin({
    required String walletId,
    required WalletManifestNetwork network,
    required String rootFingerprint,
    required String bip85DerivationPath,
  }) {
    return _recordOrigin.execute(
      walletId: walletId,
      network: network,
      rootFingerprint: rootFingerprint,
      bip85DerivationPath: bip85DerivationPath,
    );
  }

  Future<List<WalletManifestOrigin>> fetchOrigins() => _fetchOrigins.execute();

  Future<void> publishLocalManifest() async {
    await _publishLocalManifest.execute();
  }

  void startRestoreAfterSeedRecovery({
    void Function()? onWalletStateMayHaveChanged,
  }) {
    _startRestoreAfterSeedRecovery(
      onWalletStateMayHaveChanged: onWalletStateMayHaveChanged,
    );
  }

  Future<CreateManualBip85WalletsResult> createManualBip85Wallets(
    CreateManualBip85WalletsCommand command,
  ) async {
    try {
      return await _createManualBip85Wallets.execute(command);
    } catch (error) {
      throw switch (error) {
        WalletManifestManualBip85LabelRequiredException() =>
          const CreateManualBip85WalletsException(
            CreateManualBip85WalletsFailure.labelRequired,
          ),
        WalletManifestManualBip85ReservedLabelException() =>
          const CreateManualBip85WalletsException(
            CreateManualBip85WalletsFailure.reservedLabel,
          ),
        WalletManifestManualBip85InvalidIndexException() =>
          const CreateManualBip85WalletsException(
            CreateManualBip85WalletsFailure.invalidIndex,
          ),
        WalletManifestManualBip85IndexUnavailableException() =>
          const CreateManualBip85WalletsException(
            CreateManualBip85WalletsFailure.indexUnavailable,
          ),
        WalletManifestManualBip85WalletCreationException() =>
          const CreateManualBip85WalletsException(
            CreateManualBip85WalletsFailure.walletCreation,
          ),
        _ => const CreateManualBip85WalletsException(
          CreateManualBip85WalletsFailure.generic,
        ),
      };
    }
  }
}
