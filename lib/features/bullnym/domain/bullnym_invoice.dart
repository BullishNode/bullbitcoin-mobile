// Wire DTOs for the signed recipient-invoice endpoints (server
// `src/invoice.rs`). JSON keys mirror the server EXACTLY (snake_case, incl.
// the `pageSize` query/response rename the server pins in `ListSignedQuery` /
// `ListInvoicesResponse`). These are data-layer shapes only; the `invoices`
// feature maps them to its own domain entities and never re-exports them.

/// The raw `invoice-create` field values, in the server's storage order. The
/// signer emits every field (absent optionals as the empty string) so the
/// signed byte layout is stable; this object is the single source those
/// ordered fields are built from (`buildInvoiceCreatePayloadFields`).
class BullnymCreateInvoiceFields {
  final int? amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? recipientName;
  final String? invoiceNumber;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final String? bitcoinAddress;
  final String? liquidAddress;
  final String? liquidBlindingKeyHex;
  final int? expiresAtUnix;

  const BullnymCreateInvoiceFields({
    this.amountSat,
    this.fiatAmountMinor,
    this.fiatCurrency,
    this.publicDescription,
    this.recipientName,
    this.invoiceNumber,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    this.bitcoinAddress,
    this.liquidAddress,
    this.liquidBlindingKeyHex,
    this.expiresAtUnix,
  });
}

/// The signed-create response (`CreateSignedResponse`): only the id and the
/// public share URL. Pricing/status live on the separate status shape.
class BullnymCreateInvoiceResponse {
  final String invoiceId;
  final String shareUrl;

  const BullnymCreateInvoiceResponse({
    required this.invoiceId,
    required this.shareUrl,
  });
}

/// The signed-cancel response (`CancelResponse`): the id and the final status
/// the server settled on (`cancelled`, or the pre-existing terminal status).
class BullnymCancelInvoiceResponse {
  final String invoiceId;
  final String status;

  const BullnymCancelInvoiceResponse({
    required this.invoiceId,
    required this.status,
  });
}

/// One row of the npub-keyed list (`InvoiceListItem`). `nymOwner` is null for
/// unlinked invoices; the `paid*` fields are populated only once paid.
class BullnymInvoiceListItem {
  final String id;
  final String? nymOwner;
  final String origin;
  final String status;
  final String pricingMode;
  final String settlementStatus;
  final int amountSat;
  final int remainingAmountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? recipientName;
  final String? invoiceNumber;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final String? bitcoinAddress;
  final String? liquidAddress;
  final int createdAtUnix;
  final int expiresAtUnix;
  final String? paidVia;
  final int? paidAtUnix;
  final int? paidAmountSat;

  const BullnymInvoiceListItem({
    required this.id,
    this.nymOwner,
    required this.origin,
    required this.status,
    required this.pricingMode,
    required this.settlementStatus,
    required this.amountSat,
    required this.remainingAmountSat,
    this.fiatAmountMinor,
    this.fiatCurrency,
    this.publicDescription,
    this.recipientName,
    this.invoiceNumber,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    this.bitcoinAddress,
    this.liquidAddress,
    required this.createdAtUnix,
    required this.expiresAtUnix,
    this.paidVia,
    this.paidAtUnix,
    this.paidAmountSat,
  });
}

/// The npub-keyed list response (`ListInvoicesResponse`). `pageSize` keeps the
/// server's camelCase wire key.
class BullnymListInvoicesResponse {
  final List<BullnymInvoiceListItem> invoices;
  final int page;
  final int pageSize;
  final bool hasMore;

  const BullnymListInvoicesResponse({
    required this.invoices,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });
}

/// The public status shape (`InvoiceStatusResponse`, unsigned GET by id). Kept
/// deliberately separate from the list/create shapes (server design): callers
/// merge explicitly, they never conflate the two.
class BullnymInvoiceStatus {
  final String status;
  final String pricingMode;
  final String settlementStatus;
  final int amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final int remainingAmountSat;
  final int paymentToleranceSat;
  final int? rateMinorPerBtc;
  final int rateLocksUntilUnix;
  final int expiresAtUnix;
  final String? paidVia;
  final int? paidAtUnix;
  final int? paidAmountSat;
  final String? lightningPr;
  final String? liquidAddress;
  final String? bitcoinAddress;
  final String? bitcoinChainAddress;
  final String? bitcoinChainBip21;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;

  const BullnymInvoiceStatus({
    required this.status,
    required this.pricingMode,
    required this.settlementStatus,
    required this.amountSat,
    this.fiatAmountMinor,
    this.fiatCurrency,
    required this.remainingAmountSat,
    required this.paymentToleranceSat,
    this.rateMinorPerBtc,
    required this.rateLocksUntilUnix,
    required this.expiresAtUnix,
    this.paidVia,
    this.paidAtUnix,
    this.paidAmountSat,
    this.lightningPr,
    this.liquidAddress,
    this.bitcoinAddress,
    this.bitcoinChainAddress,
    this.bitcoinChainBip21,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
  });
}

/// The `invoice-recover` response (`RecoverResponse`): `status` is always
/// "recovered" on success and `txid` is the broadcast recovery transaction id.
/// A retried request after success is idempotent and returns the same txid.
class BullnymRecoverChainSwapResponse {
  final String status;
  final String txid;

  const BullnymRecoverChainSwapResponse({
    required this.status,
    required this.txid,
  });
}

/// One recoverable chain swap (server `RecoverableItem`). ONE PER SWAP — an
/// invoice with two stuck swaps yields two of these, distinguished by
/// [lockupAddress]. [recoveryStatus] is the chain-swap lifecycle string
/// (`refund_due` | `refunding` | `refunded`). [refundAddress]/[refundTxid] are
/// the committed first-write-wins destination and broadcast txid — the
/// post-reinstall reconciliation echo (null until committed/refunded).
class BullnymRecoverableSwap {
  final String invoiceId;
  final String nym; // build the per-nym recover URL from THIS value
  final String recoveryStatus;
  final int userLockAmountSat;
  final int serverLockAmountSat; // effective (renegotiation-aware)
  final String lockupAddress; // swap identity within an invoice
  final String? refundAddress;
  final String? refundTxid;
  final int swapCreatedAtUnix;
  final int swapUpdatedAtUnix;
  // Flattened invoice context (server nested `invoice` object):
  final String invoiceStatus;
  final int invoiceAmountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final String? publicDescription;
  final String? invoiceNumber;
  final int invoiceCreatedAtUnix;

  const BullnymRecoverableSwap({
    required this.invoiceId,
    required this.nym,
    required this.recoveryStatus,
    required this.userLockAmountSat,
    required this.serverLockAmountSat,
    required this.lockupAddress,
    this.refundAddress,
    this.refundTxid,
    required this.swapCreatedAtUnix,
    required this.swapUpdatedAtUnix,
    required this.invoiceStatus,
    required this.invoiceAmountSat,
    this.fiatAmountMinor,
    this.fiatCurrency,
    this.publicDescription,
    this.invoiceNumber,
    required this.invoiceCreatedAtUnix,
  });
}

/// The `invoice-recovery-list` response (`RecoverableListResponse`).
/// [recoveryEnabled] is the server's `chain_swap_merchant_recovery` flag —
/// detection is always-on behind auth, but the flag drives whether the recover
/// action is offered. [hasMore] true means the server cap (100) was hit and the
/// client should route to "contact support" rather than paginate.
class BullnymRecoverableSwapList {
  final bool recoveryEnabled;
  final List<BullnymRecoverableSwap> items;
  final int count;
  final bool hasMore;

  const BullnymRecoverableSwapList({
    required this.recoveryEnabled,
    required this.items,
    required this.count,
    required this.hasMore,
  });
}
