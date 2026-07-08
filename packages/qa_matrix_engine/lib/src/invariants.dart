import 'parameter_model.dart';
import 'scenario.dart';

/// The money-safety defect buckets a failing case is diagnosed into
/// (GETPAID-APP-E2E-FAILURE-MATRIX §6/§12).
enum DefectClass {
  recoveryLostBackup('RecoveryLostBackup'),
  falseSuccess('FalseSuccess'),
  authenticityBroken('AuthenticityBroken'),
  postureRegression('PostureRegression'),
  doubleSpendOrStuckPay('DoubleSpendOrStuckPay'),
  corruptAfterInterrupt('CorruptAfterInterrupt'),
  cleartextLeak('CleartextLeak'),
  harnessBug('HarnessBug'),
  externalDependency('ExternalDependency'),
  deployGated('DeployGated');

  const DefectClass(this.label);
  final String label;
}

/// A property invariant descriptor (GETPAID-APP-E2E-FAILURE-MATRIX §6, P1-P14).
/// The engine owns the metadata + the [appliesTo] predicate over a tuple; the
/// concrete assertion lives on the Flutter side keyed by [id]. [defectClass] is
/// what a violation is bucketed as.
class Invariant {
  const Invariant({
    required this.id,
    required this.title,
    required this.ruling,
    required this.defectClass,
    // The private field's public parameter label is `appliesTo` (Dart strips
    // the leading underscore from initializing-formal parameter names).
    required this._appliesTo,
  });

  /// `P1`..`P14`.
  final String id;
  final String title;

  /// The decision/ruling this invariant enforces (for the report).
  final String ruling;
  final DefectClass defectClass;
  final bool Function(ScenarioTuple tuple) _appliesTo;

  bool appliesTo(ScenarioTuple tuple) => _appliesTo(tuple);

  @override
  String toString() => '$id ($title)';
}

/// The P1-P14 registry. `library` returns the descriptors; the evaluator asks
/// each whether it [Invariant.appliesTo] the tuple and asserts the applicable
/// ones (a single recovery permutation typically evaluates 6-9 at once).
class InvariantLibrary {
  static const _manifestPresentReachable = _ManifestPresentReachable();

  static bool _relayReachable(ScenarioTuple t) {
    final relay = t.get(ParameterModel.dRelay);
    final network = t.get(ParameterModel.dNetwork);
    if (network == 'offline') return false;
    return relay != 'all-down' && relay != 'never-eose';
  }

  static bool _publishExercised(ScenarioTuple t) =>
      t.get(ParameterModel.dBackup).startsWith('on');

  static bool _walletSetHasLightning(ScenarioTuple t) =>
      t.get(ParameterModel.dWalletSet).contains('101');

  static final List<Invariant> all = [
    Invariant(
      id: 'P1',
      title: 'Recovery totality',
      ruling: 'RemoteKeychainRecoveryCubit always reaches a terminal typed '
          'status within the per-relay timeout; never a non-terminal limbo.',
      defectClass: DefectClass.harnessBug,
      appliesTo: (t) => true,
    ),
    Invariant(
      id: 'P2',
      title: 'No false "no backup"',
      ruling: 'A decryptable authentic manifest on >=1 reachable relay is never '
          'reported noManifestFound/nothingToRestore (KC/P21b).',
      defectClass: DefectClass.recoveryLostBackup,
      appliesTo: _manifestPresentReachable.test,
    ),
    Invariant(
      id: 'P3',
      title: 'Byte-identity or honest failure',
      ruling: 'A wallet reported restored rebuilds a byte-identical manifest '
          'payload; anything else is in failedCount (KC-6 / [F] freeze).',
      defectClass: DefectClass.falseSuccess,
      appliesTo: (t) =>
          _manifestPresentReachable.test(t) &&
          t.isValue(ParameterModel.dManifest, 'current'),
    ),
    Invariant(
      id: 'P4',
      title: 'Populated outranks empty/stale',
      ruling: 'A populated manifest always outranks empty/stale-newest; an '
          'all-empty union is nothingToRestore, never fake "restored" (KC-1).',
      defectClass: DefectClass.falseSuccess,
      appliesTo: (t) =>
          t.isValue(ParameterModel.dManifest, 'empty-newest') ||
          t.isValue(ParameterModel.dRelay, 'divergent'),
    ),
    Invariant(
      id: 'P5',
      title: 'Newer implies update-app',
      ruling: 'An authentic newer-version manifest yields '
          'unsupportedNewerManifest, never noManifestFound (KC-2).',
      defectClass: DefectClass.recoveryLostBackup,
      appliesTo: (t) => t.isValue(ParameterModel.dManifest, 'newer-version'),
    ),
    Invariant(
      id: 'P6',
      title: 'Authenticity',
      ruling: 'A forged-author / tampered / wrong-key event is never accepted: '
          'sig verified before decrypt, EtM is the authenticity gate (PR17/21).',
      defectClass: DefectClass.authenticityBroken,
      appliesTo: (t) =>
          t.isValue(ParameterModel.dManifest, 'tampered') ||
          t.isValue(ParameterModel.dManifest, 'forged-author') ||
          t.isValue(ParameterModel.dRelay, 'one-forge'),
    ),
    Invariant(
      id: 'P7',
      title: 'Consent gate',
      ruling: 'Network publish fires only when automatedBackupEnabled AND (no '
          'third-party relays OR disclosure acknowledged); the local record is '
          'unconditional (PR23 / DG[3]).',
      defectClass: DefectClass.cleartextLeak,
      appliesTo: (t) => true,
    ),
    Invariant(
      id: 'P8',
      title: 'Publish honesty',
      ruling: 'Publish reports success only on a true >=1 ["OK",id,true]; '
          'blocked/auth-required/no-OK never counts (AD-3).',
      defectClass: DefectClass.falseSuccess,
      appliesTo: _publishExercised,
    ),
    Invariant(
      id: 'P9',
      title: 'Posture preservation',
      ruling: 'Every created/restored Get Paid wallet is hideOnHome=true + '
          'autoSweepEnabled=true (KC-6 / DG[1]).',
      defectClass: DefectClass.postureRegression,
      appliesTo: (t) => !t.isValue(ParameterModel.dWalletSet, 'none'),
    ),
    Invariant(
      id: 'P10',
      title: 'DG-3 heal',
      ruling: 'A lapsed registration is re-registered silently with the SAME '
          'nym/descriptor, or surfaced loud (healOutcome=unreachable) — never '
          'silently broken, never false "healed".',
      defectClass: DefectClass.recoveryLostBackup,
      appliesTo: (t) =>
          _walletSetHasLightning(t) &&
          t.get(ParameterModel.dServer) != 'up-live',
    ),
    Invariant(
      id: 'P11',
      title: 'Direct-pay safety',
      ruling: 'LUD-22 direct-pay never double-pays; every "not possible" falls '
          'back to swap cleanly; SSRF host-pin holds (DG-7/8).',
      defectClass: DefectClass.doubleSpendOrStuckPay,
      // F8-only; the recovery-family tuples do not exercise the payer.
      appliesTo: (t) => false,
    ),
    Invariant(
      id: 'P12',
      title: 'No corrupt state after interrupt',
      ruling: 'Any interrupt leaves no corrupt local state; the next run '
          'resumes/cleanly reports; _operationId guards stale-async clobber.',
      defectClass: DefectClass.corruptAfterInterrupt,
      appliesTo: (t) => t.get(ParameterModel.dInterrupt) != 'none',
    ),
    Invariant(
      id: 'P13',
      title: 'Idempotency',
      ruling: 'Re-register / re-publish / re-prove is idempotent: same nym, '
          'single NIP-33 event, LA cursor untouched on non-101 paths (KR-1).',
      defectClass: DefectClass.falseSuccess,
      appliesTo: (t) =>
          _publishExercised(t) || t.get(ParameterModel.dServer) == 'up-lapsed',
    ),
    Invariant(
      id: 'P14',
      title: 'Wire opacity',
      ruling: 'Stored event content is bare base64 (decodes, no "{", no '
          'envelope keys); no bull-identifying strings on the wire; kind 30078, '
          'd-tag manifest (WIRE-01 / decision[2] / AD-5).',
      defectClass: DefectClass.cleartextLeak,
      appliesTo: _publishExercised,
    ),
  ];

  static Invariant byId(String id) =>
      all.firstWhere((i) => i.id == id, orElse: () {
        throw ArgumentError('no invariant $id');
      });

  /// The invariants applicable to [tuple], in P-order.
  static List<Invariant> applicableTo(ScenarioTuple tuple) =>
      all.where((i) => i.appliesTo(tuple)).toList(growable: false);
}

class _ManifestPresentReachable {
  const _ManifestPresentReachable();

  bool test(ScenarioTuple t) {
    final manifest = t.get(ParameterModel.dManifest);
    final present = manifest == 'current' || manifest == 'older-populated';
    if (!present) return false;
    return InvariantLibrary._relayReachable(t) &&
        t.get(ParameterModel.dSeed) == 'correct';
  }
}
