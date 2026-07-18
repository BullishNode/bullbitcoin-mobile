import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/swaps/domain/entity/swap.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_swap_limits_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/watch_swap_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/create_send_swap_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/update_paid_send_swap_usecase.dart';
import 'package:bb_mobile/locator.dart';

const bullstrReturnAddress = 'bullstr@pay.bitcoinjungle.app';

class BullstrLiquidReturnResult {
  final String swapId;
  final String lockupTxid;
  final int recipientAmountSat;
  final int lockupAmountSat;
  final int lockupFeeSat;
  final int totalFeeSat;
  final int residualSat;
  final SwapStatus terminalStatus;
  final DateTime? recipientPaidAt;

  const BullstrLiquidReturnResult({
    required this.swapId,
    required this.lockupTxid,
    required this.recipientAmountSat,
    required this.lockupAmountSat,
    required this.lockupFeeSat,
    required this.totalFeeSat,
    required this.residualSat,
    required this.terminalStatus,
    required this.recipientPaidAt,
  });
}

Future<BullstrLiquidReturnResult> returnLiquidToBullstr({
  required String walletId,
  required int maxFeeSat,
  int maximumResidualSat = 100,
}) async {
  if (maxFeeSat <= 0 || maxFeeSat > 5000) {
    throw ArgumentError.value(maxFeeSat, 'maxFeeSat');
  }

  final wallet = await locator<WalletRepository>().getWallet(
    walletId,
    sync: true,
  );
  if (wallet == null || !wallet.isLiquid) {
    throw StateError('Bullstr return requires a synced Liquid wallet');
  }
  final availableSat = wallet.balanceSat.toInt();
  final (limits, fees) = await locator<GetSwapLimitsUsecase>().execute(
    type: SwapType.liquidToLightning,
  );
  final feeCushionSat = (fees.lockupFee ?? 0) + 20;
  final fundingBudgetSat = availableSat - feeCushionSat;
  final recipientAmountSat = _largestReceivableAmount(
    fundingBudgetSat: fundingBudgetSat,
    limits: limits,
    fees: fees,
  );

  final swap = await locator<CreateSendSwapUsecase>().execute(
    walletId: walletId,
    type: SwapType.liquidToLightning,
    lnAddress: bullstrReturnAddress,
    amountSat: recipientAmountSat,
  );
  final pset = await locator<PrepareLiquidSendUsecase>().execute(
    walletId: walletId,
    address: swap.paymentAddress,
    amountSat: swap.paymentAmount,
    feeRate: NetworkFee.relativeFromSatPerVbyte(0.1),
  );
  final lockupFeeSat = await locator<CalculateLiquidAbsoluteFeesUsecase>()
      .execute(pset: pset);
  if (lockupFeeSat > maxFeeSat) {
    throw StateError(
      'Bullstr return fee $lockupFeeSat exceeds the $maxFeeSat sat cap',
    );
  }
  final residualSat = availableSat - swap.paymentAmount - lockupFeeSat;
  if (residualSat < 0) {
    throw StateError('Bullstr return exceeds the available Liquid balance');
  }
  if (residualSat > maximumResidualSat) {
    throw StateError(
      'Bullstr return would leave $residualSat sat, above the '
      '$maximumResidualSat sat ceiling',
    );
  }
  final totalFeeSat = swap.paymentAmount + lockupFeeSat - recipientAmountSat;
  if (totalFeeSat > maxFeeSat) {
    throw StateError(
      'Bullstr return total fee $totalFeeSat exceeds the $maxFeeSat sat cap',
    );
  }

  final signed = await locator<SignLiquidTxUsecase>().execute(
    pset: pset,
    walletId: walletId,
  );
  final lockupTxid = await locator<BroadcastLiquidTransactionUsecase>().execute(
    signed,
    isTestnet: wallet.network.isTestnet,
  );
  await locator<UpdatePaidSendSwapUsecase>().execute(
    txid: lockupTxid,
    swapId: swap.id,
    absoluteFees: lockupFeeSat,
  );

  final terminal = await locator<WatchSwapUsecase>()
      .execute(swap.id)
      .firstWhere(
        (candidate) =>
            candidate.status == SwapStatus.paid &&
                candidate.completionTime != null ||
            candidate.status == SwapStatus.canCoop ||
            candidate.status == SwapStatus.completed ||
            candidate.status == SwapStatus.refunded ||
            candidate.status == SwapStatus.expired ||
            candidate.status == SwapStatus.failed,
      )
      .timeout(const Duration(minutes: 10));
  if (terminal.status != SwapStatus.paid &&
      terminal.status != SwapStatus.canCoop &&
      terminal.status != SwapStatus.completed) {
    throw StateError(
      'Bullstr return did not pay the Lightning invoice: ${terminal.status}',
    );
  }

  return BullstrLiquidReturnResult(
    swapId: swap.id,
    lockupTxid: lockupTxid,
    recipientAmountSat: recipientAmountSat,
    lockupAmountSat: swap.paymentAmount,
    lockupFeeSat: lockupFeeSat,
    totalFeeSat: totalFeeSat,
    residualSat: residualSat,
    terminalStatus: terminal.status,
    recipientPaidAt: terminal.completionTime,
  );
}

int _largestReceivableAmount({
  required int fundingBudgetSat,
  required SwapLimits limits,
  required SwapFees fees,
}) {
  var low = limits.min;
  var high = fundingBudgetSat < limits.max ? fundingBudgetSat : limits.max;
  var best = 0;
  while (low <= high) {
    final candidate = low + ((high - low) ~/ 2);
    final lockupAmount = fees.calculateSwapAmountFromReceivableAmount(
      candidate,
    );
    if (lockupAmount <= fundingBudgetSat) {
      best = candidate;
      low = candidate + 1;
    } else {
      high = candidate - 1;
    }
  }
  if (best == 0) {
    throw StateError('Liquid balance is below the live swap minimum');
  }
  return best;
}
