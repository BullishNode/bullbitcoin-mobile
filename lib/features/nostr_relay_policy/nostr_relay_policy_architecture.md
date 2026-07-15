# Nostr Relay Policy

`nostr_relay_policy` owns Bull app-level Nostr relay defaults. The relay list is
product policy, not generic Nostr cryptography, so it does not live in
`core/nostr`. It is also not specific to keychain manifest recovery.

The initial relay list is a product decision locked in the current PR19 planning
flow for BullishNode/bullbitcoin-mobile issue #3; the historical
`feature/get-paid-deterministic-wallets-clean` branch was used only as planning
inspiration. This is a privacy and reliability decision because recovery flows
may automatically query third-party public relays. The code source of truth for
the literal relay list is `NostrRelayPolicyFacade`; this document intentionally
does not duplicate it.

The feature exposes a headless policy contract through its public facade. It has
no global locator registration until a production feature consumes it.

Rules:

- Relays must be canonical `wss://` URLs with a non-empty host.
- Relay URL canonicalization lowercases scheme and host, removes the default
  `:443` port, and removes an empty trailing slash.
- Exact canonical duplicate relay URLs are removed.
- The policy marks whether defaults are third-party public relays via
  `usesThirdPartyPublicRelays`. When that flag is set, consumers MUST gate any
  publish or fetch against those relays on the user's Automated-backup consent
  (the persisted Get Paid settings toggle plus the one-time consent dialog —
  decision [3]); the flag marks where that gate is required, it does not grant
  consent itself. Decision [3] supersedes the earlier request to rename the flag
  to `requiresThirdPartyRelayDisclosure`: the real consent feature replaces a
  bare disclosure, so the flag name is kept and this supersession closes the
  locked-term deviation in writing.
- Seed-recovery flows may use these defaults automatically to check for remote
  encrypted manifests. Normal app startup, periodic background scans, and
  ordinary wallet operation must not use them implicitly.
- No relay health checks, persistence, settings UI, relay discovery, generic
  Nostr client, publish/fetch transport, or background retry worker lives here.
- Consumers that choose these defaults must go through `NostrRelayPolicyFacade`;
  they still own their protocol-specific event content, publish/fetch semantics,
  errors, and user flows.
