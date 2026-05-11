# Payment Page Architecture

## Overview

Payment Page is the mobile editor for Bullpay donation pages. The backend owns
rendering and payment collection; mobile owns authenticated create, edit,
archive, and status reads for a single page tied to a registered nym.

This slice is application/data only. It intentionally does not add UI, routing,
image upload, QR/save behavior, or bottom navigation.

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

## Deferred

- UI/cubit/forms are Phase 2C.
- Dashboard route and slot cards are Phase 2D.
- Image upload, QR/save-to-gallery, and bottom-nav tab are optional Phase 2E
  slices after explicit approval.
- Payment Page creation without an existing Lightning Address remains a product
  decision for Phase 2C. Default is to route the user to create LA first.
