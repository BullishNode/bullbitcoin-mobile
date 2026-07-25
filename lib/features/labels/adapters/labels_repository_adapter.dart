import 'dart:async';

import 'package:bb_mobile/core/storage/storage.dart';
import 'package:bb_mobile/core/utils/logger.dart';
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
    return _mapRowsTolerantly(rows);
  }

  @override
  Future<List<LabelEntity>> fetchByReference(String reference) async {
    final rows = await _database.managers.labels
        .filter((l) => l.reference(reference))
        .get();
    return _mapRowsTolerantly(rows);
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
    return _mapRowsTolerantly(rows);
  }

  /// Maps each row independently and drops (with a log) any row that fails
  /// [LabelEntity]'s validation, instead of letting `.map().toList()`
  /// propagate the first bad row's exception and discard every valid label
  /// in the same query. Every fetch method here feeds every label lookup in
  /// the app (including the wallet transaction list's per-input/output
  /// label enrichment), so one corrupt row used to silently blank out label
  /// data everywhere it was read.
  List<LabelEntity> _mapRowsTolerantly(List<LabelRow> rows) {
    final entities = <LabelEntity>[];
    for (final row in rows) {
      try {
        entities.add(LabelMapper.toLabelEntity(row));
      } catch (e) {
        log.warning(
          'Skipping corrupt label row id=${row.id}: failed to map to a '
          'LabelEntity',
          error: e,
        );
      }
    }
    return entities;
  }
}
