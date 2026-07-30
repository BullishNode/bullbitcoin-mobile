# Get Paid

Get Paid owns the wallet's receiving-product hub and its authenticated history of payments received through Bullnym-backed Get Paid products.

## Scope

This feature owns:

- the dashboard that links to Lightning Address, Donation Page, Point of Sale, one-time invoice creation, BTCPay, and received Get Paid transactions;
- independent dashboard-card loading so a slow remote lookup does not hide the rest of the product surface;
- the Get Paid transaction entity, typed failure mapping, pagination state, and list/detail presentation;
- derivation of an ephemeral Bullnym server-auth signer at the point of the private history request.

It does not own Bullnym HTTP/signing rules, invoice settlement logic, payment page or POS configuration, Lightning Address registration, wallet transaction history, or wallet key storage. Those remain behind their owning feature/core boundaries.

## Transaction History

`Transactions` is a private, identity-wide payment-evidence projection from Bullnym. It contains evidenced Get Paid receipts from Lightning Address, one-time invoices, Donation Pages, and Point of Sale. It is not an invoice list and excludes unpaid or abandoned payment artifacts by server contract.

The client treats the server cursor as opaque. First load, pull-to-refresh, and explicit load-more calls use the signed `get-paid-transaction-list` action. Pages are deduplicated by `(source, transaction_id)`; neither identifier is shown as user copy. Unknown source, rail, settlement state, malformed identity, invalid source/invoice relationships, duplicate rows, or invalid cursor progression fail closed at the Bullnym data boundary.

Rows show amount, source, receipt time, rail, and settlement state. Optional payer comments appear only on the transaction detail screen. Invoice-backed details merge their invoice and authenticated accounting facts into that same screen; Lightning Address receipts never carry an invoice id.

## Privacy And Identity

The history endpoint is authenticated with the existing Bullnym server-auth Nostr role derived from the current default Bitcoin wallet xprv. The xprv and signer are created only for the request and are not stored in Get Paid state. Bullnym receives the derived public key, timestamp, signature, cursor, and limit; it does not receive the wallet seed or xprv.

Comments and internal identifiers are not logged or rendered in list rows. Ordinary browsing keeps the private no-store response only in the history cubit. An explicit merchant CSV export performs its own authenticated history walk and passes the resulting file to the operating-system save/share sheet; that export includes invoice and provider-order identifiers but deliberately omits comment text.

## Dependencies

The presentation flow is:

`UI -> GetPaidTransactionHistoryCubit -> ListGetPaidTransactionsUsecase -> BullnymFacade`

An open receipt uses the same authenticated collection through a Get Paid-owned
detail path:

`UI -> GetPaidTransactionDetailCubit -> LookUpGetPaidTransactionUsecase -> ListGetPaidTransactionsUsecase`

The lookup walks opaque cursor pages until it finds the receipt's stable
`(source, transaction_id)` identity. Pull-to-refresh therefore reloads the
settlement projection for every source, including Lightning Address receipts
that have no invoice id. A failed refresh retains the last verified receipt and
marks it stale instead of blanking the merchant's evidence.

The use case also consumes `NostrIdentityFacade` and a Get Paid-owned default wallet xprv capability implemented against core wallet/seed infrastructure. Cross-feature calls use public facades, and `FEATURES.md` records those edges.

No Get Paid presentation class calls another feature's facade — not a cubit, and not a screen reaching through the locator. Every foreign boundary the hub reads is wrapped in a Get Paid-owned use case, so presentation depends on Get Paid use cases plus core wallet reads, and the hub's product rules live in `domain/`:

| Use case | Foreign boundary | Hub-owned rule it holds |
| --- | --- | --- |
| `LookUpGetPaidLightningRegistrationUsecase` | `LightningAddressFacade` | normalises `NymNotFound` and an empty nym into one confirmed-empty registration |
| `FindGetPaidPaymentPageUsecase` | `PaymentPageFacade` | classifies the nym-keyed probe and maps it to URL + archived state |
| `FindGetPaidPosTerminalUsecase` | `PosFacade` | classifies the nym-keyed probe and maps it to URL + archived state |
| `GetGetPaidBtcpayConnectionUsecase` | `BtcpayFacade` | keeps the BTCPay failure family out of hub state and maps a connection to its server URL |
| `GetGetPaidFiatSettlementSummaryUsecase` | `FiatSettlementFacade` | mainnet-only gate + Get Paid-owned percentage/currency projection for the three dashboard products |
| `EnsureGetPaidProductWalletUsecase` | the three product facades | contract #4 Q9/Q9b self-heal |
| `EnsureGetPaidAutomaticFallbackUsecase` | `AutomaticFallbackFacade` | idempotent setup, failure never hides the hub |
| `GetPaidFallbackAttentionUsecase` | `InvoicesFacade` | attention count only |
| `LoadGetPaidInvoicesOverviewUsecase` | core wallets + the attention wrapper | preserves known readiness, known empty, and unavailable as distinct card outcomes |
| `LoadGetPaidProductOverviewUsecase` | the Lightning Address/Page/POS/fallback/wallet wrappers | coordinates nym-keyed probes and active-product self-healing while streaming independent card results |
| `LookUpGetPaidInvoiceFactsUsecase` | `InvoicesFacade` | requires the public detail read, best-effort reads authenticated accounting, and maps both into a Get Paid-owned snapshot |

Every product read reports one of three outcomes — found, confirmed absent, or unavailable (`GetPaidProductProbe`). Collapsing "unavailable" into "absent" is what would make the hub claim a product is unconfigured when its truth is simply unknown, so the distinction is owned by `domain/`, not by the cubit. The cubit keeps only what presentation owns: independent per-card loading, the refresh generation guard, and the retry banner.

Foreign product entities stop at those use cases. Dashboard state contains only Get Paid-owned snapshots: hosted-product URL and archived state, the BTCPay server URL, and settlement percentage/currency. It therefore cannot accidentally grow a dependency on another feature's product model merely because that provider model later gains fields.

The coupled product workflow also stops in domain. The product-overview use case decides that Page/POS require a confirmed nym, fallback setup follows identity, and only active products trigger fixed-wallet self-healing. It streams owned events so independently resolving cards stay independent; the Cubit applies generation guards and presentation state only. Invoice readiness similarly keeps failed wallet or supervision reads distinct from a confirmed missing wallet or zero attention count.

Every hub dependency is required and explicit. Nothing is nullable "when not wired", nothing is guarded with `locator.isRegistered`, and no adapter silently does nothing: whether fiat settlement applies is decided inside `GetGetPaidFiatSettlementSummaryUsecase` (non-mainnet reports "does not apply"), not by handing presentation a dependency that may be absent.

## Transaction Detail

`GetPaidTransactionDetailCubit` owns the receipt projection and
`GetPaidInvoiceFactsCubit` owns the optional invoice-state read. The route
provides both and starts the invoice read; the screen renders whichever states
they hold and resolves nothing itself. Pull-to-refresh reloads both reads when
an invoice exists and reloads only the receipt for Lightning Address history.
After a successful first read, either cubit retains its last verified data when
a refresh fails and exposes a stale indication.

The use case maps the required Invoices public response and the best-effort authenticated merchant payment summary into `GetPaidInvoiceFacts`, including Get Paid-owned rail, payment-event, lifecycle, and aggregate payment values. Provider entities and their failure family therefore never enter Get Paid presentation or UI. A public-read failure remains a retryable detail failure. An authenticated-accounting failure is stated as unavailable while the public detail remains visible. An invoice-backed history row is already authenticated positive payment evidence by contract, so this receipt-only surface models no admission state, payer instructions, quote controls, or cancellation actions. The ordinary Invoices flow remains the owner of an unpaid invoice's payment UI.

Initial and failure are deliberately distinct. Initial means no read applies (a Lightning Address receipt carries no invoice id) and the card renders as it does for an entry with no invoice. Failure means a read was attempted and did not land, and the invoice section says so — mirroring how an uninterpretable settlement states itself. Collapsing the two is what would let an unreadable invoice render as an invoice-less payment.
