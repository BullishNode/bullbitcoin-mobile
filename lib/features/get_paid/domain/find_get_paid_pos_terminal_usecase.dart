import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';

/// Get Paid's narrow wrapper over the Point of Sale boundary: probe the terminal
/// for a nym and classify the read as found / confirmed-absent / unavailable. A
/// failure never reads as absent, so the hub cannot show "not configured" for a
/// terminal it simply could not reach.
class FindGetPaidPosTerminalUsecase {
  final PosFacade _pos;

  const FindGetPaidPosTerminalUsecase({required this._pos});

  Future<GetPaidProductProbe<GetPaidPosTerminalSnapshot>> execute({
    required String nym,
  }) async {
    try {
      final terminal = await _pos.find(nym: nym);
      return terminal == null
          ? const GetPaidProductAbsent()
          : GetPaidProductFound(
              GetPaidPosTerminalSnapshot(
                terminalUrl: terminal.terminalUrl,
                isArchived: terminal.isArchived,
              ),
            );
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid Point of Sale lookup failed',
        error: error,
        trace: trace,
      );
      return const GetPaidProductUnavailable();
    }
  }
}
