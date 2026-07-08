import 'package:meta/meta.dart';

import 'invariants.dart';
import 'oracle.dart';
import 'scenario.dart';

/// The rich outcome enum mined from bullnym-tests (§12): only [passed]
/// certifies; the rest are distinct and non-fatal so a red run means a real
/// regression, not a deploy-gated or unbuilt case.
enum CaseOutcome {
  passed,
  failed,
  skipped,
  blocked,
  missingFixture,
  unsupportedEnvironment,
  inconclusive,
  manualOnly;

  bool get certifies => this == CaseOutcome.passed;
}

/// The oracle-class taxonomy (§12) — what kind of check the case principally is.
enum OracleClass {
  shapeOnly,
  fieldEquality,
  stateTransition,
  destinationProof,
  idempotencyProof,
  negativeBoundary,
  invariantProperty,
  externalEventualObservation,
  manualPlaybook,
}

/// The result of evaluating one invariant against a run.
@immutable
class InvariantResult {
  const InvariantResult({
    required this.id,
    required this.applicable,
    required this.satisfied,
    this.detail,
  });

  final String id;
  final bool applicable;
  final bool satisfied;
  final String? detail;

  bool get violated => applicable && !satisfied;
}

/// The evidence record for one case (§5.3 step 7 / §12 report row). This is what
/// the reporter aggregates; only [outcome] == passed certifies.
@immutable
class EvidenceRecord {
  const EvidenceRecord({
    required this.scenarioId,
    required this.tuple,
    required this.feature,
    required this.scenarioClass,
    required this.oracleClass,
    required this.expected,
    required this.observedClass,
    required this.outcome,
    required this.invariantResults,
    this.defectClass,
    this.message,
  });

  final ScenarioId scenarioId;
  final ScenarioTuple tuple;

  /// Feature id (e.g. `F5`) this case is primarily attributed to.
  final String feature;

  /// Scenario class (e.g. `RB`).
  final String scenarioClass;
  final OracleClass oracleClass;
  final ExpectedOutcome expected;

  /// The class the run actually reached (null if the run never produced one).
  final ExpectedRecoveryClass? observedClass;
  final CaseOutcome outcome;
  final List<InvariantResult> invariantResults;

  /// Set on a Fail: which defect bucket this failure belongs to (§12).
  final DefectClass? defectClass;
  final String? message;

  Iterable<InvariantResult> get violations =>
      invariantResults.where((r) => r.violated);
}
