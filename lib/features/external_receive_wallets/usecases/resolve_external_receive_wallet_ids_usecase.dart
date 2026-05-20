import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/data/external_receive_wallet_settings_datasource.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_ids.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';

class ResolveExternalReceiveWalletIdsUsecase {
  final WalletManifestFacade _walletManifest;
  final ExternalReceiveWalletSettingsDatasource _settings;

  ResolveExternalReceiveWalletIdsUsecase({
    required WalletManifestFacade walletManifest,
    required ExternalReceiveWalletSettingsDatasource settings,
  }) : _walletManifest = walletManifest,
       _settings = settings;

  Future<ExternalReceiveWalletIds> execute(Iterable<Wallet> wallets) async {
    final walletById = {for (final wallet in wallets) wallet.id: wallet};
    if (walletById.isEmpty) return ExternalReceiveWalletIds.empty;

    final origins = await _walletManifest.fetchOrigins();
    final purposeByWalletId = <String, ExternalReceiveWalletPurpose>{};
    final accountKeyByWalletId = <String, ExternalReceiveWalletAccountKey>{};
    final hiddenOnHome = <String>{};

    for (final origin in origins) {
      final wallet = walletById[origin.walletId];
      if (wallet == null) continue;
      if (walletManifestNetworkFromWalletNetwork(wallet.network) !=
          origin.network) {
        continue;
      }

      switch (origin.walletType) {
        case WalletManifestWalletType.manual:
          break;
        case WalletManifestWalletType.lightningAddress:
          await _recordExternalReceiveWallet(
            origin.walletId,
            wallet,
            ExternalReceiveWalletPurpose.lightningAddress,
            purposeByWalletId,
            accountKeyByWalletId,
            hiddenOnHome,
          );
        case WalletManifestWalletType.paymentPage:
          await _recordExternalReceiveWallet(
            origin.walletId,
            wallet,
            ExternalReceiveWalletPurpose.paymentPage,
            purposeByWalletId,
            accountKeyByWalletId,
            hiddenOnHome,
          );
        case WalletManifestWalletType.btcpay:
          await _recordExternalReceiveWallet(
            origin.walletId,
            wallet,
            ExternalReceiveWalletPurpose.btcpay,
            purposeByWalletId,
            accountKeyByWalletId,
            hiddenOnHome,
          );
      }
    }

    return ExternalReceiveWalletIds(
      purposeByWalletId: purposeByWalletId,
      accountKeyByWalletId: accountKeyByWalletId,
      hiddenOnHomeWalletIds: hiddenOnHome,
    );
  }

  Future<void> _recordExternalReceiveWallet(
    String walletId,
    Wallet wallet,
    ExternalReceiveWalletPurpose purpose,
    Map<String, ExternalReceiveWalletPurpose> purposeByWalletId,
    Map<String, ExternalReceiveWalletAccountKey> accountKeyByWalletId,
    Set<String> hiddenOnHome,
  ) async {
    final accountKey = ExternalReceiveWalletAccountKey.forNetwork(
      purpose: purpose,
      network: wallet.network,
    );
    purposeByWalletId[walletId] = purpose;
    accountKeyByWalletId[walletId] = accountKey;
    if (await _settings.getHideWalletForAccount(accountKey)) {
      hiddenOnHome.add(walletId);
    }
  }
}
