# Core Nostr

`core/nostr` is the app-wide generic Nostr key boundary. It owns BIP85 path
derivation, BIP340 hash signing, and public-key access through the existing
`bitcoin_base` crypto stack.

Feature-specific protocol semantics stay outside this package. Bullnym actions,
Lightning Address message fields, wallet manifest events, profile content,
public identity registration, DMs, and UI policy belong to feature layers.

## BIP85 Derivation

Nostr keys are derived with BIP85 application `128002`:

```text
m/83696968'/128002'/{identity}'/{account_index}'
```

Bull's namespace policy leaves identity `0'` and account `0'` unused because
the current BIP proposal reserves them. User-created identities allocate the
first free identity in `1'..99'`, always at account `1'`. App-owned roles use
identities `100'..199'`, also at account `1'`; currently assigned roles are
wallet backup (`100'`), Bullnym authentication (`101'`), and NIP-05 public-nym
verification (`102'`). User allocation can therefore never collide with an app
role, including a future role added within the reserved app range.

This is a pre-release namespace correction. Paths under the former application
numbers `86'` and `9000'` are not imported or migrated.

Generic callers pass a BIP85 hardened path accepted by `Bip85HardenedPath`.
Bull product features should use the role-named helpers exposed by
`features/nostr_identity/public/nostr_identity_facade.dart`, which consumes the
canonical registry suffix paths, such as `128002'/100'/1'`, from
`features/bip85_registry`.

## Public Surface

- `NostrKeychainHandle` wraps the key object without exposing raw
  secret-key material during normal signing/public-key use.
- `NostrKeychainHandle` derives keys from BIP85 hardened paths, returns
  x-only public keys, and signs explicit 32-byte hash hex values.
- `NostrKeychainSecretMaterializer` is restricted to explicit private-key
  reveal flows; its result is ephemeral Nsec text and must never be persisted.
- The settings key list persists public materialization metadata only. An nsec
  is derived from the local root key when the user explicitly reveals it, held
  only in presentation memory, and discarded when the screen is disposed.

## Boundaries

- DTOs and persistence models must not contain `NostrKeychainHandle`.
- Feature layers pass public keys and signatures across their own ports.
- Feature layers own their protocol-specific event contents and relay behavior.
- `toString()` implementations must never include secret-key material.
