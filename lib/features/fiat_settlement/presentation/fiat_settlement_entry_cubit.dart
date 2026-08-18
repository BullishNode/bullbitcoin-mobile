import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/entities/fiat_settlement.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/fiat_settlement_configuration_events.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/get_fiat_settlement_configuration_usecase.dart';
import 'package:bb_mobile/features/fiat_settlement/domain/usecases/is_fiat_settlement_available_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum FiatSettlementEntryStatus { initializing, hidden, ready }

final class FiatSettlementEntryState {
  const FiatSettlementEntryState({
    this.status = FiatSettlementEntryStatus.initializing,
    this.config,
    this.unavailable = false,
  });

  final FiatSettlementEntryStatus status;
  final FiatSettlementProductConfig? config;
  final bool unavailable;
}

/// Owns visibility, configuration reads, and refresh-event handling for the
/// self-contained public entry tile.
final class FiatSettlementEntryCubit extends Cubit<FiatSettlementEntryState> {
  FiatSettlementEntryCubit({
    required this._product,
    required this._availability,
    required this._getConfiguration,
    required this._events,
  }) : super(const FiatSettlementEntryState());

  final FiatSettlementProduct _product;
  final IsFiatSettlementAvailableUsecase _availability;
  final GetFiatSettlementConfigurationUsecase _getConfiguration;
  final FiatSettlementConfigurationEvents _events;

  StreamSubscription<void>? _changes;
  int _readGeneration = 0;

  Future<void> load() async {
    if (!await _availability.execute()) {
      if (!isClosed) {
        emit(
          const FiatSettlementEntryState(
            status: FiatSettlementEntryStatus.hidden,
          ),
        );
      }
      return;
    }
    if (isClosed) return;
    _changes ??= _events.changes.listen((_) => unawaited(refresh()));
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_readGeneration;
    final result = await _getConfiguration.execute();
    if (isClosed || generation != _readGeneration) return;
    switch (result) {
      case Ok(:final value):
        emit(
          FiatSettlementEntryState(
            status: FiatSettlementEntryStatus.ready,
            config: value.configFor(_product),
          ),
        );
      case Err():
        emit(
          const FiatSettlementEntryState(
            status: FiatSettlementEntryStatus.ready,
            unavailable: true,
          ),
        );
    }
  }

  @override
  Future<void> close() async {
    ++_readGeneration;
    await _changes?.cancel();
    return super.close();
  }
}
