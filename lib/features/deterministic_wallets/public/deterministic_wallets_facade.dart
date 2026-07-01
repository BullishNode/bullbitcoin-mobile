import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets_error.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/prepare_deterministic_wallets_usecase.dart';

export 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
export 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets_error.dart';

class DeterministicWalletsFacade {
  final PrepareDeterministicWalletsUsecase _prepareWallets;

  const DeterministicWalletsFacade({required this._prepareWallets});

  Future<PreparedDeterministicWallets> prepare(
    DeterministicWalletsRequest request,
  ) async {
    try {
      return await _prepareWallets.execute(request);
    } on DeterministicWalletException {
      rethrow;
    } catch (_) {
      throw DeterministicWalletException.generic();
    }
  }

  Future<void> rollbackCreatedWallets(PreparedDeterministicWallets result) {
    return _prepareWallets.rollbackCreatedWallets(result);
  }
}
