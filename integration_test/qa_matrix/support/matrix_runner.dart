import 'package:get_it/get_it.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import 'invariant_assertions.dart';
import 'recovery_status_mapping.dart';
import 'scenario_compiler.dart';

/// Runs one [GeneratedCase] end to end (GETPAID-APP-E2E-FAILURE-MATRIX §5.3
/// steps 5-7): compile+stage the tuple, drive the real recovery cubit, map the
/// terminal status onto the analytic oracle, score the applicable invariants,
/// and fold it all into one [EvidenceRecord]. Only [CaseOutcome.passed]
/// certifies; a tuple this build cannot stage becomes [CaseOutcome.blocked],
/// never a Fail (the §12 rich-outcome model).
Future<EvidenceRecord> runCase(GetIt locator, GeneratedCase c) async {
  if (!c.isFeasible) {
    return _record(
      c,
      outcome: CaseOutcome.skipped,
      observed: null,
      invariants: const [],
      message: c.feasibility.reason,
    );
  }

  final CompiledScenario scenario;
  try {
    scenario = await ScenarioCompiler(locator).compileAndStage(c.tuple);
  } on ScenarioUnsupported catch (e) {
    return _record(
      c,
      outcome: CaseOutcome.blocked,
      observed: null,
      invariants: const [],
      defectClass: DefectClass.deployGated,
      message: e.reason,
    );
  }

  final observed = mapRecoveryStatus(scenario.finalState.status);
  final invariants = scoreInvariants(scenario);
  final violations = invariants.where((r) => r.violated).toList();

  // Oracle check: an interrupted run was cut before a verdict, so its terminal
  // class is not scored against the oracle (P12 owns interrupt safety instead).
  final oracleSatisfied = scenario.interrupted ||
      (observed != null && c.expected.accepts(observed));

  final passed = violations.isEmpty && oracleSatisfied;

  DefectClass? defect;
  String? message;
  if (!passed) {
    if (violations.isNotEmpty) {
      defect = InvariantLibrary.byId(violations.first.id).defectClass;
      message = violations
          .map((v) => '${v.id}:${v.detail ?? ''}')
          .join(' | ');
    } else {
      // Oracle mismatch with no invariant violated: a wrong terminal class.
      defect = observed == ExpectedRecoveryClass.restored ||
              observed == ExpectedRecoveryClass.partiallyRestored
          ? DefectClass.falseSuccess
          : DefectClass.recoveryLostBackup;
      message = 'oracle: expected ${c.expected.acceptable} '
          '(${c.expected.rationale}); observed $observed '
          '[status=${scenario.finalState.status}]';
    }
  }

  return _record(
    c,
    outcome: passed ? CaseOutcome.passed : CaseOutcome.failed,
    observed: observed,
    invariants: invariants,
    defectClass: defect,
    message: message,
  );
}

EvidenceRecord _record(
  GeneratedCase c, {
  required CaseOutcome outcome,
  required ExpectedRecoveryClass? observed,
  required List<InvariantResult> invariants,
  DefectClass? defectClass,
  String? message,
}) {
  return EvidenceRecord(
    scenarioId: c.id,
    tuple: c.tuple,
    feature: c.feature,
    scenarioClass: c.scenarioClass,
    oracleClass: OracleClass.invariantProperty,
    expected: c.expected,
    observedClass: observed,
    outcome: outcome,
    invariantResults: invariants,
    defectClass: defectClass,
    message: message,
  );
}
