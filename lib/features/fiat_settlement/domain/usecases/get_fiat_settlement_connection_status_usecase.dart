import 'package:bb_mobile/features/fiat_settlement/domain/scoped_settlement_key_port.dart';

/// Reads why the local credential store can or cannot settle to fiat, so a
/// return from the Bull Bitcoin login is answered with what actually happened
/// instead of dropping the merchant back on the form.
class GetFiatSettlementConnectionStatusUsecase {
  final ScopedSettlementKeyPort _scopedKey;

  const GetFiatSettlementConnectionStatusUsecase({required this._scopedKey});

  Future<FiatSettlementConnectionStatus> execute() =>
      _scopedKey.connectionStatus();
}
