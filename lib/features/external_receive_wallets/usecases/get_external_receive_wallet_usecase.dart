import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_errors.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';

class GetExternalReceiveWalletUsecase {
  final WalletRepository _walletRepository;
  final WalletManifestFacade _walletManifest;

  GetExternalReceiveWalletUsecase({
    required WalletRepository walletRepository,
    required WalletManifestFacade walletManifest,
  }) : _walletRepository = walletRepository,
       _walletManifest = walletManifest;

  Future<Wallet?> execute({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    ExternalReceiveWalletAccountKey? accountKey,
  }) async {
    final key =
        accountKey ??
        purpose.liquidAccountKey(isTestnet: environment == Environment.testnet);
    if (key.purpose != purpose) {
      throw ArgumentError.value(
        accountKey,
        'accountKey',
        'account key purpose must match purpose',
      );
    }
    if (key.network.isTestnet != environment.isTestnet) {
      throw ArgumentError.value(
        accountKey,
        'accountKey',
        'account key network must match environment',
      );
    }
    final wallets = await _walletRepository.getWallets(
      environment: environment,
    );
    final defaultWallet = await _getDefaultBitcoinWallet(environment);
    final manifestNetwork = walletManifestNetworkFromWalletNetwork(key.network);
    final derivationPath = Bip85DerivationPath.mnemonic12(
      index: key.bip85Index,
    );
    final origins = await _walletManifest.fetchOrigins();
    final originWalletIds = origins
        .where(
          (origin) => origin.rootFingerprint == defaultWallet.masterFingerprint,
        )
        .where((origin) => origin.network == manifestNetwork)
        .where((origin) => origin.bip85DerivationPath == derivationPath)
        .map((origin) => origin.walletId)
        .toSet();

    return wallets
        .where((wallet) => wallet.network == key.network)
        .where((wallet) => originWalletIds.contains(wallet.id))
        .firstOrNull;
  }

  Future<Wallet> _getDefaultBitcoinWallet(Environment environment) async {
    final wallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) {
      throw ExternalReceiveWalletNoDefaultWalletException();
    }
    return wallets.first;
  }
}
