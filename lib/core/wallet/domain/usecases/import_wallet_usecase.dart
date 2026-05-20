import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';

class ImportWalletUsecase {
  final SeedRepository _seedRepository;
  final SettingsRepository _settingsRepository;
  final WalletRepository _wallet;
  final WalletLabelReservationPolicy _walletLabelReservationPolicy;

  ImportWalletUsecase({
    required SeedRepository seedRepository,
    required SettingsRepository settingsRepository,
    required WalletRepository walletRepository,
    required WalletLabelReservationPolicy walletLabelReservationPolicy,
  }) : _seedRepository = seedRepository,
       _settingsRepository = settingsRepository,
       _wallet = walletRepository,
       _walletLabelReservationPolicy = walletLabelReservationPolicy;

  Future<Wallet> execute({
    required List<String> mnemonicWords,
    ScriptType scriptType = ScriptType.bip84,
    String passphrase = '',
    String? label,
  }) async {
    try {
      _walletLabelReservationPolicy.throwIfReserved(label);

      // Get the current environment to determine the network
      final settings = await _settingsRepository.fetch();
      final environment = settings.environment;
      final bitcoinNetwork =
          environment.isMainnet
              ? Network.bitcoinMainnet
              : Network.bitcoinTestnet;

      final seed = await _seedRepository.createFromMnemonic(
        mnemonicWords: mnemonicWords,
        passphrase: passphrase,
      );

      final wallet = _wallet.createWallet(
        seed: seed,
        network: bitcoinNetwork,
        scriptType: scriptType,
        isDefault: false,
        sync: false,
        label: label,
      );

      log.fine('Wallet imported');

      return wallet;
    } on ReservedWalletLabelException {
      rethrow;
    } catch (e) {
      throw ImportWalletException(e.toString());
    }
  }
}

class ImportWalletException extends BullException {
  ImportWalletException(super.message);
}
