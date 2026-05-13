import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';

abstract class InvoicesPayServicePort {
  Future<CreateInvoiceResult> createInvoice({
    required CreateInvoiceCommand command,
    required NostrKeychainHandle handle,
    required String? bitcoinAddress,
    required String? liquidAddress,
  });

  Future<CancelInvoiceResult> cancelInvoice({
    required CancelInvoiceCommand command,
    required NostrKeychainHandle handle,
  });

  Future<List<Invoice>> listInvoices({
    required ListInvoicesCommand command,
    required NostrKeychainHandle handle,
  });

  Future<InvoiceStatusSnapshot> getInvoiceStatus({required InvoiceId id});
}
