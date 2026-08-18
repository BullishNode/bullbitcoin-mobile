import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/labels/adapters/labels_converter_apadater.dart';
import 'package:bb_mobile/features/labels/adapters/labels_repository_adapter.dart';
import 'package:bb_mobile/features/labels/application/usecases/restore_bip329_label_records_usecase.dart';
import 'package:bb_mobile/features/labels/bip329_label_record.dart';
import 'package:bb_mobile/features/labels/domain/label_failure.dart';
import 'package:bb_mobile/features/labels/domain/new_label.dart';
import 'package:bb_mobile/features/labels/domain/primitive/label_type.dart';
import 'package:bb_mobile/features/labels/frameworks/bip329_codec.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDatabase database;
  late DriftLabelsRepositoryAdapter repository;
  late RestoreBip329LabelRecordsUsecase usecase;

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    repository = DriftLabelsRepositoryAdapter(database: database);
    usecase = RestoreBip329LabelRecordsUsecase(
      repository,
      LabelsConverterAdapter(Bip329LabelsCodec()),
    );
  });

  tearDown(() => database.close());

  test('preserves a label changed after recovery classification', () async {
    final remote = Bip329LabelRecord(
      type: 'tx',
      reference: 'a' * 64,
      label: 'existing',
    );
    final extra = Bip329LabelRecord(
      type: 'tx',
      reference: 'b' * 64,
      label: 'local extra',
    );
    _requireOk(await usecase.execute([remote, extra]));
    await repository.store(
      NewLabel(
        type: LabelType.address,
        reference: 'a' * 64,
        label: 'existing',
        origin: '[12345678/84h/0h/0h]',
      ),
    );

    final first = _requireOk(await usecase.execute([remote]));
    final second = _requireOk(await usecase.execute([remote]));
    final exported = Bip329LabelsCodec().encodeMetadataRecords(
      await repository.fetchAll(),
    );

    expect(first.restoredCount, 0);
    expect(first.alreadyPresentCount, 0);
    expect(first.preservedLocalConflictCount, 1);
    expect(first.localProjectionMatchesSnapshot, isFalse);
    expect(second.restoredCount, 0);
    expect(second.alreadyPresentCount, 0);
    expect(second.preservedLocalConflictCount, 1);
    expect(second.localProjectionMatchesSnapshot, isFalse);
    expect(exported, hasLength(2));
    final preserved = exported.singleWhere(
      (record) => record.label == 'existing',
    );
    expect(preserved.type, 'addr');
    expect(preserved.origin, '[12345678/84h/0h/0h]');
  });

  test('reports an unchanged recovered label as already present', () async {
    final remote = Bip329LabelRecord(
      type: 'tx',
      reference: 'a' * 64,
      label: 'existing',
    );
    _requireOk(await usecase.execute([remote]));

    final result = _requireOk(await usecase.execute([remote]));

    expect(result.restoredCount, 0);
    expect(result.alreadyPresentCount, 1);
    expect(result.preservedLocalConflictCount, 0);
    expect(result.localProjectionMatchesSnapshot, isTrue);
  });

  test('rejects duplicate identities before writing', () async {
    final valid = Bip329LabelRecord(
      type: 'tx',
      reference: 'a' * 64,
      label: 'valid',
    );

    final result = await usecase.execute([valid, valid]);

    expect(result, isA<Err<Bip329LabelRestoreSummary, LabelFailure>>());
    expect(await repository.fetchAll(), isEmpty);
  });

  test(
    'keeps unrelated local labels without blocking additive restore',
    () async {
      final desired = Bip329LabelRecord(
        type: 'tx',
        reference: 'a' * 64,
        label: 'remote',
      );
      final localOnly = Bip329LabelRecord(
        type: 'tx',
        reference: 'b' * 64,
        label: 'local',
      );
      _requireOk(await usecase.execute([localOnly]));

      final result = _requireOk(await usecase.execute([desired]));

      expect(result.restoredCount, 1);
      expect(result.preservedLocalConflictCount, 0);
      expect(result.localProjectionMatchesSnapshot, isTrue);
      expect(await repository.fetchAll(), hasLength(2));
    },
  );

  test('emits once only after a successful restore commit', () async {
    var changes = 0;
    final subscription = repository.changes.listen((_) => changes++);
    addTearDown(subscription.cancel);
    final valid = Bip329LabelRecord(
      type: 'tx',
      reference: 'a' * 64,
      label: 'valid',
    );

    _requireOk(await usecase.execute([valid]));
    final invalidResult = await usecase.execute([valid, valid]);

    expect(invalidResult, isA<Err<Bip329LabelRestoreSummary, LabelFailure>>());
    expect(changes, 1);
  });
}

Bip329LabelRestoreSummary _requireOk(
  Result<Bip329LabelRestoreSummary, LabelFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}
