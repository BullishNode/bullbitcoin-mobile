import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_failure.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/scoped_settlement_key_port.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/disable_fiat_settlement_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_configuration_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_connection_status_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/set_fiat_settlement_usecase.dart';
import 'package:flutter/foundation.dart';

export 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
export 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_failure.dart';
export 'package:bb_mobile/features/fiat_settlement/domain/scoped_settlement_key_port.dart'
    show FiatSettlementConnectionStatus;

/// Locator-singleton revision counter shared by every [FiatSettlementFacade]
/// instance (the facade itself is factory-registered). It bumps after every
/// SUCCESSFUL configuration mutation so read-only summaries (the entry tiles)
/// can re-read instead of holding the snapshot they took at mount — the
/// activation-time chooser mutates configuration without passing through any
/// tile's own tap round-trip, which is exactly the path that left a freshly
/// created product showing "Bitcoin only" until the screen was revisited.
class FiatSettlementConfigurationRevision extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// The only cross-feature entry point into fiat settlement. Products call it to
/// probe capability, read configuration, and activate/change/disable settlement.
class FiatSettlementFacade {
  final GetFiatSettlementConfigurationUsecase _getConfiguration;
  final GetFiatSettlementConnectionStatusUsecase _getConnectionStatus;
  final SetFiatSettlementUsecase _set;
  final DisableFiatSettlementUsecase _disable;
  final FiatSettlementConfigurationRevision _revision;

  const FiatSettlementFacade({
    required this._getConfiguration,
    required this._getConnectionStatus,
    required this._set,
    required this._disable,
    required FiatSettlementConfigurationRevision revision,
    // ignore: prefer_initializing_formals
  }) : _revision = revision;

  /// Notifies whenever a configuration mutation succeeds. Summaries listen and
  /// re-read; they must never mutate through this.
  Listenable get configurationRevision => _revision;

  Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
  configuration() => _getConfiguration.execute();

  /// Whether this device holds a usable settlement credential, and if not, why.
  /// Local only — no server call and no credential material.
  Future<FiatSettlementConnectionStatus> connectionStatus() =>
      _getConnectionStatus.execute();

  Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>> set({
    required FiatSettlementProduct product,
    required int fiatPercentage,
    required FiatCurrency currency,
  }) async {
    final result = await _set.execute(
      product: product,
      fiatPercentage: fiatPercentage,
      currency: currency,
    );
    if (result is Ok) _revision.bump();
    return result;
  }

  Future<Result<FiatSettlementConfigurationView, FiatSettlementFailure>>
  disable({required FiatSettlementProduct product}) async {
    final result = await _disable.execute(product: product);
    if (result is Ok) _revision.bump();
    return result;
  }

  @override
  String toString() => 'FiatSettlementFacade';
}
