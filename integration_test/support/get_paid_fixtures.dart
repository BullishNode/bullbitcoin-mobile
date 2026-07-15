// Shared fixtures for the Get Paid L1 flows (HARNESS §2.5).

/// A committed, valueless fixture mnemonic (the `zoo…wrong` vector). Nothing
/// here touches mainnet funds, so no secret is needed and the tests stay
/// hermetic (no dependency on CI secrets).
const getPaidFixtureMnemonicWords = <String>[
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'wrong',
];

/// The expected Get Paid posture, imported by BOTH the pairing-time and
/// recovery-time assertions so the two paths cannot drift apart (POSTURE-01).
const expectedGetPaidPosture = (hidden: true, autosweep: true);

/// The two LOCKED copy strings, as test literals (NOT arb-key references) so any
/// reword of the shipped copy is caught.
const lockedConsentBody =
    'An encrypted backup of your wallet metadata will be created and '
    'published anonymously on NOSTR so that when you recover your wallet, the '
    'BULL app will automatically recover your Get Paid wallet. Your private '
    'keys never leave the device. This is highly recommended and does not '
    'compromise your privacy or security.';

const lockedOffWarning =
    'You will need to manually re-enable the Get Paid feature you are '
    'activating now to recover funds you received with this feature.';
