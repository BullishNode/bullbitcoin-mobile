/// Shared contract for handing a rendered CSV to the platform save/share sheet.
/// Lives in core because saving an arbitrary CSV is not owned by any one
/// feature: both the wallet Transactions export and the Get Paid merchant
/// accounting export consume it.
abstract interface class TransactionExportSaver {
  Future<bool> save(String csv);
}
