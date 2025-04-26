import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_repository.dart';

class WatchStartedWalletSyncsUsecase {
  final WalletRepository _walletRepository;

  WatchStartedWalletSyncsUsecase({
    required WalletRepository walletRepository,
  }) : _walletRepository = walletRepository;

  Stream<Wallet> execute({
    String? walletId,
  }) {
    try {
      if (walletId != null) {
        return _walletRepository.walletSyncStartedStream
            .where((wallet) => wallet.id == walletId);
      } else {
        return _walletRepository.walletSyncStartedStream;
      }
    } catch (e) {
      throw WatchStartedWalletSyncsException(e.toString());
    }
  }
}

class WatchStartedWalletSyncsException implements Exception {
  final String message;

  WatchStartedWalletSyncsException(this.message);
}
