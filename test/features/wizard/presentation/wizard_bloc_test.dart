import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wizard/domain/entity/wizard_choices.dart';
import 'package:bb_mobile/features/wizard/domain/repository/wizard_repository.dart';
import 'package:bb_mobile/features/wizard/domain/wizard_failure.dart';
import 'package:bb_mobile/features/wizard/domain/usecase/mark_wizard_complete_usecase.dart';
import 'package:bb_mobile/features/wizard/domain/usecase/save_metadata_backup_choice_usecase.dart';
import 'package:bb_mobile/features/wizard/domain/usecase/save_pending_wizard_choices_usecase.dart';
import 'package:bb_mobile/features/wizard/presentation/bloc/wizard_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeWizardRepository repository;

  setUp(() => repository = _FakeWizardRepository());

  WizardBloc buildBloc({
    WizardChoices initialChoices = const WizardChoices(),
  }) => WizardBloc(
    savePending: SavePendingWizardChoicesUsecase(repository: repository),
    saveMetadataBackupChoice: SaveMetadataBackupChoiceUsecase(
      repository: repository,
    ),
    markComplete: MarkWizardCompleteUsecase(repository: repository),
    initialChoices: initialChoices,
  );

  test('restores a previously persisted backup choice on restart', () async {
    const restored = WizardChoices(
      metadataBackupEnabled: true,
      touched: {WizardField.metadataBackupEnabled},
    );
    final bloc = buildBloc(initialChoices: restored);
    addTearDown(bloc.close);

    expect(bloc.state.choices, restored);
  });

  test('persists opt-in before publishing the choice as complete', () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);
    final states = bloc.stream.take(2).toList();

    bloc.add(const WizardEvent.metadataBackupPicked(true));

    final emitted = await states;
    expect(emitted, hasLength(2));
    expect(emitted.first.metadataBackupSaving, isTrue);
    expect(emitted.first.choices.metadataBackupEnabled, isNull);
    expect(emitted.last.metadataBackupSaving, isFalse);
    expect(emitted.last.metadataBackupSaveFailed, isFalse);
    expect(emitted.last.choices.metadataBackupEnabled, isTrue);
    expect(
      emitted.last.choices.touched,
      contains(WizardField.metadataBackupEnabled),
    );
    expect(repository.savedMetadataBackupChoices, [true]);
  });

  test(
    'persists explicit opt-out without changing reporting consent',
    () async {
      final bloc = buildBloc(
        initialChoices: const WizardChoices(
          reportingConsent: true,
          touched: {WizardField.reportingConsent},
        ),
      );
      addTearDown(bloc.close);
      final states = bloc.stream.take(2).toList();

      bloc.add(const WizardEvent.metadataBackupPicked(false));

      final emitted = await states;
      expect(emitted, hasLength(2));
      expect(emitted.first.metadataBackupSaving, isTrue);
      expect(emitted.first.choices.reportingConsent, isTrue);
      expect(emitted.first.choices.metadataBackupEnabled, isNull);
      expect(emitted.last.metadataBackupSaving, isFalse);
      expect(emitted.last.metadataBackupSaveFailed, isFalse);
      expect(emitted.last.choices.reportingConsent, isTrue);
      expect(emitted.last.choices.metadataBackupEnabled, isFalse);
      expect(emitted.last.choices.touched, {
        WizardField.reportingConsent,
        WizardField.metadataBackupEnabled,
      });
      expect(repository.savedMetadataBackupChoices, [false]);
    },
  );

  test(
    'keeps the choice unset and exposes retry after persistence fails',
    () async {
      repository.saveFailure = const WizardPersistenceFailure(
        'storage unavailable',
      );
      final bloc = buildBloc();
      addTearDown(bloc.close);
      final states = bloc.stream.take(2).toList();

      bloc.add(const WizardEvent.metadataBackupPicked(true));

      expect(await states, [
        const WizardState(metadataBackupSaving: true),
        const WizardState(metadataBackupSaveFailed: true),
      ]);
      expect(repository.savedChoices, isEmpty);
    },
  );

  test('ignores duplicate choice taps while persistence is active', () async {
    repository.saveGate = Completer<void>();
    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(const WizardEvent.metadataBackupPicked(true));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const WizardEvent.metadataBackupPicked(false));
    await Future<void>.delayed(Duration.zero);

    expect(repository.saveAttempts, 1);
    final finished = bloc.stream.firstWhere(
      (state) => !state.metadataBackupSaving,
    );
    repository.saveGate!.complete();
    await finished;
    expect(bloc.state.choices.metadataBackupEnabled, isTrue);
  });

  test('completion cannot race a backup-choice replacement', () async {
    repository.saveGate = Completer<void>();
    final bloc = buildBloc(
      initialChoices: const WizardChoices(
        metadataBackupEnabled: true,
        reportingConsent: true,
        touched: {
          WizardField.metadataBackupEnabled,
          WizardField.reportingConsent,
        },
      ),
    );
    addTearDown(bloc.close);

    bloc.add(const WizardEvent.metadataBackupPicked(false));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const WizardEvent.completed());
    await Future<void>.delayed(Duration.zero);

    expect(repository.markCompleteCalls, 0);
    expect(repository.savedChoices, isEmpty);
    repository.saveGate!.complete();
    await bloc.stream.firstWhere((state) => !state.metadataBackupSaving);

    expect(bloc.state.finished, isFalse);
    expect(bloc.state.choices.metadataBackupEnabled, isFalse);
    expect(repository.savedMetadataBackupChoices, [false]);
  });

  test('backup choice cannot change while completion is saving', () async {
    repository.pendingSaveGate = Completer<void>();
    final bloc = buildBloc(
      initialChoices: const WizardChoices(
        metadataBackupEnabled: true,
        reportingConsent: true,
        touched: {
          WizardField.metadataBackupEnabled,
          WizardField.reportingConsent,
        },
      ),
    );
    addTearDown(bloc.close);

    bloc.add(const WizardEvent.completed());
    await bloc.stream.firstWhere((state) => state.completionSaving);
    bloc.add(const WizardEvent.metadataBackupPicked(false));
    await Future<void>.delayed(Duration.zero);

    expect(repository.pendingSaveAttempts, 1);
    expect(repository.saveAttempts, 0);
    expect(bloc.state.choices.metadataBackupEnabled, isTrue);

    final finished = bloc.stream.firstWhere((state) => state.finished);
    repository.pendingSaveGate!.complete();
    await finished;

    expect(repository.savedMetadataBackupChoices, isEmpty);
    expect(repository.savedChoices.single.metadataBackupEnabled, isTrue);
  });

  test(
    'failed completion remains retryable and never marks complete',
    () async {
      repository.pendingSaveFailure = Exception('storage unavailable');
      final bloc = buildBloc(
        initialChoices: const WizardChoices(
          metadataBackupEnabled: true,
          reportingConsent: true,
          touched: {
            WizardField.metadataBackupEnabled,
            WizardField.reportingConsent,
          },
        ),
      );
      addTearDown(bloc.close);

      bloc.add(const WizardEvent.completed());
      await bloc.stream.firstWhere((state) => state.completionSaveFailed);

      expect(bloc.state.finished, isFalse);
      expect(bloc.state.completionSaving, isFalse);
      expect(repository.markCompleteCalls, 0);

      repository.pendingSaveFailure = null;
      bloc.add(const WizardEvent.completed());
      await bloc.stream.firstWhere((state) => state.finished);

      expect(repository.markCompleteCalls, 1);
      expect(repository.savedChoices, hasLength(1));
    },
  );
}

class _FakeWizardRepository implements WizardRepository {
  final List<WizardChoices> savedChoices = [];
  final List<bool> savedMetadataBackupChoices = [];
  WizardFailure? saveFailure;
  Exception? pendingSaveFailure;
  Completer<void>? saveGate;
  Completer<void>? pendingSaveGate;
  int saveAttempts = 0;
  int pendingSaveAttempts = 0;
  int markCompleteCalls = 0;

  @override
  Future<void> clearPending() async {}

  @override
  Future<bool> isComplete() async => false;

  @override
  Future<void> markComplete() async => markCompleteCalls++;

  @override
  Future<WizardChoices?> readPending() async => null;

  @override
  Future<Result<void, WizardFailure>> saveMetadataBackupChoice(
    bool enabled,
  ) async {
    saveAttempts++;
    final failure = saveFailure;
    if (failure != null) return Err(failure);
    await saveGate?.future;
    savedMetadataBackupChoices.add(enabled);
    return const Ok(null);
  }

  @override
  Future<void> savePending(WizardChoices choices) async {
    pendingSaveAttempts++;
    final failure = pendingSaveFailure;
    if (failure != null) throw failure;
    await pendingSaveGate?.future;
    savedChoices.add(choices);
  }
}
