import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/watch_only_wallet_entity.dart';

class ImportWatchOnlyXpubUsecase {
  final WalletRepository _wallet;
  final WalletLabelReservationPolicy _walletLabelReservationPolicy;

  ImportWatchOnlyXpubUsecase({
    required WalletRepository walletRepository,
    required WalletLabelReservationPolicy walletLabelReservationPolicy,
  }) : _wallet = walletRepository,
       _walletLabelReservationPolicy = walletLabelReservationPolicy;

  Future<Wallet> call({required WatchOnlyXpubEntity watchOnlyXpub}) async {
    try {
      _walletLabelReservationPolicy.throwIfReserved(watchOnlyXpub.label);

      final wallet = await _wallet.importWatchOnlyXpub(
        xpub: watchOnlyXpub.pubkey,
        network: watchOnlyXpub.network,
        scriptType: watchOnlyXpub.scriptType,
        label: watchOnlyXpub.label,
      );

      return wallet;
    } on ReservedWalletLabelException {
      rethrow;
    } catch (e) {
      throw ImportWatchOnlyXpubException(e.toString());
    }
  }
}

class ImportWatchOnlyXpubException extends BullException {
  ImportWatchOnlyXpubException(super.message);
}
