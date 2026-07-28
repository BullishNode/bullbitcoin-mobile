import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_health_reminder.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/acknowledge_backup_health_reminder_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/evaluate_backup_health_reminder_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/start_backup_health_action_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'backup_health_reminder_state.dart';

class BackupHealthReminderCubit extends Cubit<BackupHealthReminderState> {
  final EvaluateBackupHealthReminderUsecase _evaluateUsecase;
  final AcknowledgeBackupHealthReminderUsecase _acknowledgeUsecase;
  final StartBackupHealthActionUsecase _startActionUsecase;

  BackupHealthReminderCubit(
    this._evaluateUsecase,
    this._acknowledgeUsecase,
    this._startActionUsecase,
  ) : super(const BackupHealthReminderHidden());

  List<Wallet> _wallets = const [];
  int _arkBalanceSat = 0;
  bool _isEvaluating = false;
  bool _evaluationQueued = false;
  bool _actionInFlight = false;
  int _actionGeneration = 0;
  bool _sessionSuppressed = false;

  Future<void> evaluate({
    required List<Wallet> wallets,
    required int arkBalanceSat,
  }) async {
    _wallets = List.unmodifiable(wallets);
    _arkBalanceSat = arkBalanceSat;
    if (_sessionSuppressed) return;
    if (_actionInFlight) {
      _evaluationQueued = true;
      return;
    }

    if (_isEvaluating) {
      _evaluationQueued = true;
      return;
    }

    _isEvaluating = true;
    try {
      do {
        _evaluationQueued = false;
        final generation = _actionGeneration;
        final result = await _evaluateUsecase.execute(
          wallets: _wallets,
          arkBalanceSat: _arkBalanceSat,
        );
        if (isClosed ||
            _sessionSuppressed ||
            _actionInFlight ||
            generation != _actionGeneration) {
          return;
        }
        switch (result) {
          case Ok(:final value):
            emit(
              value == null
                  ? const BackupHealthReminderHidden()
                  : BackupHealthReminderVisible(decision: value),
            );
          case Err():
            if (state is! BackupHealthReminderVisible) {
              emit(const BackupHealthReminderHidden());
            }
        }
      } while (_evaluationQueued);
    } finally {
      _isEvaluating = false;
    }
  }

  Future<void> reevaluate() async {
    if (_wallets.isEmpty) return;
    await evaluate(wallets: _wallets, arkBalanceSat: _arkBalanceSat);
  }

  Future<void> acknowledge() async {
    final current = state;
    if (current is! BackupHealthReminderVisible || current.isSaving) return;

    _actionInFlight = true;
    _actionGeneration++;
    emit(current.copyWith(isSaving: true, clearFailure: true));
    try {
      final result = await _acknowledgeUsecase.execute(current.decision);
      if (isClosed) return;
      switch (result) {
        case Ok():
          emit(const BackupHealthReminderHidden());
        case Err(:final failure):
          emit(current.copyWith(isSaving: false, failure: failure));
      }
    } finally {
      final failure = switch (state) {
        BackupHealthReminderVisible(:final failure) => failure,
        _ => null,
      };
      _actionInFlight = false;
      await _drainQueuedEvaluation(preserveFailure: failure);
    }
  }

  Future<bool> startRecommendedAction() async {
    final current = state;
    if (current is! BackupHealthReminderVisible || current.isSaving) {
      return false;
    }

    _actionInFlight = true;
    _actionGeneration++;
    emit(current.copyWith(isSaving: true, clearFailure: true));
    try {
      final result = await _startActionUsecase.execute(current.decision);
      if (isClosed) return false;
      switch (result) {
        case Ok():
          _sessionSuppressed = true;
          emit(const BackupHealthReminderHidden());
          return true;
        case Err(:final failure):
          emit(current.copyWith(isSaving: false, failure: failure));
          return false;
      }
    } finally {
      final failure = switch (state) {
        BackupHealthReminderVisible(:final failure) => failure,
        _ => null,
      };
      _actionInFlight = false;
      await _drainQueuedEvaluation(preserveFailure: failure);
    }
  }

  Future<void> _drainQueuedEvaluation({
    BackupSettingsFailure? preserveFailure,
  }) async {
    if (!_evaluationQueued) return;
    _evaluationQueued = false;
    if (_sessionSuppressed || isClosed) return;
    await evaluate(wallets: _wallets, arkBalanceSat: _arkBalanceSat);
    if (preserveFailure == null || isClosed) return;
    final current = state;
    if (current is BackupHealthReminderVisible) {
      emit(current.copyWith(failure: preserveFailure));
    }
  }

  void dismissFailureForSession() {
    final current = state;
    if (current is! BackupHealthReminderVisible ||
        current.failure == null ||
        current.isSaving) {
      return;
    }

    _sessionSuppressed = true;
    emit(const BackupHealthReminderHidden());
  }
}
