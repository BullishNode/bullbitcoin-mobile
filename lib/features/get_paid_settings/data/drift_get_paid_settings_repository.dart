import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';

/// Drift-backed [GetPaidSettingsRepository]. The preference is a single row
/// (id == 1); an absent row reads as the defaults (backup on, disclosure not
/// yet acknowledged). Setters read-modify-write the full row so the two flags
/// never clobber each other.
class DriftGetPaidSettingsRepository implements GetPaidSettingsRepository {
  static const int _rowId = 1;

  final SqliteDatabase _database;

  DriftGetPaidSettingsRepository({required this._database});

  @override
  Future<GetPaidSettings> fetch() async {
    try {
      return _toEntity(await _readRow());
    } catch (e) {
      throw GetPaidSettingsStorageException(cause: e);
    }
  }

  @override
  Future<void> setAutomatedBackupEnabled(bool enabled) async {
    try {
      final current = _toEntity(await _readRow());
      await _writeRow(
        automatedBackupEnabled: enabled,
        backupDisclosureAcknowledged: current.backupDisclosureAcknowledged,
      );
    } catch (e) {
      throw GetPaidSettingsStorageException(cause: e);
    }
  }

  @override
  Future<void> setBackupDisclosureAcknowledged({
    required bool automatedBackupEnabled,
  }) async {
    try {
      await _writeRow(
        automatedBackupEnabled: automatedBackupEnabled,
        backupDisclosureAcknowledged: true,
      );
    } catch (e) {
      throw GetPaidSettingsStorageException(cause: e);
    }
  }

  Future<GetPaidSettingsRow?> _readRow() {
    return (_database.select(
      _database.getPaidSettings,
    )..where((t) => t.id.equals(_rowId))).getSingleOrNull();
  }

  Future<void> _writeRow({
    required bool automatedBackupEnabled,
    required bool backupDisclosureAcknowledged,
  }) async {
    await _database
        .into(_database.getPaidSettings)
        .insertOnConflictUpdate(
          GetPaidSettingsRow(
            id: _rowId,
            automatedBackupEnabled: automatedBackupEnabled,
            backupDisclosureAcknowledged: backupDisclosureAcknowledged,
          ),
        );
  }

  GetPaidSettings _toEntity(GetPaidSettingsRow? row) {
    if (row == null) {
      return const GetPaidSettings(
        automatedBackupEnabled: true,
        backupDisclosureAcknowledged: false,
      );
    }
    return GetPaidSettings(
      automatedBackupEnabled: row.automatedBackupEnabled,
      backupDisclosureAcknowledged: row.backupDisclosureAcknowledged,
    );
  }
}
