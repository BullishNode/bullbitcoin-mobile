import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_wallet.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_wallet_port.dart';
import 'package:meta/meta.dart';

final class DefaultWalletBackupWalletAdapter implements WalletBackupWalletPort {
  final GetSettingsUsecase _getSettings;
  final WalletRepository _wallets;
  final SeedRepository _seeds;

  const DefaultWalletBackupWalletAdapter({
    required this._getSettings,
    required this._wallets,
    required this._seeds,
  });

  @override
  @useResult
  Future<Result<WalletBackupWallet, WalletBackupFailure>>
  deriveDefaultWallet() async {
    try {
      final settings = await _getSettings.execute();
      final defaults = await _wallets.getWallets(
        environment: settings.environment,
        onlyDefaults: true,
        onlyBitcoin: true,
      );
      if (defaults.length != 1) {
        return Err(
          WalletBackupWalletUnavailableFailure(
            'expected one active default Bitcoin wallet; found '
            '${defaults.length}',
          ),
        );
      }
      final wallet = defaults.single;
      final seed = await _seeds.get(wallet.masterFingerprint);
      final walletFingerprint = wallet.masterFingerprint.trim().toLowerCase();
      final seedFingerprint = seed.masterFingerprint.trim().toLowerCase();
      if (walletFingerprint != seedFingerprint) {
        return const Err(
          WalletBackupWalletUnavailableFailure(
            'default wallet and stored seed fingerprints do not match',
          ),
        );
      }
      return Ok(
        WalletBackupWallet(
          xprvBase58: Bip32Derivation.getCanonicalRootXprvFromSeed(seed.bytes),
          parentFingerprint: walletFingerprint,
        ),
      );
    } on ArgumentError catch (error, trace) {
      log.warning(
        'Default wallet backup key validation failed',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(
        WalletBackupWalletUnavailableFailure(error.runtimeType.toString()),
      );
    } on Exception catch (error, trace) {
      log.warning(
        'Default wallet backup key derivation failed',
        error: error.runtimeType,
        trace: trace,
      );
      return Err(
        WalletBackupWalletUnavailableFailure(error.runtimeType.toString()),
      );
    }
  }
}
