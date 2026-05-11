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
  days in the future. The old plan text mentioning 30 days is stale unless the
  backend cap changes explicitly.
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
`InvoiceListItem` shape, so mobile must not pretend a full entity exists after
those calls unless it composes one from existing local state.

`CreateInvoiceResult`

- `invoiceId: InvoiceId`
- `shareUrl: InvoiceUrl`

The backend create response returns only `invoice_id` and `share_url`, not a
full invoice row.

Derived behavior belongs on the entity:

- `isPayable` is true for `unpaid` and `inProgress` before expiry.
- `isCancellable` is true for `unpaid` and `inProgress`.
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
    using `NewLabel.addr(...)` and origin `invoice:<invoiceId>`.

- `CancelInvoiceUsecase`
  - Gets the signing handle and delegates cancel to the port.
  - Returns the cancelled invoice id and final status from the backend.
  - Does not delete local labels; labels remain wallet history metadata.

- `ListInvoicesUsecase`
  - Gets the signing handle and delegates list to the port.
  - Uses the backend `since_unix`, `limit`, `status` contract. Do not invent
    offset `page/pageSize`.

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

Presentation is Phase 3.3 and stays thin:

- `InvoicesListCubit`: load list, client-side status chips over loaded
  invoices, refresh, and pagination only after the backend contract can support
  older-page continuation.
- `InvoiceCreateCubit`: local form state and submit through
  `CreateInvoiceUsecase`.
- `InvoiceDetailCubit`: public status lookup, cancel action.

Cubits catch typed invoice errors explicitly and map unknown errors to a generic
friendly UI message after logging.

## UI

Routes live under `features/get_paid/invoices/ui/` and are registered as child
routes under `GetPaidRouter.route`.

Screens:

- Invoice list with status chips and dedicated `InvoiceListItem` widget.
- Create flow:
  - amount step, reusing the existing amount input pattern available in the app;
  - details step with public description, invoice number, recipient name,
    expiry constrained to the backend's 1-minute to 7-day window, rail toggles,
    link-to-payment-page toggle, and private memo.
- Detail screen mirrors the transaction detail pattern: all relevant blocks are
  visible, cancel uses a confirmation dialog, URL copy is silent, and status
  refresh is explicit or lifecycle-driven.

The dashboard's Invoices slot remains disabled until the list route exists,
then navigates internally to the invoices list route. Invoices are not exposed
through a Get Paid public facade in v1.

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
continuation. Mobile v1 should fetch a single bounded window or require a
backend cursor/keyset contract before implementing infinite scroll. Do not
silently switch to offset pagination.

Status chips are client-side filters over the currently loaded set unless the
user explicitly refreshes with a backend status filter.

## Countdown

Phase 3.5 extends `lib/core/widgets/timers/countdown.dart`:

- `enum CountdownFormat { hms, dhm }`
- default remains `hms` so existing buy/sell callers are unchanged.
- `dhm` renders `Xd Yh Zmin` for multi-day invoice expiry.
- tick frequency is 1 minute when remaining time is greater than 1 hour, and 1
  second otherwise.

## Multi-Rail Address Caveat

When both Lightning and Liquid are enabled, mobile supplies one Liquid receive
address. The backend uses it both as the Liquid payment destination and as the
claim destination for Lightning swaps. This is intentional for v1.

There is still a race to document in code review: a user could reuse/observe the
same Liquid address while a Lightning swap for the same invoice is pending. This
is not user-surfaced in v1 per the plan; it is a known limitation.

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

Phase 3.1:

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

Phase 3.3-3.5 add presentation, UI routes, locator wiring, and countdown
extension in their own commits.

## Verification

Required before each phase commit:

- `flutter analyze`
- targeted unit/widget tests for the files changed
- `git diff --check`

Phase-specific gates:

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
- Image upload and QR/save/share polish remain Phase 2E-style optional slices.
- Invoice labels are local wallet metadata only; Bullnym never receives
  `privateMemo`.
