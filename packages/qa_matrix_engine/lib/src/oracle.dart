import 'package:meta/meta.dart';

import 'parameter_model.dart';
import 'scenario.dart';

/// A provider-agnostic mirror of the app's terminal recovery statuses. The
/// Flutter runner maps the real `RemoteKeychainRecoveryStatus` onto this so the
/// engine stays free of app imports.
enum ExpectedRecoveryClass {
  restored,
  partiallyRestored,
  olderManifestAvailable,
  nothingToRestore,
  unsupportedNewerManifest,
  relaysUnavailable,
  noRecoverableManifest,
  restoreFailed,
  defaultWalletUnavailable,
}

/// The analytic expectation for a tuple (§5.3 step 6): the set of terminal
/// classes that count as correct (a set, not a single value, so benign
/// variation — e.g. restored vs partiallyRestored under an interrupt — passes),
/// plus a short rationale for the report.
@immutable
class ExpectedOutcome {
  const ExpectedOutcome(this.acceptable, this.rationale);

  final Set<ExpectedRecoveryClass> acceptable;
  final String rationale;

  bool accepts(ExpectedRecoveryClass actual) => acceptable.contains(actual);
}

/// Derives the expected recovery outcome purely from the tuple — no per-row
/// hard-coding (§5.3 step 6). Precedence is deliberate and documented.
class RecoveryOracle {
  const RecoveryOracle();

  ExpectedOutcome derive(ScenarioTuple t) {
    final manifest = t.get(ParameterModel.dManifest);
    final relay = t.get(ParameterModel.dRelay);
    final network = t.get(ParameterModel.dNetwork);
    final seed = t.get(ParameterModel.dSeed);

    // 1. Nothing CONTACTED => relaysUnavailable (loud, distinct from "absent").
    // Reconciled with the shipped fetch semantics: `relaysUnavailable` requires
    // `contactedAnyRelay == false`, which only a refused socket produces
    // (relay=all-down / network=offline). A `never-eose` relay IS contacted —
    // the stored events stream before the delayed EOSE, and the fetch simply
    // times out with whatever arrived — so it resolves to the normal
    // manifest/seed outcome (an absent/hostile coordinate => noManifestFound),
    // never `relaysUnavailable`.
    final noRelayReachable = network == 'offline' || relay == 'all-down';
    if (noRelayReachable) {
      return const ExpectedOutcome(
        {ExpectedRecoveryClass.relaysUnavailable},
        'no relay reachable within the per-relay timeout',
      );
    }

    // 2. Wrong/partial seed or no manifest => the coordinate is empty.
    if (seed != 'correct' || manifest == 'none') {
      return const ExpectedOutcome(
        {ExpectedRecoveryClass.nothingToRestore},
        'seed-derived coordinate is empty (wrong seed or nothing published)',
      );
    }

    // 3. Authentic newer version => update-the-app, never "no backup".
    if (manifest == 'newer-version') {
      return const ExpectedOutcome(
        {ExpectedRecoveryClass.unsupportedNewerManifest},
        'authentic newer-version manifest (KC-2)',
      );
    }

    // 4. Undecryptable / inauthentic => treated as absent, never materialised.
    if (manifest == 'corrupt-undecryptable' ||
        manifest == 'tampered' ||
        manifest == 'forged-author') {
      return const ExpectedOutcome(
        {
          ExpectedRecoveryClass.noRecoverableManifest,
          ExpectedRecoveryClass.nothingToRestore,
        },
        'corrupt/tampered/forged event rejected pre-materialise (P6)',
      );
    }

    // 5. Older-populated => the "restore older?" branch.
    if (manifest == 'older-populated') {
      return const ExpectedOutcome(
        {ExpectedRecoveryClass.olderManifestAvailable},
        'a populated older manifest is offered for explicit restore',
      );
    }

    // 6. Empty-newest: divergent stages a populated sibling (KC-1) => restore;
    //    otherwise the only event is empty => nothingToRestore.
    if (manifest == 'empty-newest') {
      if (relay == 'divergent') {
        return const ExpectedOutcome(
          {ExpectedRecoveryClass.restored, ExpectedRecoveryClass.partiallyRestored},
          'populated older sibling outranks the empty newest (KC-1)',
        );
      }
      return const ExpectedOutcome(
        {ExpectedRecoveryClass.nothingToRestore},
        'the only event is empty; never a fake "restored" (P4)',
      );
    }

    // 7. Current + reachable + correct seed => a real restore. A one-relay
    //    fault (reject/timeout/flood/forge) still leaves a good relay, and an
    //    interrupt may land in partiallyRestored on the first pass.
    return const ExpectedOutcome(
      {ExpectedRecoveryClass.restored, ExpectedRecoveryClass.partiallyRestored},
      'a current authentic manifest on a reachable relay restores',
    );
  }
}
