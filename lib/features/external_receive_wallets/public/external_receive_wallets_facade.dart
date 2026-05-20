import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_ids.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_restore_outcome.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/create_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/delete_created_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/restore_reserved_external_receive_wallets_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/resolve_external_receive_wallet_ids_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/sweep_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/data/external_receive_wallet_settings_datasource.dart';

class ExternalReceiveWalletsFacade {
  final GetExternalReceiveWalletUsecase _getWallet;
  final CreateExternalReceiveWalletUsecase _createWallet;
  final DeleteCreatedExternalReceiveWalletUsecase _deleteCreatedWallet;
  final RestoreReservedExternalReceiveWalletsUsecase _restoreReservedWallets;
  final SweepExternalReceiveWalletUsecase _sweepWallet;
  final ResolveExternalReceiveWalletIdsUsecase _resolveWalletIds;
  final ExternalReceiveWalletSettingsDatasource _settings;

  ExternalReceiveWalletsFacade({
    required GetExternalReceiveWalletUsecase getWallet,
    required CreateExternalReceiveWalletUsecase createWallet,
    required DeleteCreatedExternalReceiveWalletUsecase deleteCreatedWallet,
    required RestoreReservedExternalReceiveWalletsUsecase
    restoreReservedWallets,
    required SweepExternalReceiveWalletUsecase sweepWallet,
    required ResolveExternalReceiveWalletIdsUsecase resolveWalletIds,
    required ExternalReceiveWalletSettingsDatasource settings,
  }) : _getWallet = getWallet,
       _createWallet = createWallet,
       _deleteCreatedWallet = deleteCreatedWallet,
       _restoreReservedWallets = restoreReservedWallets,
       _sweepWallet = sweepWallet,
       _resolveWalletIds = resolveWalletIds,
       _settings = settings;

  Future<Wallet?> get({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    ExternalReceiveWalletAccountKey? accountKey,
  }) {
    return _getWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
    );
  }

  Future<Wallet> create({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    ExternalReceiveWalletAccountKey? accountKey,
    bool publishManifest = true,
  }) {
    return _createWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
      publishManifest: publishManifest,
    );
  }

  Future<void> deleteCreated({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    required ExternalReceiveWalletAccountKey accountKey,
    required String expectedWalletId,
  }) {
    return _deleteCreatedWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
      expectedWalletId: expectedWalletId,
    );
  }

  Future<String?> sweep({
    required bool isTestnet,
    required ExternalReceiveWalletPurpose purpose,
    required String expectedWalletId,
    ExternalReceiveWalletAccountKey? accountKey,
  }) {
    return _sweepWallet.execute(
      isTestnet: isTestnet,
      purpose: purpose,
      expectedWalletId: expectedWalletId,
      accountKey: accountKey,
    );
  }

  Future<bool> shouldAutoSweepForAccount(
    ExternalReceiveWalletAccountKey accountKey,
  ) {
    return _settings.getAutoSweepForAccount(accountKey);
  }

  Future<void> setAutoSweepForAccount(
    ExternalReceiveWalletAccountKey accountKey,
    bool value,
  ) {
    return _settings.setAutoSweepForAccount(accountKey, value);
  }

  Future<bool> isHiddenOnHomeForAccount(
    ExternalReceiveWalletAccountKey accountKey,
  ) {
    return _settings.getHideWalletForAccount(accountKey);
  }

  Future<void> setHiddenOnHomeForAccount(
    ExternalReceiveWalletAccountKey accountKey,
    bool value,
  ) {
    return _settings.setHideWalletForAccount(accountKey, value);
  }

  Future<List<ExternalReceiveWalletRestoreOutcome>>
  restoreReservedExternalReceiveWallets({required Environment environment}) {
    return _restoreReservedWallets.execute(environment: environment);
  }

  Future<ExternalReceiveWalletIds> idsForWallets(Iterable<Wallet> wallets) =>
      _resolveWalletIds.execute(wallets);
}
