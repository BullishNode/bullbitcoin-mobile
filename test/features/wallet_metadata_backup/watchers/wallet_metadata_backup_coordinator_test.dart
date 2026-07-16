import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/watchers/wallet_metadata_backup_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coalesces a source burst into one dirty write and publication',
    () async {
      final source = _ChangeSource();
      final state = _StateRepository();
      var publications = 0;
      final coordinator = _coordinator(
        source: source,
        state: state,
        debounce: const Duration(milliseconds: 5),
        publish: () async {
          publications++;
          return _unchanged();
        },
      );
      addTearDown(() async {
        await coordinator.dispose();
        await source.close();
      });

      await coordinator.start();
      source.emit();
      source.emit();
      source.emit();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(state.updateCount, 1);
      expect(state.state.dirty, isTrue);
      expect(publications, 1);
    },
  );

  test('metadata apply changes are ignored completely', () async {
    final source = _ChangeSource();
    final state = _StateRepository();
    final guard = WalletMetadataPublicationGuard();
    var publications = 0;
    final coordinator = _coordinator(
      source: source,
      state: state,
      guard: guard,
      publish: () async {
        publications++;
        return _unchanged();
      },
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });
    await coordinator.start();

    await guard.suppressApplyChangesWhile(() async {
      source.emit();
      await Future<void>.delayed(Duration.zero);
    });

    expect(state.updateCount, 0);
    expect(publications, 0);
  });

  test(
    'recovery-session changes become dirty without scheduling network',
    () async {
      final source = _ChangeSource();
      final state = _StateRepository();
      final guard = WalletMetadataPublicationGuard();
      var publications = 0;
      final coordinator = _coordinator(
        source: source,
        state: state,
        guard: guard,
        publish: () async {
          publications++;
          return _unchanged();
        },
      );
      addTearDown(() async {
        await coordinator.dispose();
        await source.close();
      });
      await coordinator.start();

      await guard.suppressPublicationWhile(() async {
        source.emit();
        await Future<void>.delayed(Duration.zero);
      });

      expect(state.state.dirty, isTrue);
      expect(publications, 0);

      await coordinator.publishNow();
      expect(publications, 1);
    },
  );

  test('closing a coordinator recovery session retries dirty work', () async {
    final source = _ChangeSource();
    final state = _StateRepository();
    final guard = WalletMetadataPublicationGuard();
    var publications = 0;
    final coordinator = _coordinator(
      source: source,
      state: state,
      guard: guard,
      debounce: const Duration(milliseconds: 5),
      publish: () async {
        publications++;
        return _unchanged();
      },
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });
    await coordinator.start();

    final session = await coordinator.beginRecoverySession();
    source.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(state.state.dirty, isTrue);
    expect(publications, 0);

    session.close();
    await _waitFor(() => publications == 1);
  });

  test('concurrent manual retries share one publication', () async {
    final source = _ChangeSource();
    final state = _StateRepository();
    final completion =
        Completer<
          Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>
        >();
    var publications = 0;
    final coordinator = _coordinator(
      source: source,
      state: state,
      publish: () {
        publications++;
        return completion.future;
      },
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });

    final first = coordinator.publishNow();
    final second = coordinator.publishNow();
    await Future<void>.delayed(Duration.zero);
    expect(publications, 1);

    completion.complete(_unchanged());
    await Future.wait([first, second]);
    expect(publications, 1);
  });

  test(
    'recovery waits for an active publication and blocks the next',
    () async {
      final source = _ChangeSource();
      final state = _StateRepository();
      final guard = WalletMetadataPublicationGuard();
      final firstPublication =
          Completer<
            Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>
          >();
      var publications = 0;
      final coordinator = _coordinator(
        source: source,
        state: state,
        guard: guard,
        publish: () {
          publications++;
          return publications == 1
              ? firstPublication.future
              : Future.value(_unchanged());
        },
      );
      addTearDown(() async {
        await coordinator.dispose();
        await source.close();
      });

      final publication = coordinator.publishNow();
      await _waitFor(() => publications == 1);
      var sessionAcquired = false;
      final sessionFuture = coordinator.beginRecoverySession().then((session) {
        sessionAcquired = true;
        return session;
      });
      await Future<void>.delayed(Duration.zero);

      expect(guard.isPublicationSuppressed, isTrue);
      expect(sessionAcquired, isFalse);

      firstPublication.complete(_unchanged());
      await publication;
      final session = await sessionFuture;
      final blocked = await coordinator.publishNow();

      expect(
        (blocked
                as Ok<
                  WalletMetadataPublishOutcome,
                  WalletMetadataBackupFailure
                >)
            .value
            .status,
        WalletMetadataPublishStatus.notReady,
      );
      expect(publications, 1);

      session.close();
      await coordinator.publishNow();
      expect(publications, 2);
    },
  );

  test('a thrown active publication does not prevent recovery', () async {
    final source = _ChangeSource();
    final state = _StateRepository();
    final guard = WalletMetadataPublicationGuard();
    final publicationStarted = Completer<void>();
    final publicationFinished = Completer<void>();
    final coordinator = _coordinator(
      source: source,
      state: state,
      guard: guard,
      publish: () async {
        publicationStarted.complete();
        await publicationFinished.future;
        throw Exception('relay transport failed');
      },
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });

    final publication = coordinator.publishNow();
    await publicationStarted.future;
    final sessionFuture = coordinator.beginRecoverySession();
    publicationFinished.complete();

    await expectLater(publication, throwsException);
    final session = await sessionFuture;
    expect(guard.isPublicationSuppressed, isTrue);

    session.close();
  });

  test('a failed dirty write prevents publication', () async {
    final source = _ChangeSource();
    final state = _StateRepository(failUpdates: true);
    var publications = 0;
    final coordinator = _coordinator(
      source: source,
      state: state,
      publish: () async {
        publications++;
        return _unchanged();
      },
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });
    await coordinator.start();
    source.emit();

    final result = await coordinator.publishNow();

    expect(
      result,
      isA<Err<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>(),
    );
    expect(publications, 0);
  });

  test(
    'an unexpected dirty-write exception does not poison later writes',
    () async {
      final source = _ChangeSource();
      final state = _StateRepository(unexpectedFailures: 1);
      var publications = 0;
      final coordinator = _coordinator(
        source: source,
        state: state,
        publish: () async {
          publications++;
          return _unchanged();
        },
      );
      addTearDown(() async {
        await coordinator.dispose();
        await source.close();
      });
      await coordinator.start();

      source.emit();
      final first = await coordinator.publishNow();
      source.emit();
      final second = await coordinator.publishNow();

      expect(
        first,
        isA<Err<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>(),
      );
      expect(
        second,
        isA<Ok<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>(),
      );
      expect(state.updateCount, 2);
      expect(publications, 1);
    },
  );

  test('a change during publication schedules a follow-up attempt', () async {
    final source = _ChangeSource();
    final state = _StateRepository();
    final firstPublication =
        Completer<
          Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>
        >();
    var publications = 0;
    final coordinator = _coordinator(
      source: source,
      state: state,
      debounce: const Duration(milliseconds: 5),
      publish: () {
        publications++;
        return publications == 1
            ? firstPublication.future
            : Future.value(_unchanged());
      },
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });

    await coordinator.start();
    await _waitFor(() => publications == 1);
    source.emit();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    firstPublication.complete(_unchanged());
    await _waitFor(() => publications == 2);

    expect(state.state.dirty, isTrue);
    expect(publications, 2);
  });

  test('failed startup cancels partial subscriptions and can retry', () async {
    final source = _ChangeSource();
    final state = _StateRepository();
    var sources = <WalletMetadataChangeSource>[
      source,
      const _ThrowingChangeSource(),
    ];
    final coordinator = WalletMetadataBackupCoordinator(
      markDirty: MarkWalletMetadataBackupDirtyUsecase(state),
      publishCurrent: () async => _unchanged(),
      guard: WalletMetadataPublicationGuard(),
      sources: () => sources,
      debounce: const Duration(hours: 1),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await source.close();
    });

    await expectLater(coordinator.start(), throwsStateError);
    expect(source.hasListener, isFalse);

    sources = [source];
    await coordinator.start();
    expect(source.hasListener, isTrue);
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw TestFailure('condition was not reached');
}

WalletMetadataBackupCoordinator _coordinator({
  required _ChangeSource source,
  required _StateRepository state,
  required Future<
    Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>
  >
  Function()
  publish,
  WalletMetadataPublicationGuard? guard,
  Duration debounce = const Duration(hours: 1),
}) {
  return WalletMetadataBackupCoordinator(
    markDirty: MarkWalletMetadataBackupDirtyUsecase(state),
    publishCurrent: publish,
    guard: guard ?? WalletMetadataPublicationGuard(),
    sources: () => [source],
    debounce: debounce,
  );
}

Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure> _unchanged() {
  return Ok(
    WalletMetadataPublishOutcome(status: WalletMetadataPublishStatus.unchanged),
  );
}

final class _ChangeSource implements WalletMetadataChangeSource {
  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get changes => _controller.stream;

  bool get hasListener => _controller.hasListener;

  void emit() => _controller.add(null);

  Future<void> close() => _controller.close();
}

final class _ThrowingChangeSource implements WalletMetadataChangeSource {
  const _ThrowingChangeSource();

  @override
  Stream<void> get changes => throw StateError('source unavailable');
}

final class _StateRepository implements WalletMetadataBackupStateRepository {
  WalletMetadataBackupState state = WalletMetadataBackupState.initial;
  final bool failUpdates;
  int unexpectedFailures;
  int updateCount = 0;

  _StateRepository({this.failUpdates = false, this.unexpectedFailures = 0});

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  fetch() async => Ok(state);

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>> update(
    WalletMetadataBackupStateUpdate update,
  ) async {
    updateCount++;
    if (unexpectedFailures > 0) {
      unexpectedFailures--;
      throw Exception('storage unavailable');
    }
    if (failUpdates) {
      return const Err(WalletMetadataBackupStorageFailure());
    }
    state = update(state);
    return Ok(state);
  }
}
