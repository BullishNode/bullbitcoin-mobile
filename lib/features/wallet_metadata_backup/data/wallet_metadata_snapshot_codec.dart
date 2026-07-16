import 'dart:convert';

import 'package:bb_mobile/features/wallet_metadata_backup/data/mappers/wallet_metadata_snapshot_mapper.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/models/wallet_metadata_snapshot_model.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_backup_format_exception.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:crypto/crypto.dart';

final class WalletMetadataSnapshotCodec {
  static const _recordKeys = {
    'type',
    'version',
    'scope',
    'recordId',
    'payload',
  };
  static const _rootKeys = {
    'contentType',
    'envelopeVersion',
    'parentFingerprint',
    'snapshotId',
    'revision',
    'createdAt',
    'recordsHash',
    'recordCount',
    'sections',
    'records',
    'chunks',
  };
  static const _sectionKeys = {
    'type',
    'versions',
    'recordCount',
    'recordsHash',
  };
  static const _chunkReferenceKeys = {
    'index',
    'eventId',
    'd',
    'recordCount',
    'ciphertextHash',
  };
  static const _chunkKeys = {
    'contentType',
    'envelopeVersion',
    'snapshotId',
    'index',
    'chunkCount',
    'recordCount',
    'records',
  };

  const WalletMetadataSnapshotCodec();

  String encodeRecord(WalletMetadataRecord record) {
    final model = WalletMetadataSnapshotMapper.recordToModel(record);
    final encoded = jsonEncode(model.toJson());
    _validateRecordSize(encoded);
    return encoded;
  }

  WalletMetadataRecord decodeRecord(String payload) {
    try {
      _validateRecordSize(payload);
      final json = _decodeObject(payload);
      final model = _parseRecordModel(json);
      final record = WalletMetadataSnapshotMapper.recordToEntity(model);
      if (encodeRecord(record) != payload) {
        _throwMalformed('wallet metadata record is not canonical JSON');
      }
      return record;
    } on WalletMetadataBackupFormatException {
      rethrow;
    } on FormatException catch (e) {
      _throwMalformed('wallet metadata record is malformed', cause: e);
    } on ArgumentError catch (e) {
      _throwMalformed('wallet metadata record is invalid', cause: e);
    }
  }

  String encodeRoot(WalletMetadataSnapshotRoot root) {
    final model = WalletMetadataSnapshotMapper.rootToModel(root);
    for (final record in model.records) {
      _validateRecordSize(jsonEncode(record.toJson()));
    }
    final encoded = jsonEncode(model.toJson());
    _validateSnapshotSize(encoded);
    return encoded;
  }

  WalletMetadataSnapshotRoot decodeRoot(String payload) {
    try {
      _validateSnapshotSize(payload);
      final json = _decodeObject(payload);
      final envelopeVersion = _int(json, 'envelopeVersion');
      _validateEnvelopeVersion(envelopeVersion);
      _expectKeys(json, _rootKeys, 'root');
      final records = _list(json, 'records')
          .map((value) => _parseRecordModel(_object(value, 'record')))
          .toList(growable: false);
      for (final record in records) {
        _validateRecordSize(jsonEncode(record.toJson()));
      }
      final model = WalletMetadataSnapshotRootModel(
        contentType: _string(json, 'contentType'),
        envelopeVersion: envelopeVersion,
        parentFingerprint: _string(json, 'parentFingerprint'),
        snapshotId: _string(json, 'snapshotId'),
        revision: _int(json, 'revision'),
        createdAt: _int(json, 'createdAt'),
        recordsHash: _string(json, 'recordsHash'),
        recordCount: _int(json, 'recordCount'),
        sections: _list(json, 'sections')
            .map((value) => _parseSectionModel(_object(value, 'section')))
            .toList(growable: false),
        records: records,
        chunks: _list(json, 'chunks')
            .map(
              (value) =>
                  _parseChunkReferenceModel(_object(value, 'chunk reference')),
            )
            .toList(growable: false),
      );
      final root = WalletMetadataSnapshotMapper.rootToEntity(model);
      if (encodeRoot(root) != payload) {
        _throwMalformed('wallet metadata root is not canonical JSON');
      }
      return root;
    } on WalletMetadataBackupFormatException {
      rethrow;
    } on FormatException catch (e) {
      _throwMalformed('wallet metadata root is malformed', cause: e);
    } on ArgumentError catch (e) {
      _throwMalformed('wallet metadata root is invalid', cause: e);
    }
  }

  String encodeChunk(WalletMetadataSnapshotChunk chunk) {
    final model = WalletMetadataSnapshotMapper.chunkToModel(chunk);
    final records = model.records
        .map((record) {
          final json = record.toJson();
          _validateRecordSize(jsonEncode(json));
          return json;
        })
        .toList(growable: false);
    final encoded = jsonEncode({
      'contentType': model.contentType,
      'envelopeVersion': model.envelopeVersion,
      'snapshotId': model.snapshotId,
      'index': model.index,
      'chunkCount': model.chunkCount,
      'recordCount': model.recordCount,
      'records': records,
    });
    _validateSnapshotSize(encoded);
    return encoded;
  }

  WalletMetadataSnapshotChunk decodeChunk(String payload) {
    try {
      _validateSnapshotSize(payload);
      final json = _decodeObject(payload);
      final envelopeVersion = _int(json, 'envelopeVersion');
      _validateEnvelopeVersion(envelopeVersion);
      _expectKeys(json, _chunkKeys, 'chunk');
      final records = _list(json, 'records')
          .map((value) => _parseRecordModel(_object(value, 'record')))
          .toList(growable: false);
      for (final record in records) {
        _validateRecordSize(jsonEncode(record.toJson()));
      }
      final model = WalletMetadataSnapshotChunkModel(
        contentType: _string(json, 'contentType'),
        envelopeVersion: envelopeVersion,
        snapshotId: _string(json, 'snapshotId'),
        index: _int(json, 'index'),
        chunkCount: _int(json, 'chunkCount'),
        recordCount: _int(json, 'recordCount'),
        records: records,
      );
      final chunk = WalletMetadataSnapshotMapper.chunkToEntity(model);
      if (encodeChunk(chunk) != payload) {
        _throwMalformed('wallet metadata chunk is not canonical JSON');
      }
      return chunk;
    } on WalletMetadataBackupFormatException {
      rethrow;
    } on FormatException catch (e) {
      _throwMalformed('wallet metadata chunk is malformed', cause: e);
    } on ArgumentError catch (e) {
      _throwMalformed('wallet metadata chunk is invalid', cause: e);
    }
  }

  String canonicalRecordsJson(Iterable<WalletMetadataRecord> records) {
    final sorted = _sortedUniqueRecords(records);
    return jsonEncode(
      sorted
          .map(WalletMetadataSnapshotMapper.recordToModel)
          .map((record) => record.toJson())
          .toList(growable: false),
    );
  }

  String recordsHash(Iterable<WalletMetadataRecord> records) {
    return sha256
        .convert(utf8.encode(canonicalRecordsJson(records)))
        .toString();
  }

  String contentHash({
    required Iterable<WalletMetadataRecord> records,
    required Iterable<WalletMetadataSection> sections,
  }) {
    final sortedSections = sections.toList(growable: false)
      ..sort((left, right) => left.type.compareTo(right.type));
    if (sortedSections.map((section) => section.type).toSet().length !=
        sortedSections.length) {
      _throwMalformed('wallet metadata sections contain a duplicate type');
    }
    final content = jsonEncode({
      'recordsHash': recordsHash(records),
      'sections': sortedSections
          .map(WalletMetadataSnapshotMapper.sectionToModel)
          .map((section) => section.toJson())
          .toList(growable: false),
    });
    return sha256.convert(utf8.encode(content)).toString();
  }

  void validateRootRecords({
    required WalletMetadataSnapshotRoot root,
    required List<WalletMetadataRecord> records,
  }) {
    final canonicalRecords = _sortedUniqueRecords(records);
    if (canonicalRecords.length != records.length ||
        root.recordCount != records.length ||
        root.recordsHash != recordsHash(records)) {
      _throwMalformed('wallet metadata root record integrity is invalid');
    }
    for (var index = 0; index < records.length; index++) {
      if (records[index].identity != canonicalRecords[index].identity) {
        _throwMalformed('wallet metadata records are not globally canonical');
      }
    }

    final recordsByType = <String, List<WalletMetadataRecord>>{};
    for (final record in records) {
      recordsByType.putIfAbsent(record.type, () => []).add(record);
    }
    for (final section in root.sections) {
      final sectionRecords = recordsByType.remove(section.type) ?? const [];
      final actualVersions = sectionRecords
          .map((record) => record.version)
          .toSet();
      if (section.recordCount != sectionRecords.length ||
          section.recordsHash != recordsHash(sectionRecords) ||
          actualVersions.any(
            (version) => !section.versions.contains(version),
          )) {
        _throwMalformed('wallet metadata section integrity is invalid');
      }
    }
    if (recordsByType.isNotEmpty) {
      _throwMalformed('wallet metadata records lack a section declaration');
    }
  }

  WalletMetadataRecordModel _parseRecordModel(Map<String, Object?> json) {
    _expectKeys(json, _recordKeys, 'record');
    return WalletMetadataRecordModel(
      type: _string(json, 'type'),
      version: _int(json, 'version'),
      scope: _object(json['scope'], 'scope'),
      recordId: _string(json, 'recordId'),
      payload: _object(json['payload'], 'payload'),
    );
  }

  WalletMetadataSectionModel _parseSectionModel(Map<String, Object?> json) {
    _expectKeys(json, _sectionKeys, 'section');
    return WalletMetadataSectionModel(
      type: _string(json, 'type'),
      versions: _list(json, 'versions')
          .map((value) => _integerValue(value, 'versions'))
          .toList(growable: false),
      recordCount: _int(json, 'recordCount'),
      recordsHash: _string(json, 'recordsHash'),
    );
  }

  WalletMetadataChunkReferenceModel _parseChunkReferenceModel(
    Map<String, Object?> json,
  ) {
    _expectKeys(json, _chunkReferenceKeys, 'chunk reference');
    return WalletMetadataChunkReferenceModel(
      index: _int(json, 'index'),
      eventId: _string(json, 'eventId'),
      dTag: _string(json, 'd'),
      recordCount: _int(json, 'recordCount'),
      ciphertextHash: _string(json, 'ciphertextHash'),
    );
  }

  List<WalletMetadataRecord> _sortedUniqueRecords(
    Iterable<WalletMetadataRecord> records,
  ) {
    final sorted = records.toList(growable: false)..sort();
    if (sorted.length > WalletMetadataBackupLimits.maxLogicalRecords) {
      _throwResourceLimit('wallet metadata record count exceeds the limit');
    }
    final identities = <String>{};
    for (final record in sorted) {
      if (!identities.add(record.identity)) {
        _throwMalformed('wallet metadata records contain a duplicate identity');
      }
      final model = WalletMetadataSnapshotMapper.recordToModel(record);
      _validateRecordSize(jsonEncode(model.toJson()));
    }
    return sorted;
  }

  Map<String, Object?> _decodeObject(String payload) {
    final decoded = jsonDecode(payload);
    return _object(decoded, 'document');
  }

  void _validateEnvelopeVersion(int version) {
    if (version > WalletMetadataBackupLimits.maxSignedInt64) {
      _throwResourceLimit('wallet metadata envelope version is too large');
    }
    if (version > walletMetadataEnvelopeVersion) {
      throw WalletMetadataBackupFormatException(
        WalletMetadataBackupFormatExceptionType.unsupportedEnvelopeVersion,
        'wallet metadata envelope version is unsupported',
        envelopeVersion: version,
      );
    }
    if (version != walletMetadataEnvelopeVersion) {
      _throwMalformed('wallet metadata envelope version is invalid');
    }
  }

  void _validateRecordSize(String payload) {
    if (utf8.encode(payload).length >
        WalletMetadataBackupLimits.maxRecordCanonicalBytes) {
      _throwResourceLimit('wallet metadata record exceeds the byte limit');
    }
  }

  void _validateSnapshotSize(String payload) {
    if (utf8.encode(payload).length >
        WalletMetadataBackupLimits.maxDecryptedSnapshotBytes) {
      _throwResourceLimit('wallet metadata snapshot exceeds the byte limit');
    }
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  _throwMalformed('wallet metadata field $key must be a string');
}

int _int(Map<String, Object?> json, String key) {
  return _integerValue(json[key], key);
}

int _integerValue(Object? value, String description) {
  if (value is int) return value;
  _throwMalformed('wallet metadata field $description must be an integer');
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List) return List<Object?>.from(value);
  _throwMalformed('wallet metadata field $key must be a list');
}

Map<String, Object?> _object(Object? value, String description) {
  if (value is! Map) {
    _throwMalformed('wallet metadata $description must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      _throwMalformed('wallet metadata $description keys must be strings');
    }
    result[key] = entry.value;
  }
  return result;
}

void _expectKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String description,
) {
  final keys = json.keys.toSet();
  if (keys.length != expected.length || !keys.containsAll(expected)) {
    _throwMalformed('wallet metadata $description fields are invalid');
  }
}

Never _throwMalformed(String message, {Object? cause}) {
  throw WalletMetadataBackupFormatException(
    WalletMetadataBackupFormatExceptionType.malformed,
    message,
    cause: cause,
  );
}

Never _throwResourceLimit(String message) {
  throw WalletMetadataBackupFormatException(
    WalletMetadataBackupFormatExceptionType.resourceLimit,
    message,
  );
}
