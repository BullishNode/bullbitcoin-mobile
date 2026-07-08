// Committed, valueless fixtures for the QA-matrix S-INJECT lane
// (GETPAID-APP-E2E-FAILURE-MATRIX §11-D7). Nothing here touches mainnet funds,
// so the suite stays hermetic (no CI secrets) and deterministic. Two distinct
// valid BIP39 mnemonics let the D9 seed dimension stage `correct` vs `wrong`.

/// The primary fixture seed — the same `zoo…wrong` vector the existing L1
/// round-trip uses, so a QA-matrix restore of a manifest published under this
/// seed reproduces the proven happy path.
const matrixCorrectMnemonic = <String>[
  'zoo', 'zoo', 'zoo', 'zoo', 'zoo', 'zoo', //
  'zoo', 'zoo', 'zoo', 'zoo', 'zoo', 'wrong',
];

/// A second, unrelated valid mnemonic (the canonical all-zero-entropy BIP39
/// vector). Recovering under this seed derives a different manifest author key,
/// so the seed-derived `(author, 30078, manifest)` coordinate is empty — the
/// D9 `wrong` value. It must NEVER surface another seed's data (WS / P2).
const matrixWrongMnemonic = <String>[
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'abandon', //
  'abandon', 'abandon', 'abandon', 'abandon', 'abandon', 'about',
];

/// The controlled relay URL set the QA matrix pins the [NostrRelayPolicyFacade]
/// to (overriding the 7 shipped public relays), so the in-process connect
/// dispatcher can route each URL to a distinct [FakeNostrRelay] — the E9
/// two-relay harness the `divergent` / `empty-newest` cells need.
const matrixRelayUrlPrimary = 'wss://matrix-relay-a.invalid';
const matrixRelayUrlSecondary = 'wss://matrix-relay-b.invalid';

/// The staging offset (seconds) between an older-populated event and a
/// newer-but-unusable one on the same coordinate, large enough to survive any
/// clock-skew value in D8 (±10 min / +400 s).
const matrixManifestStagingSkewSecs = 3600;
