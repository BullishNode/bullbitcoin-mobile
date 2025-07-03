import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/experimental/import_watch_only_wallet/watch_only_wallet_entity.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'import_watch_only_state.freezed.dart';

@freezed
abstract class ImportWatchOnlyState with _$ImportWatchOnlyState {
  const factory ImportWatchOnlyState({
    WatchOnlyWalletEntity? watchOnlyWallet,
    Wallet? importedWallet,
    WalletSource? source,
    @Default('') String input,
    @Default('') String error,
  }) = _ImportWatchOnlyState;

  const ImportWatchOnlyState._();
}
