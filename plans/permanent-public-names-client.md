# Permanent Public Names: Mobile Client Implementation Plan

Status: locked product semantics; implementation pending

Date locked: 2026-07-11

Mobile baseline: BullishNode/bullbitcoin-mobile branch pr30-getpaid-sweep-labels, commit 9b1b255feede3ce6297525441e59ec1ebd24e7c3.

Required server baseline: BullishNode/bullnym PR #92 after it is revised to implement the coordinated server plan:

- ../../bullnym/plans/permanent-public-names-server.md

This plan replaces all proposed mobile flows for inactive names, alias clearing, alias reactivation, nym reactivation, or choosing a replacement name. Names are permanent. Lightning Address, Payment Page, and Point of Sale are the things users turn online or offline.

## Objective

Add client support for one permanent nym and one optional permanent alias per npub, while presenting three independent product availability controls:

- Lightning Address online/offline;
- Payment Page online/offline;
- Point of Sale online/offline.

The client must never imply that turning a product offline changes ownership of its nym or alias.

## Locked client behavior

### Name ownership

Before the first nym claim:

- show one nym input;
- validate and normalize it;
- explain that it is the permanent Lightning Address name and default web name;
- submit only after explicit confirmation.

After the nym claim:

- always show the nym read-only;
- never show a rename or second-name field;
- never describe the nym as inactive;
- use the same nym when turning Lightning Address online.

Before the first alias claim:

- Payment Page and Point of Sale may each show the same optional custom-link field because either product may be the first/only configured product;
- leaving it empty performs no alias operation and uses the nym URLs;
- claiming requires explicit confirmation that the alias is permanent and shared by both products.

After the alias claim:

- show the alias read-only in both products;
- never show clear, disable, rename, replace, or turn-alias-on controls;
- ordinary surface saves preserve the alias by omitting the alias field;
- share URLs use the alias whether the selected surface is online or offline.

### Product availability

The client presents only product controls:

- Turn Lightning Address on/off.
- Publish or take Payment Page offline.
- Publish or take Point of Sale offline.

Changing one product must not optimistically mutate another product's state. After any operation, refresh server state and render the three independently.

### Effective links

Without an alias:

- Payment Page: https://domain/<nym>
- Point of Sale: https://domain/<nym>/pos

With an alias:

- Payment Page: https://domain/a/<alias>
- Point of Sale: https://domain/a/<alias>/pos

The client consumes the server-returned public_url. It does not compose alias paths locally. Both legacy nym routes remain valid but the returned public_url is the default share link.

## Server dependency and capability gate

The client must not expose permanent-name UX against an older Bullnym server. Older servers may accept aliases with releasable or per-surface semantics.

Required lookup fields:

    {
      "nym": "alice",
      "active": false,
      "lightning_address_online": false,
      "alias": "coffee",
      "public_name_policy": "permanent_names_v1",
      "quota": { "used": 1, "cap": 1, "remaining": 0 }
    }

Rules:

- public_name_policy must equal permanent_names_v1 before enabling the new name-management UX.
- The compatibility active field is interpreted only as Lightning Address online status.
- alias is null only when no alias has ever been claimed.
- Unknown future response fields remain tolerated.
- Missing or unknown policy fails closed: hide alias claiming and do not offer any name mutation.
- Backend deployment and migration must precede the mobile release.

## Architecture

No new local database or public-name feature is required.

Ownership:

- bullnym owns wire models, signing, HTTP parsing, capability status, public name validation primitives, and structured server errors;
- lightning_address owns Lightning Address availability UX;
- payment_page owns Payment Page configuration and availability UX;
- pos owns Point of Sale configuration and availability UX;
- get_paid reads the three product facades and displays returned state.

New Payment Page and Point of Sale public-name status reads must go through feature-local use cases and their own public facades. Do not add new direct Bullnym calls from cubits.

The existing exception/failure and cross-feature-cubit architecture debt is not silently expanded. Any broad migration to the current Failure architecture or cubit/use-case rules remains an atomic follow-up PR; the public-name PRs add only the seams necessary for this feature.

## Client chunk 1: Bullnym protocol contract

Target stack branch: next branch after pr30-getpaid-sweep-labels.

### Domain and public contract

Update the Bullnym published contract with:

- BullnymQuota containing used, cap, and remaining;
- BullnymPublicNameStatus containing permanent nym, optional alias, Lightning Address online status, and policy;
- a validated public-name/alias primitive for 1-32 lowercase ASCII letters, digits, and internal hyphens with no leading/trailing hyphen;
- the server-reserved nym and alias value sets for immediate feedback;
- typed optional conflict details for owned nym and owned alias.

The server remains authoritative. A locally valid name can still lose a race.

### Registration lookup

Update:

- lib/features/bullnym/domain/bullnym_registration.dart
- lib/features/bullnym/data/bullnym_http_client.dart
- lib/features/bullnym/domain/bullnym_client_port.dart
- lib/features/bullnym/public/bullnym_facade.dart

Parse and publish:

- permanent nym;
- Lightning Address online status;
- optional permanent alias;
- quota;
- permanent_names_v1 capability.

Do not model name-active booleans.

### Donation page view

Update lib/features/bullnym/domain/bullnym_donation_page.dart:

- add String? alias;
- keep publicUrl;
- document that alias is the permanent canonical alias, independent of selected surface availability;
- remove any alias-active concept.

### Alias request intent

Represent alias writes explicitly:

    preserve
    claim(valid non-empty alias)

There is no clear, deactivate, reactivate, empty, or replace intent.

At the wire boundary:

- preserve omits the JSON key and signed field;
- claim sends a non-empty alias and appends it after kind;
- an empty alias cannot be constructed by product code.

### Signing

Update:

- lib/features/bullnym/domain/usecases/save_donation_page_usecase.dart
- lib/features/bullnym/domain/bullpay_signing.dart
- test/features/bullnym/bullnym_donation_page_contract_test.dart

Required byte contracts:

- preserve is byte-for-byte identical to the current seven mandatory fields, ct_descriptor, kind layout;
- first alias claim appends the non-empty alias after kind;
- alias remains the newest terminal optional field;
- no client test or production path signs an empty alias;
- Payment Page and Point of Sale use identical ordering.

### HTTP serialization

Update lib/features/bullnym/data/bullnym_http_client.dart:

- conditionally add alias only for a claim;
- parse alias from DonationPageView;
- parse the policy/status fields from registration lookup;
- parse structured details for NymAlreadyAssigned and AliasAlreadyAssigned;
- continue checking coded error envelopes at every HTTP status.

### Public URL trust boundary

Use server-returned public_url for both products, but validate it before exposing or launching it:

- HTTPS except the existing local-development HTTP exception;
- trusted configured Bullnym public origin;
- no userinfo, query, or fragment;
- path shape matches returned kind and alias/nym;
- bounded length;
- invalid values become InvalidServerResponse.

If API and public origins can differ in a supported deployment, add an explicit trusted public-origin configuration instead of accepting arbitrary server origins.

### Protocol tests

- Alias absent/null response parses as no claim.
- Claimed alias response parses.
- Lookup policy and product status parse.
- Unknown response keys are tolerated.
- Missing/invalid typed fields fail closed.
- Preserve request omits alias key.
- Claim request includes non-empty alias key.
- Both byte layouts verify against an independent oracle.
- Structured conflict details parse without exposing reason to users.
- Public URL origin/path validation rejects hostile values.

Gate:

- focused Bullnym tests;
- full project analyze;
- no UI enabled yet.

## Client chunk 2: Permanent nym and Lightning Address availability

### Nym validation

Replace the current minimal empty/@ validation with the exact shared server syntax and reserved-name prefilter.

Input behavior:

- trim surrounding whitespace;
- normalize to lowercase before confirmation;
- reflect normalization back to the field;
- reject invalid edges, characters, byte/length limits, and reserved names;
- reject alias/nym shared-name conflicts from stable server codes.

### First claim

The Lightning Address setup screen:

- shows the nym field only when lookup confirms no lifetime nym;
- explains that the nym is permanent;
- confirms before the first signed registration;
- stores no additional local ownership record;
- reloads the server status after success.

### Claimed nym

Once lookup returns a nym:

- display it read-only in every Lightning Address state;
- remove any path that edits state.nym into a different value;
- do not use previous_nyms as a rename menu;
- treat NymAlreadyAssigned as a reload/reconciliation signal and show the server-owned nym;
- keep quota for diagnostics/compatibility, not for offering another slot.

### Lightning Address online/offline

User-facing actions:

- Turn Lightning Address off calls DELETE /register.
- Turn Lightning Address on submits the already-owned nym through the same-name server path.
- No naming confirmation is repeated.
- Reload after either operation.
- Payment Page and Point of Sale state in the dashboard remains unchanged.

Rename internal presentation states where practical from active/inactive to online/offline. At minimum, all user-facing text and domain comments must use product-status terminology.

### Errors and localization

Add distinct localized handling for:

- NameTaken;
- NymAlreadyAssigned with the owned nym;
- NymInvalid/NymReserved;
- capability unavailable;
- network/timeout/uncertain product toggle.

Never display the server reason string.

### Lightning Address tests

- First claim shows one input and confirmation.
- Successful claim makes the nym permanently read-only.
- Different-name registration is never offered.
- Turning the product off retains the nym.
- Turning it on uses the same nym.
- Reinstall/app-state wipe reloads the same nym from the server.
- Payment Page/POS dashboard state does not change across the toggle.
- Policy missing hides new name controls.

Gate:

- Lightning Address unit, cubit, widget, and lifecycle tests;
- full project analyze.

## Client chunk 3: Shared alias in Payment Page and Point of Sale

The alias control must exist in both product settings because either surface may be configured first or exist alone. Both controls read the same npub-level status from the server.

### Unclaimed alias UX

When alias is null:

- show Custom link name (optional);
- explain that blank uses the permanent nym;
- explain that one alias is shared by Payment Page and Point of Sale;
- normalize/validate locally;
- require a permanent-claim confirmation before save;
- submit the alias only when the user explicitly confirmed a non-empty value.

If the field is blank or untouched, the surface save uses preserve and omits alias from JSON/signing.

### Claimed alias UX

When alias is non-null:

- show it read-only;
- show both resulting route shapes;
- remove the editable alias field;
- provide no clear, off/on, rename, or replacement action;
- ordinary page/POS content saves use preserve;
- stale conflicting responses reload the server-owned alias.

### Payment Page

Update the Payment Page entity, command, use cases, facade, state, cubit, and editor:

- surface entity carries permanent alias plus server publicUrl;
- editor loads npub-level public-name status even when no Payment Page row exists;
- first claim is included only in an explicitly confirmed save;
- archive/publish changes only Payment Page status;
- claimed alias remains visible and unchanged while the page is offline;
- share row always uses validated server publicUrl.

### Point of Sale

Update the Point of Sale entity, command, use cases, facade, state, cubit, locator, and provisioning screen:

- replace client-built /<nym>/pos URL with validated server public_url;
- remove terminalBaseUrl URL-composition plumbing once unused;
- load the same npub-level alias status even when no POS row exists;
- first claim follows the same confirmation/serialization rules as Payment Page;
- archive/publish changes only POS status;
- claimed alias remains visible and unchanged while POS is offline.

### Cross-surface synchronization

No local event bus or alias database is needed.

- After a claim through either product, reload that product.
- Returning to Get Paid already refreshes Payment Page and POS.
- Both surface reads must return the same alias and their kind-specific URL.
- Opening the other product reloads npub-level status.
- Concurrent first claims rely on the server; the loser maps the stable error and reloads.

### Alias errors and localization

Add specific copy for:

- invalid/reserved custom link name;
- NameTaken;
- AliasAlreadyAssigned with the permanent owned alias;
- permanent-claim confirmation;
- shared-across-products explanation;
- capability unavailable.

Do not add copy for alias deactivation or alias reactivation.

### Alias tests

- Blank alias saves omit alias and use nym URLs.
- First claim from Payment Page is confirmed and appears in both product statuses.
- First claim from POS behaves identically.
- Claimed alias becomes read-only in both screens.
- Ordinary content saves omit alias and preserve it.
- A different alias is never offered after reload.
- NameTaken and AliasAlreadyAssigned reconcile correctly.
- Taking Payment Page offline leaves POS and the alias unchanged.
- Taking POS offline leaves Payment Page and the alias unchanged.
- Taking Lightning Address offline leaves both surface URLs/statuses unchanged.
- POS uses /a/<alias>/pos from server public_url.
- Dashboard subtitles display the returned nym or alias URLs.

Gate:

- Payment Page and POS unit/cubit/widget tests;
- cross-surface integration tests;
- full project analyze.

## Test-support and integration harness changes

Update integration_test/support/fake_bullnym_client.dart so it models the server, not the old per-surface alias behavior:

- one permanent nym claim per npub;
- one optional permanent alias per npub;
- shared nym/alias allocation namespace;
- separate Lightning Address, Payment Page, and POS online states;
- alias claim-only semantics;
- no empty-alias mutation;
- same alias returned for both surface reads;
- independent public URLs and surface availability;
- stable conflict details and permanent_names_v1 policy.

Update recording clients and fixtures in:

- test/features/bullnym
- test/features/lightning_address
- test/features/payment_page
- test/features/pos
- test/features/get_paid
- integration_test/payment_page_lifecycle_test.dart
- integration_test/pos_lifecycle_test.dart
- integration_test/get_paid_backup_roundtrip_test.dart

Add one integration matrix covering all eight combinations of the three product online/offline states.

## Documentation and generated artifacts

Update:

- lib/features/bullnym/bullnym_architecture.md
- lib/features/lightning_address/lightning_address_architecture.md
- lib/features/payment_page/payment_page_architecture.md
- lib/features/pos/pos_architecture.md
- localization/app_en.arb and generated localizations
- relevant public contract tests and integration-test comments

Do not add local persistence migrations.

Run repository-standard generation commands through the Makefile and pinned FVM toolchain.

## Proposed mobile PR stack

### PR31: Bullnym permanent-name protocol

Scope:

- models;
- lookup policy/status;
- alias claim-only request;
- signing;
- error details;
- public URL validation;
- protocol fakes/tests.

No user-facing name UI.

### PR32: Permanent nym and Lightning Address status

Scope:

- exact validation;
- first-claim confirmation;
- claimed nym read-only;
- Lightning Address online/offline controls;
- errors/localization/tests.

### PR33: Shared alias for Payment Page and Point of Sale

Scope:

- optional first claim in both surfaces;
- permanent read-only claimed alias;
- POS server public URL;
- surface independence;
- dashboard/cross-surface integration tests.

Each PR is stacked on the previous one until the existing Get Paid stack lands. Do not release PR32/PR33 behavior before the server advertises permanent_names_v1.

## Verification commands

Use the repository-standard pinned toolchain:

- make translations when localization changes;
- make build-runner when generated models require it;
- make unit-test;
- targeted integration tests on the supported device harness;
- make analyze;
- fvm dart fix --dry-run, which must report nothing to fix.

Never use bare flutter/dart and never bypass the pre-commit hook.

## Mobile definition of done

- The nym field appears only before the first lifetime claim.
- The alias field appears only before the first lifetime alias claim.
- Claimed names are always read-only.
- No UI or domain intent can clear, disable, reactivate, rename, or replace a name.
- Lightning Address, Payment Page, and Point of Sale each have independent online/offline controls.
- Toggling one product does not alter another product's state.
- No alias means nym URLs with no alias signed field.
- Claimed alias means both products use their server-returned alias URLs.
- POS no longer composes its public URL.
- The client fails closed against servers without permanent_names_v1.
- Recovery/app-state wipe reconstructs all ownership and product status from the server.
- Contract, signing, product-state, cross-surface, integration, localization, and analyzer gates pass.

## Explicit non-goals

- Local storage of public-name ownership.
- Alias or nym rename.
- Alias or nym on/off controls.
- Multiple normal nyms or aliases.
- Restoring migration tombstones.
- Linking the three product availability toggles.
- Rebuilding unrelated Get Paid architecture in the feature PRs.
