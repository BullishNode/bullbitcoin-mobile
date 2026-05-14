# Payment Page Architecture

## Overview

Payment Page is the mobile editor for Bullpay donation pages. The backend owns
rendering and payment collection; mobile owns authenticated create, edit,
archive, and status reads for a single page tied to a registered nym.
The editor is an internal Get Paid route, not a bottom navigation destination.

## Backend Contract

The feature uses the existing Bullnym endpoints through
`features/get_paid/shared/bullnym/BullnymClient`:

- `GET /donation-page/:nym` returns `DonationPageView`.
- `PUT /donation-page` saves or reactivates a page.
- `DELETE /donation-page` archives a page.

Signed write actions use the deployed `bullpay-la-v2` wire domain:

- `donation-page-save` signs payload fields in this exact order:
  `header`, `description`, `display_currency`, `website`, `twitter`,
  `instagram`, `enabled`.
- `donation-page-archive` signs no payload fields.

The Nostr key handle is passed separately to use cases and ports. It is never
stored inside commands, DTOs, generated state, equality, `copyWith`, or JSON.

## Layers

### Domain

- `PaymentPage` is the domain entity for the editor/dashboard state.
- `PaymentPage.isActive` is derived from `enabled && !isArchived`.

### Application

- `PaymentPageServicePort` is the boundary consumed by use cases.
- `PaymentPageIdentityPort` provides the signing handle to write use cases so
  presentation code never fetches or derives Nostr keys.
- `SavePaymentPageCommand` contains serializable page fields only.
- `ArchivePaymentPageCommand` contains the target nym only.
- `GetPaymentPageUsecase`, `SavePaymentPageUsecase`, and
  `ArchivePaymentPageUsecase` are thin application entry points.
- `FindPaymentPageUsecase` maps not-found into `null` for dashboard/status
  flows where "no page yet" is expected.
- `PaymentPageApplicationError` maps Bullnym transport/backend errors into
  feature errors without importing Bullnym types into the application layer.

### Data

- `PaymentPageDatasource` implements `PaymentPageServicePort`.
- It wraps `BullnymClient` and maps `BullnymDonationPageDto` to `PaymentPage`.
- It catches `BullnymException` and throws `PaymentPageApplicationError`.

### Presentation And UI

- `PaymentPageCubit` loads an existing page, saves edits, and archives the
  page through application use cases.
- The editor route is owned by `payment_page/ui/payment_page_router.dart`.
- Save/archive success pops `true` so the Get Paid dashboard can refresh.
- User-facing errors come from `payment_page_error_message.dart`; raw backend
  reasons and generic exception strings are not emitted to UI state.
- Header, description, website, and social handle limits mirror the backend
  validators. Byte-counted fields use `Utf8ByteLimitFormatter`.

## Deferred

- Image upload, QR/save-to-gallery, and a bottom-nav entry are separate product
  work.
- Payment Page creation requires a Bullnym name; it does not require an active
  Lightning Address.
