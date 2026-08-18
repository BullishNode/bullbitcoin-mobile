import 'dart:convert';

import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/invoices/data/models/prepared_private_invoice_create_model.dart';
import 'package:bb_mobile/features/invoices/domain/entities/prepared_private_invoice_create.dart';
import 'package:bb_mobile/features/invoices/domain/repositories/private_invoice_link_repository.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/invoices/domain/value_objects/private_invoice_link.dart';
import 'package:synchronized/synchronized.dart';

class PrivateInvoiceLinkRepositoryImpl implements PrivateInvoiceLinkRepository {
  static const _pendingKey = 'private_invoice_pending_v1';
  static const _quarantineKey = 'private_invoice_pending_v1_corrupt';
  static const _linkPrefix = 'private_invoice_link_v1_';

  final KeyValueStorageDatasource<String> _storage;
  final Uri _expectedOrigin;
  final Lock _lock = Lock();

  PrivateInvoiceLinkRepositoryImpl({
    required KeyValueStorageDatasource<String> storage,
    required Uri expectedOrigin,
  }) : this._(storage, expectedOrigin);

  PrivateInvoiceLinkRepositoryImpl._(this._storage, this._expectedOrigin);

  @override
  Future<PreparedPrivateInvoiceCreate?> getPending() {
    return _lock.synchronized(() async {
      final encoded = await _storage.getValue(_pendingKey);
      if (encoded == null) return null;
      try {
        final json = jsonDecode(encoded);
        if (json is! Map<String, dynamic> || json['version'] != 1) {
          throw const FormatException();
        }
        final operation = json['operation'];
        if (operation is! Map<String, dynamic>) {
          throw const FormatException();
        }
        return PreparedPrivateInvoiceCreateModel.fromJson(operation).toEntity();
      } on Object catch (error, stackTrace) {
        // A torn write, key-store reset, or version downgrade must not brick
        // every future invoice creation (each new create reads this first).
        // Quarantine the unreadable blob for support forensics and treat the
        // store as empty. The in-flight operation it described is
        // unrecoverable either way; its client_request_id remains server-side
        // idempotent if the same operation is rebuilt and retried.
        await _quarantineCorruptPending(encoded, error, stackTrace);
        return null;
      }
    });
  }

  Future<void> _quarantineCorruptPending(
    String encoded,
    Object error,
    StackTrace stackTrace,
  ) async {
    log.severe(
      message: 'Discarding corrupt private invoice pending state',
      error: error,
      trace: stackTrace,
    );
    try {
      await _storage.saveValue(key: _quarantineKey, value: encoded);
    } on Object {
      // Best-effort forensics only; never let quarantine block recovery.
    }
    try {
      await _storage.deleteValue(_pendingKey);
    } on Object catch (deleteError, deleteTrace) {
      log.severe(
        message: 'Failed to delete corrupt private invoice pending state',
        error: deleteError,
        trace: deleteTrace,
      );
    }
  }

  @override
  Future<void> savePending(PreparedPrivateInvoiceCreate operation) {
    return _lock.synchronized(() {
      return _storage.saveValue(
        key: _pendingKey,
        value: jsonEncode({
          'version': 1,
          'operation': PreparedPrivateInvoiceCreateModel.fromEntity(
            operation,
          ).toJson(),
        }),
      );
    });
  }

  @override
  Future<void> deletePending(String clientRequestId) {
    return _lock.synchronized(() async {
      final encoded = await _storage.getValue(_pendingKey);
      if (encoded == null) return;
      try {
        final json = jsonDecode(encoded) as Map<String, dynamic>;
        final operation = json['operation'] as Map<String, dynamic>;
        if (operation['client_request_id'] != clientRequestId) return;
      } on Object catch (error, stackTrace) {
        // Same contract as getPending: an unreadable blob is quarantined and
        // treated as absent rather than wedging the pending lifecycle.
        await _quarantineCorruptPending(encoded, error, stackTrace);
        return;
      }
      await _storage.deleteValue(_pendingKey);
    });
  }

  @override
  Future<PrivateInvoiceLink?> getRetainedLink(InvoiceId invoiceId) async {
    final value = await _storage.getValue('$_linkPrefix${invoiceId.value}');
    if (value == null) return null;
    return PrivateInvoiceLink.stored(
      invoiceId: invoiceId,
      value: value,
      expectedOrigin: _expectedOrigin,
    );
  }

  @override
  Future<void> retainLink(PrivateInvoiceLink link) {
    return _storage.saveValue(
      key: '$_linkPrefix${link.invoiceId.value}',
      value: link.value,
    );
  }
}
