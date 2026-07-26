import 'dart:async';

import 'package:bb_mobile/core/storage/storage.dart';
import 'package:bb_mobile/features/labels/adapters/label_mapper.dart';
import 'package:bb_mobile/features/labels/application/labels_repository_port.dart';
import 'package:bb_mobile/features/labels/domain/label_entity.dart';
import 'package:bb_mobile/features/labels/domain/new_label.dart';

class DriftLabelsRepositoryAdapter implements LabelsRepositoryPort {
  final SqliteDatabase _database;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  DriftLabelsRepositoryAdapter({required this._database});

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<LabelEntity> store(NewLabel newLabel) async {
    _validate(newLabel);
    final stored = await _store(newLabel);
    _changes.add(null);
    return stored;
  }

  @override
  Future<void> storeAll(List<NewLabel> labels) async {
    for (final label in labels) {
      _validate(label);
    }
    await _database.transaction(() async {
      for (final label in labels) {
        await _store(label);
      }
    });
    if (labels.isNotEmpty) _changes.add(null);
  }

  @override
  Future<LabelRecoveryWriteResult> restoreMissing(List<NewLabel> labels) async {
    final identities = <(String, String)>{};
    for (final label in labels) {
      _validate(label);
      if (!identities.add((label.label, label.reference))) {
        throw const FormatException('Duplicate label recovery identity');
      }
    }

    final result = await _database.transaction(() async {
      var restoredCount = 0;
      var alreadyPresentCount = 0;
      var preservedLocalConflictCount = 0;
      for (final label in labels) {
        final query = _database.select(_database.labels)
          ..where(
            (row) =>
                row.label.equals(label.label) &
                row.reference.equals(label.reference),
          );
        final currentRow = await query.getSingleOrNull();
        if (currentRow == null) {
          await _database
              .into(_database.labels)
              .insert(LabelMapper.newLabelEntityToCompanion(label));
          restoredCount++;
          continue;
        }
        final current = LabelMapper.toLabelEntity(currentRow);
        if (_sameLabel(current, label)) {
          alreadyPresentCount++;
        } else {
          preservedLocalConflictCount++;
        }
      }
      return LabelRecoveryWriteResult(
        restoredCount: restoredCount,
        alreadyPresentCount: alreadyPresentCount,
        preservedLocalConflictCount: preservedLocalConflictCount,
      );
    });
    if (result.restoredCount > 0) _changes.add(null);
    return result;
  }

  Future<LabelEntity> _store(NewLabel newLabel) async {
    final companion = LabelMapper.newLabelEntityToCompanion(newLabel);
    final id = await _database
        .into(_database.labels)
        .insert(
          companion,
          onConflict: DoUpdate(
            (old) => companion,
            target: [_database.labels.label, _database.labels.reference],
          ),
        );

    return LabelEntity(
      id: id,
      type: newLabel.type,
      label: newLabel.label,
      reference: newLabel.reference,
      origin: newLabel.origin,
    );
  }

  void _validate(NewLabel label) {
    LabelEntity(
      id: label.id ?? 0,
      type: label.type,
      label: label.label,
      reference: label.reference,
      origin: label.origin,
    );
  }

  @override
  Future<List<LabelEntity>> fetchByLabel(String label) async {
    final rows = await _database.managers.labels
        .filter((l) => l.label(label))
        .get();
    return rows.map((row) => LabelMapper.toLabelEntity(row)).toList();
  }

  @override
  Future<List<LabelEntity>> fetchByReference(String reference) async {
    final rows = await _database.managers.labels
        .filter((l) => l.reference(reference))
        .get();
    return rows.map((row) => LabelMapper.toLabelEntity(row)).toList();
  }

  @override
  Future<LabelEntity?> fetchById(int id) async {
    final row = await _database.managers.labels
        .filter((l) => l.id(id))
        .getSingleOrNull();
    return row != null ? LabelMapper.toLabelEntity(row) : null;
  }

  @override
  Future<void> trash(int id) async {
    final deleted = await _database.managers.labels
        .filter((l) => l.id(id))
        .delete();
    if (deleted > 0) _changes.add(null);
  }

  @override
  Future<List<LabelEntity>> fetchAll() async {
    final rows = await _database.managers.labels.get();
    return rows.map((row) => LabelMapper.toLabelEntity(row)).toList();
  }
}

bool _sameLabel(LabelEntity current, NewLabel recovered) =>
    current.type == recovered.type &&
    current.reference == recovered.reference &&
    current.label == recovered.label &&
    current.origin == recovered.origin;
