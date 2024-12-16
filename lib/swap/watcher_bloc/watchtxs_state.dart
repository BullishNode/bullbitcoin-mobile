import 'package:bb_mobile/_model/swap.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'watchtxs_state.freezed.dart';

@freezed
class WatchTxsState with _$WatchTxsState {
  const factory WatchTxsState({
    @Default('') String errClaimingSwap,
    @Default('') String errRefundingSwap,
    @Default(false) bool claimingSwap,
    @Default(false) bool refundingSwap,
    @Default('') String errWatchingInvoice,
    @Default([]) List<String> listeningTxs,
    @Default([]) List<String> claimedSwapTxs,
    @Default([]) List<String> claimingSwapTxIds,
    @Default([]) List<String> refundedSwapTxs,
    @Default([]) List<String> refundingSwapTxIds,
    SwapTx? updatedSwapTx,
    // SwapTx? txPaid,
    // Wallet? syncWallet,
  }) = _WatchTxsState;
  const WatchTxsState._();

  bool isListening(String swap) => listeningTxs.any((_) => _ == swap);

  bool isListeningId(String id) => listeningTxs.any((_) => _ == id);

  bool swapClaimed(String swap) => claimedSwapTxs.any((_) => _ == swap);

  bool isClaiming(String swap) => claimingSwapTxIds.any((_) => _ == swap);

  List<String>? addClaiming(String id) =>
      isClaiming(id) ? null : [id, ...claimingSwapTxIds];

  List<String> removeClaiming(String id) {
    final List<String> updatedList = List<String>.from(claimingSwapTxIds)
      ..remove(id);
    return updatedList;
  }

  bool swapRefunded(String swap) => refundedSwapTxs.any((_) => _ == swap);

  bool isRefunding(String swap) => refundingSwapTxIds.any((_) => _ == swap);

  List<String>? addRefunding(String id) =>
      isRefunding(id) ? null : [id, ...refundingSwapTxIds];

  List<String> removeRefunding(String id) {
    final List<String> updatedList = List<String>.from(refundingSwapTxIds)
      ..remove(id);
    return updatedList;
  }

  List<String> removeListeningTx(String id) {
    final List<String> updatedList = List<String>.from(listeningTxs)
      ..remove(id);
    return updatedList;
  }
}
