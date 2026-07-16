import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_root.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_root_port.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;

final class LocalWalletMetadataBackupRootAdapter
    implements WalletMetadataBackupRootPort {
  final GetSettingsUsecase _getSettings;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const LocalWalletMetadataBackupRootAdapter({
    required this._getSettings,
    required this._walletRepository,
    required this._seedRepository,
  });

  @override
  Future<Result<WalletMetadataBackupRoot, WalletMetadataBackupFailure>>
  deriveLocalRoot() async {
    try {
      final settings = await _getSettings.execute();
      final wallets = await _walletRepository.getWallets(
        environment: settings.environment,
        onlyDefaults: true,
        onlyBitcoin: true,
      );
      if (wallets.isEmpty) {
        return const Err(WalletMetadataBackupKeyFailure());
      }
      final wallet = wallets.first;
      if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(wallet.masterFingerprint)) {
        return const Err(WalletMetadataBackupKeyFailure());
      }
      final seed = await _seedRepository.get(wallet.masterFingerprint);
      final xprv = Bip32Derivation.getXprvFromSeed(seed.bytes, wallet.network);
      if (xprv.isEmpty || xprv.length > 256) {
        return const Err(WalletMetadataBackupKeyFailure());
      }
      final normalizedFingerprint = wallet.masterFingerprint.toLowerCase();
      if (bip32.Bip32Keys.fromBase58(xprv).fingerprintHex !=
          normalizedFingerprint) {
        return const Err(WalletMetadataBackupKeyFailure());
      }
      return Ok(
        WalletMetadataBackupRoot(
          xprvBase58: xprv,
          parentFingerprint: normalizedFingerprint,
        ),
      );
    } on ArgumentError catch (_, st) {
      _logRootFailure(st);
      return const Err(WalletMetadataBackupKeyFailure());
    } on Exception catch (_, st) {
      _logRootFailure(st);
      return const Err(WalletMetadataBackupKeyFailure());
    }
  }

  void _logRootFailure(StackTrace stack) {
    log.warning(
      'Wallet metadata local recovery root derivation failed',
      error: StateError('Wallet metadata recovery root unavailable'),
      trace: stack,
    );
  }
}
