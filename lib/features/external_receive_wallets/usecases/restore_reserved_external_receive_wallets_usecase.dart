import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_errors.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_restore_outcome.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/create_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';

class RestoreReservedExternalReceiveWalletsUsecase {
  final GetExternalReceiveWalletUsecase _getWallet;
  final CreateExternalReceiveWalletUsecase _createWallet;
  final WalletManifestFacade _walletManifest;

  RestoreReservedExternalReceiveWalletsUsecase({
    required GetExternalReceiveWalletUsecase getWallet,
    required CreateExternalReceiveWalletUsecase createWallet,
    required WalletManifestFacade walletManifest,
  }) : _getWallet = getWallet,
       _createWallet = createWallet,
       _walletManifest = walletManifest;

  Future<List<ExternalReceiveWalletRestoreOutcome>> execute({
    required Environment environment,
  }) async {
    final isTestnet = environment == Environment.testnet;
    final accountKeys = [
      ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
        isTestnet: isTestnet,
      ),
      ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: isTestnet,
      ),
      ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
        isTestnet: isTestnet,
      ),
      ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: isTestnet,
      ),
    ];

    final outcomes = <ExternalReceiveWalletRestoreOutcome>[];
    for (final accountKey in accountKeys) {
      outcomes.add(
        await _restoreAccountKey(
          environment: environment,
          accountKey: accountKey,
        ),
      );
    }

    final hasLocalChanges = outcomes.any(
      (outcome) => outcome.changedLocalState,
    );
    if (hasLocalChanges) {
      await _publishManifestBestEffort();
    }
    return outcomes;
  }

  Future<ExternalReceiveWalletRestoreOutcome> _restoreAccountKey({
    required Environment environment,
    required ExternalReceiveWalletAccountKey accountKey,
  }) async {
    final purpose = accountKey.purpose;
    try {
      final existing = await _getWallet.execute(
        environment: environment,
        purpose: purpose,
        accountKey: accountKey,
      );
      if (existing != null) {
        return ExternalReceiveWalletRestoreOutcome(
          accountKey: accountKey,
          status: ExternalReceiveWalletRestoreOutcomeStatus.existing,
        );
      }

      final created = await _createWallet.executeWithResult(
        environment: environment,
        purpose: purpose,
        accountKey: accountKey,
        publishManifest: false,
      );
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: _statusFromCreateResult(created),
      );
    } on ExternalReceiveWalletAlreadyExistsException {
      return await _alreadyExistsRaceOutcome(
        environment: environment,
        accountKey: accountKey,
      );
    } on ExternalReceiveWalletNoDefaultWalletException {
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason:
            ExternalReceiveWalletRestoreFailureReason.noDefaultWallet,
      );
    } on ExternalReceiveWalletMetadataException {
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason:
            ExternalReceiveWalletRestoreFailureReason.metadataUpdateFailed,
      );
    } catch (e, stack) {
      log.warning(
        'External receive wallet restore failed',
        error: e,
        trace: stack,
      );
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason:
            ExternalReceiveWalletRestoreFailureReason.walletCreationFailed,
      );
    }
  }

  Future<ExternalReceiveWalletRestoreOutcome> _alreadyExistsRaceOutcome({
    required Environment environment,
    required ExternalReceiveWalletAccountKey accountKey,
  }) async {
    final purpose = accountKey.purpose;
    try {
      final existing = await _getWallet.execute(
        environment: environment,
        purpose: purpose,
        accountKey: accountKey,
      );
      if (existing != null) {
        return ExternalReceiveWalletRestoreOutcome(
          accountKey: accountKey,
          status: ExternalReceiveWalletRestoreOutcomeStatus.existing,
        );
      }

      final restored = await _createWallet.executeWithResult(
        environment: environment,
        purpose: purpose,
        accountKey: accountKey,
        publishManifest: false,
      );
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: _statusFromCreateResult(restored),
      );
    } on ExternalReceiveWalletMetadataException {
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason:
            ExternalReceiveWalletRestoreFailureReason.metadataUpdateFailed,
      );
    } on ExternalReceiveWalletNoDefaultWalletException {
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason:
            ExternalReceiveWalletRestoreFailureReason.noDefaultWallet,
      );
    } on ExternalReceiveWalletAlreadyExistsException {
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason:
            ExternalReceiveWalletRestoreFailureReason.alreadyExistsRace,
      );
    } catch (e, stack) {
      log.warning(
        'External receive wallet race recovery failed',
        error: e,
        trace: stack,
      );
      return ExternalReceiveWalletRestoreOutcome(
        accountKey: accountKey,
        status: ExternalReceiveWalletRestoreOutcomeStatus.failed,
        failureReason: null,
      );
    }
  }

  ExternalReceiveWalletRestoreOutcomeStatus _statusFromCreateResult(
    CreateExternalReceiveWalletResult result,
  ) {
    return switch (result.status) {
      CreateExternalReceiveWalletStatus.created =>
        ExternalReceiveWalletRestoreOutcomeStatus.created,
      CreateExternalReceiveWalletStatus.repaired =>
        ExternalReceiveWalletRestoreOutcomeStatus.repaired,
    };
  }

  Future<void> _publishManifestBestEffort() async {
    try {
      await _walletManifest.publishLocalManifest();
    } catch (e, stack) {
      log.warning(
        'External receive wallet restore manifest publish failed',
        error: e,
        trace: stack,
      );
    }
  }
}
