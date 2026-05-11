# Get Paid Architecture

Get Paid is a product surface that coordinates payment receiving features while
keeping their implementation boundaries intact.

## Scope

Phase 2D adds an internal dashboard route. It reads Lightning Address state
through `LightningAddressFacade` and Payment Page state through the Payment Page
application use cases. It does not move Lightning Address, change the app shell,
add a bottom navigation tab, add image upload, or implement invoices.

## Dependencies

- `features/lightning_address/public/lightning_address_facade.dart` is the only
  Lightning Address dependency.
- `features/get_paid/payment_page/application/` is consumed through use cases.
- `features/get_paid/payment_page/ui/` owns Payment Page editing.
- `features/get_paid/shared/bullnym/` remains the protocol boundary.

## Dashboard Flow

1. `GetPaidDashboardCubit.refresh()` reads the current Lightning Address from
   `LightningAddressFacade`.
2. If no Lightning Address exists, the dashboard shows the Lightning Address
   setup action and does not query Payment Page.
3. If a Lightning Address exists, the cubit derives the nym and loads the
   active Payment Page with `FindPaymentPageUsecase`.
4. Sub-feature screens return `true` after a mutation. The dashboard refreshes
   only when that value is returned, or on pull-to-refresh/app-resume.

## Boundaries

Payment Page archive only archives the page. Lightning Address deactivation
stays in Lightning Address settings. The dashboard may navigate to those
screens, but it does not compose their write operations.

## Deferred

Bottom navigation, image upload, QR/save, dashboard polish, and invoices remain
outside this phase.
