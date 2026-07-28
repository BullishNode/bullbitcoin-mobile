import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/data/services/mnemonic_generator.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/inconsistent_wallet_state_exception.dart';

class CreateDefaultWalletsUsecase {
  final SeedRepository _seedRepository;
  final SettingsRepository _settingsRepository;
  final MnemonicGenerator _mnemonicGenerator;
  final WalletRepository _wallet;

  CreateDefaultWalletsUsecase({
    required this._seedRepository,
    required this._settingsRepository,
    required this._mnemonicGenerator,
    required WalletRepository walletRepository,
  }) : _wallet = walletRepository;

  Future<List<Wallet>> execute({
    List<String>? mnemonicWords,
    String? passphrase,
  }) async {
    try {
      final settings = await _settingsRepository.fetch();
      final environment = settings.environment;

      const scriptType = ScriptType.bip84;
      final bitcoinNetwork = environment.isMainnet
          ? Network.bitcoinMainnet
          : Network.bitcoinTestnet;
      final liquidNetwork = environment.isMainnet
          ? Network.liquidMainnet
          : Network.liquidTestnet;

      final existing = await _wallet.getWallets(
        onlyDefaults: true,
        environment: environment,
      );
      final hasBitcoin = existing.any((w) => w.network.isBitcoin);
      final hasLiquid = existing.any((w) => w.network.isLiquid);
      if (hasBitcoin && hasLiquid) {
        await _ensureSeedsPresent(
          existing,
          mnemonicWords: mnemonicWords,
          passphrase: passphrase,
        );
        return existing;
      }

      final isGenerated = mnemonicWords == null;
      final mnemonic = mnemonicWords ?? _mnemonicGenerator.generate();
      final DateTime? birthday = isGenerated ? DateTime.now().toUtc() : null;
      final seed = await _seedRepository.createFromMnemonic(
        mnemonicWords: mnemonic,
        passphrase: passphrase,
      );

      final created = <Wallet>[];
      try {
        if (!hasBitcoin) {
          created.add(
            await _wallet.createWallet(
              seed: seed,
              network: bitcoinNetwork,
              scriptType: scriptType,
              isDefault: true,
              birthday: birthday,
            ),
          );
        }
        if (!hasLiquid) {
          created.add(
            await _wallet.createWallet(
              seed: seed,
              network: liquidNetwork,
              scriptType: scriptType,
              isDefault: true,
              birthday: birthday,
            ),
          );
        }
      } catch (_) {
        for (final wallet in created) {
          try {
            await _wallet.deleteWallet(walletId: wallet.id);
          } catch (e, stackTrace) {
            log.severe(
              message: 'CreateDefaultWalletsUsecase: rollback failed',
              error: e,
              trace: stackTrace,
            );
          }
        }
        rethrow;
      }

      return [...existing, ...created];
    } on InconsistentWalletStateException {
      // Its own diagnosis; stringifying it into CreateDefaultWalletsException
      // would hide the one failure whose remedy is wallet recovery (#137).
      rethrow;
    } catch (e) {
      throw CreateDefaultWalletsException(e.toString());
    }
  }

  /// Guards the reuse path: records whose seed is gone would otherwise pass as
  /// "wallets already exist" and blow up later in the first flow that derives
  /// the xprv. Presence check only — no seed material is read or logged.
  ///
  /// When the caller supplied the mnemonic (restore-from-backup) and it is the
  /// mnemonic these records were built from, the missing seed is simply stored
  /// back: that is exactly the recovery the exception tells users to perform,
  /// so it must not itself be rejected as an inconsistent state.
  Future<void> _ensureSeedsPresent(
    List<Wallet> wallets, {
    List<String>? mnemonicWords,
    String? passphrase,
  }) async {
    final fingerprints = wallets.map((w) => w.masterFingerprint).toSet();
    for (final fingerprint in fingerprints) {
      if (await _seedRepository.exists(fingerprint)) continue;

      final restorable =
          mnemonicWords != null &&
          _seedRepository.fingerprintFor(
                mnemonicWords: mnemonicWords,
                passphrase: passphrase,
              ) ==
              fingerprint;
      if (restorable) {
        await _seedRepository.createFromMnemonic(
          mnemonicWords: mnemonicWords,
          passphrase: passphrase,
        );
        continue;
      }

      final inconsistent = InconsistentWalletStateException(
        fingerprint: fingerprint,
      );
      log.severe(
        message:
            'CreateDefaultWalletsUsecase: default wallet records without a seed',
        error: inconsistent,
        trace: StackTrace.current,
      );
      throw inconsistent;
    }
  }
}

class CreateDefaultWalletsException extends BullException {
  CreateDefaultWalletsException(super.message);
}
