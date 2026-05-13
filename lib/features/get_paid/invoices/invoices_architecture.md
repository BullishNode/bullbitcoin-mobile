# Invoices Architecture

## Overview

Invoices are the third Get Paid sub-feature. Mobile creates, lists, cancels,
and inspects wallet-origin Bullpay invoices owned by the user's Get Paid Nostr
identity. The backend owns public rendering, payment detection, rate refresh,
Lightning offer creation, and invoice state transitions.

This feature stays under `features/get_paid/invoices/`. It does not expose a
cross-feature facade in v1. The Get Paid dashboard navigates to invoices as an
internal sub-feature route.

## Backend Contract

Invoices use `features/get_paid/shared/bullnym/BullnymClient`.

Current bullnym endpoints verified in `/home/francis/bull-bitcoin-workspace/bullnym/src/invoice.rs`:

- `POST /api/v1/:nym/invoices` creates a linked invoice.
- `POST /api/v1/invoices` creates an unlinked invoice.
- `DELETE /api/v1/:nym/invoices/:id` cancels a linked invoice.
- `DELETE /api/v1/invoices/:id` cancels an unlinked invoice.
- `GET /api/v1/invoices?npub=...&timestamp=...&signature=...&since_unix=...&limit=...&status=...`
  lists invoices for the signing npub.
- `GET /api/v1/invoices/:id/status` returns public invoice status/detail data.

Signed actions use the deployed `bullpay-la-v2` wire domain through
`signBullpayAction`:

- `invoice-create` signs fields in this exact order:
  `amount_sat`, `fiat_amount_minor`, `fiat_currency`, `public_description`,
  `recipient_name`, `invoice_number`, `accept_btc`, `accept_ln`,
  `accept_liquid`, `bitcoin_address`, `liquid_address`, `expires_at_unix`.
- `invoice-cancel` signs `invoice_id`.
- `invoice-list` signs `since_unix_or_zero`, `limit`, `status_or_empty`.

For linked create/cancel, `nymOrEmpty` is the path nym. For unlinked
create/cancel and all list requests, `nymOrEmpty` is the empty string.

Backend constraints mobile must mirror:

- At least one rail must be enabled.
- `accept_btc=true` requires a wallet-supplied Bitcoin address.
- `accept_ln=true` or `accept_liquid=true` requires a wallet-supplied Liquid
  address.
- `expires_at_unix` must be at least 60 seconds in the future and at most 7
  days in the future.
- Fiat minor-unit precision must mirror the backend pricer (`COP` is 0-decimal;
  currently supported invoice fiat currencies otherwise use 2 decimals).
- `limit` must be at least 1; backend caps it at 100.
- Status filter is absent/empty or one of: `unpaid`, `in_progress`, `paid`,
  `underpaid`, `overpaid`, `expired`, `cancelled`.

## Domain

### Entities

`Invoice`

- `id: InvoiceId`
- `nymOwner: String?`
- `origin: String`
- `status: InvoiceStatus`
- `amountSat: int`
- `fiatAmountMinor: int?`
- `fiatCurrency: String?`
- `publicDescription: String?`
- `recipientName: String?`
- `invoiceNumber: String?`
- `acceptBtc: bool`
- `acceptLn: bool`
- `acceptLiquid: bool`
- `bitcoinAddress: String?`
- `liquidAddress: String?`
- `createdAt: DateTime`
- `expiresAt: DateTime`
- `paidVia: PaymentMethod?`
- `paidAt: DateTime?`
- `paidAmountSat: int?`
- `shareUrl: InvoiceUrl?`

`InvoiceStatusSnapshot`

- `invoiceId: InvoiceId`
- `status: InvoiceStatus`
- `amountSat: int`
- `rateMinorPerBtc: int?`
- `rateLocksUntil: DateTime`
- `expiresAt: DateTime`
- `paidVia: PaymentMethod?`
- `paidAt: DateTime?`
- `paidAmountSat: int?`
- `lightningPr: String?`
- `liquidAddress: String?`
- `bitcoinAddress: String?`
- `acceptBtc: bool`
- `acceptLn: bool`
- `acceptLiquid: bool`
- `rateStale: bool`

The list/create entity and public status snapshot are deliberately separate.
The backend cancel response and status endpoint do not return the full
`InvoiceListItem` shape, so callers keep status updates separate from list
items unless they explicitly merge them with local state.

`CreateInvoiceResult`

- `invoiceId: InvoiceId`
- `shareUrl: InvoiceUrl`

The backend create response returns only `invoice_id` and `share_url`, not a
full invoice row.

Derived behavior belongs on the entity:

- `isPayable` is true for `unpaid` and `inProgress` before expiry.
- `isCancellable` is true only for `unpaid`, matching the backend cancel
  update predicate.
- `timeUntilExpiry(DateTime now)` returns zero when expired.
- `publicUrlFor({required String domain})` returns
  `https://<domain>/<nym>/i/<id>` when linked and
  `https://<domain>/invoice/<id>` when unlinked.

### Value Objects And Primitives

- `InvoiceId`: validated non-empty UUID string.
- `InvoiceUrl`: validated HTTPS URL string returned by backend or derived from
  `Invoice.publicUrlFor`.
- `InvoiceStatus`: `unpaid`, `inProgress`, `paid`, `underpaid`, `overpaid`,
  `expired`, `cancelled`.
- `PaymentMethod`: `btc`, `lightning`, `liquid`.

Domain stores `DateTime`; Unix seconds are converted only at the Bullnym
datasource boundary.

## Application

### Ports

`InvoicesPayServicePort`

- `Future<CreateInvoiceResult> createInvoice({required NostrKeychainHandle handle, required CreateInvoiceCommand command, required String? bitcoinAddress, required String? liquidAddress})`
- `Future<CancelInvoiceResult> cancelInvoice({required NostrKeychainHandle handle, required CancelInvoiceCommand command})`
- `Future<List<Invoice>> listInvoices({required NostrKeychainHandle handle, required ListInvoicesCommand command})`
- `Future<InvoiceStatusSnapshot> getInvoiceStatus({required InvoiceId id})`

The port returns domain entities and maps Bullnym/client errors into
`InvoicesApplicationError`. It does not expose Bullnym DTOs to use cases or
presentation.

### Commands

- `CreateInvoiceCommand`
  - amount is either `amountSat` or `fiatAmountMinor` + `fiatCurrency`.
  - public metadata: `publicDescription`, `recipientName`, `invoiceNumber`.
  - rails: `acceptBtc`, `acceptLn`, `acceptLiquid`.
  - `expiresAt: DateTime`.
  - `linkToPageNym: String?`.
  - `privateMemo: String?` is mobile-only and never sent to Bullnym.
- `CancelInvoiceCommand`: `invoiceId`, `nymOwner`.
- `ListInvoicesCommand`: `since`, `limit`, `status`.

### Identity

Invoices reuse the single Bullnym/Get Paid Nostr identity also used by
Lightning Address and Payment Page. The derivation policy is owned by
`features/get_paid/shared/get_paid_identity_derivation.dart`, not `core/nostr`
and not an invoice-local copy.

`InvoicesIdentityDatasource` adapts that shared helper to
`InvoicesIdentityPort`. If the helper returns null because no default Bitcoin
wallet exists, the datasource throws `InvoicesIdentityUnavailableError`.
Lightning Address still has a local compatibility path while its remaining
`NostrIdentity` call sites are retired.

### Use Cases

- `CreateInvoiceUsecase`
  - Validates command invariants that mobile can know before the server.
  - Generates a fresh Bitcoin receive address when `acceptBtc` is true using
    `WalletRepository.getWallets(onlyDefaults: true, onlyBitcoin: true)` and
    `WalletAddressRepository.generateNewReceiveAddress`.
  - Generates one fresh Liquid receive address when either `acceptLn` or
    `acceptLiquid` is true using
    `WalletRepository.getWallets(onlyDefaults: true, onlyLiquid: true)`.
  - Throws typed invoice errors when required default wallets are missing.
  - Gets the Get Paid Nostr signing handle through an identity port/datasource;
    presentation never derives or carries secrets.
  - Calls `InvoicesPayServicePort.createInvoice`.
  - Stores `privateMemo` as local address labels through `LabelsFacade.store`
    using `NewLabel.addr(...)` and origin `invoice:<invoiceId>`. Label storage
    is best-effort after server success and cannot turn a created invoice into
    a failed create result.

- `CancelInvoiceUsecase`
  - Gets the signing handle and delegates cancel to the port.
  - Returns the cancelled invoice id and final status from the backend.
  - Does not delete local labels; labels remain wallet history metadata.

- `ListInvoicesUsecase`
  - Gets the signing handle and delegates list to the port.
  - Uses the backend `since_unix`, `limit`, `status` contract.

- `GetInvoiceUsecase`
  - Reads public status/detail data by invoice id and returns
    `InvoiceStatusSnapshot`.
  - Does not require a signing handle.

## Data

`InvoicesPayServiceDatasource` wraps `BullnymClient`.

Required Bullnym client additions:

- `createInvoice`
- `cancelInvoice`
- `listInvoices`
- `getInvoiceStatus`

DTOs live in `features/get_paid/shared/bullnym/models/`. They mirror the
backend wire contract exactly:

- `BullnymCreateInvoiceResponseDto`: `invoice_id`, `share_url`.
- `BullnymCancelInvoiceResponseDto`: `invoice_id`, `status`.
- `BullnymInvoiceListItemDto`: list item fields from `InvoiceListItem`.
- `BullnymListInvoicesResponseDto`: `invoices`.
- `BullnymInvoiceStatusDto`: status endpoint fields.

DTOs do not contain `NostrKeychainHandle`. The handle is passed as a separate
method argument to the client for signed actions.

## Presentation

Presentation stays thin:

- `InvoicesListCubit`: load list, client-side status chips over loaded
  invoices, refresh, and pagination only after the backend contract can support
  older-page continuation.
- `InvoiceCreateCubit`: local form state and submit through
  `CreateInvoiceUsecase`.
- `InvoiceDetailCubit`: public status lookup, cancel action.

Cubits catch typed invoice errors explicitly and map unknown errors to a generic
friendly UI message after logging.

- `InvoicesListCubit.load/refresh` calls `ListInvoicesUsecase` with no status
  filter and applies `statusFilter` locally in `InvoicesListState`.
- `InvoiceCreateCubit.submit` builds `CreateInvoiceCommand` from form state;
  wallet lookup, address generation, signing, and label storage remain in
  `CreateInvoiceUsecase`.
- `InvoiceDetailCubit.load/refresh` uses the public status endpoint through
  `GetInvoiceUsecase`; `cancel` delegates to `CancelInvoiceUsecase` and stores
  the returned final status separately from the public status snapshot.

## UI

Routes live under `features/get_paid/invoices/ui/` and are registered as child
routes under `GetPaidRouter.route`.

Screens:

- Invoice list with status chips and dedicated `InvoiceListItem` widget.
- Create flow:
  - amount step, reusing the existing amount input pattern available in the app;
  - details step with public description, invoice number, recipient name,
    expiry exposed as a 1-to-7 day picker, rail toggles,
    link-to-payment-page toggle, and private memo.
- Detail screen mirrors the transaction detail pattern: all relevant blocks are
  visible, cancel uses a confirmation dialog, URL copy is silent, and status
  refresh is explicit or lifecycle-driven.

The dashboard's Invoices slot navigates internally to the invoices list route
once the user has a Lightning Address. The slot awaits `pushNamed<bool>` and
refreshes the Get Paid dashboard only when the invoices flow pops `true`,
matching the mutation-result contract used by the Payment Page slot. Invoices
are not exposed through a Get Paid public facade in v1.

### Implementation Notes

The create flow is implemented as a single route with amount/details steps
inside the same widget, instead of two separate routes. This preserves the form
state and keeps the browser/system back behavior local: back from details
returns to the amount step, while back from the success view pops `true` to the
caller. If create substeps need deep links later, the route split can be done
then.

The expiry selector is a 1-to-7 day picker because the backend wallet-origin
expiry cap is 7 days.

`CountdownFormat.mmss` remains the default because existing callers already
present `MM:SS`. Invoice detail uses `CountdownFormat.dhm`, which drops seconds
and renders minutes as `min`.

## Pagination And Filtering

Backend list is `since_unix` + `limit` + optional `status`, sorted by
`created_at DESC`.

Mobile v1 uses:

- `limit <= 100`;
- first page with no `since`;
- no infinite scroll until backend exposes a cursor/keyset contract or changes
  `since_unix` semantics.

Current backend `since_unix` means "created at or after" while results are
sorted newest-first. That is useful for refresh/newer-sync, not older-page
continuation. Mobile v1 fetches a single bounded window; infinite scroll needs
a backend cursor/keyset contract.

Status chips are client-side filters over the currently loaded set unless the
user explicitly refreshes with a backend status filter.

## Countdown

`lib/core/widgets/timers/countdown.dart` supports the invoice detail screen
without changing existing buy/sell callers:

- `enum CountdownFormat { mmss, dhm }`
- default remains `mmss` so existing buy/sell callers are unchanged.
- `dhm` renders `Xd Yh Zmin`, `Xh Ymin`, or `Xmin` depending on remaining
  time.
- tick frequency remains one second in this slice. The originally planned
  battery-saver minute tick is deferred until it is needed by a broader timer
  optimization pass.

## Multi-Rail Address Caveat

When both Lightning and Liquid are enabled, mobile supplies one Liquid receive
address. The backend uses it both as the Liquid payment destination and as the
claim destination for Lightning swaps. This is intentional for v1.

If a user reuses or observes the shared Liquid address while a Lightning swap
for the same invoice is pending, the UI does not surface that distinction in
v1.

## Error Handling

`InvoicesApplicationError` maps backend and local orchestration failures:

- no default Bitcoin wallet;
- no default Liquid wallet;
- validation error;
- invoice not found;
- auth/ownership error;
- rate limited;
- network error;
- unexpected server error.

Raw `Exception.toString()` must not be emitted to UI state.

## Files

- `lib/features/get_paid/invoices/domain/entities/invoice.dart`
- `lib/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart`
- `lib/features/get_paid/invoices/domain/primitives/invoice_status.dart`
- `lib/features/get_paid/invoices/domain/primitives/payment_method.dart`
- `lib/features/get_paid/invoices/domain/value_objects/invoice_id.dart`
- `lib/features/get_paid/invoices/domain/value_objects/invoice_url.dart`
- `lib/features/get_paid/invoices/application/cancel_invoice_result.dart`
- `lib/features/get_paid/invoices/application/create_invoice_result.dart`
- `lib/features/get_paid/invoices/application/invoices_application_error.dart`
- `lib/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart`
- `lib/features/get_paid/invoices/application/ports/invoices_identity_port.dart`
- `lib/features/get_paid/invoices/application/usecases/*`
- `lib/features/get_paid/invoices/data/datasources/invoices_pay_service_datasource.dart`
- `lib/features/get_paid/invoices/data/datasources/invoices_identity_datasource.dart`

Presentation, UI routes, locator wiring, and countdown support live in the
same feature tree.

## Verification

Run for relevant invoice changes:

- `flutter analyze`
- targeted unit/widget tests for the files changed
- `git diff --check`

Coverage targets:

- entity getter tests for `isPayable`, `isCancellable`, `timeUntilExpiry`, and
  `publicUrlFor`;
- Bullnym DTO/client tests for exact invoice field order and parse shape;
- use case tests with mocked wallets, addresses, identity, labels, and service;
- cubit tests for loading, filters, submit, cancel, and generic error mapping;
- widget tests for list, create flow, detail cancel confirmation, and dashboard
  route wiring.

## Known Limitations

- Backend wallet-origin expiry cap is 7 days today.
- List continuation semantics are not sufficient for older-page infinite scroll
  unless backend pagination changes or confirms cursor/keyset behavior.
- Image upload and QR/save/share polish are separate product work.
- Invoice labels are local wallet metadata only; Bullnym never receives
  `privateMemo`.
