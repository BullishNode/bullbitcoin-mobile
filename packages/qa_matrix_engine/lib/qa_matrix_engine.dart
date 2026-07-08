/// The seeded combinatorial QA engine for the Get Paid app E2E failure matrix
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5/§6/§12).
///
/// Pure Dart, zero app imports: the parameter model, the covering-array
/// generator, the scenario tuple + feasibility filter, the recovery oracle, the
/// P1-P14 invariant registry, the outcome model, and the reporter. The Flutter
/// integration specs on the `qa/e2e-matrix` overlay compile a [GeneratedCase]
/// into a fake configuration, drive the app's real code, and score the run
/// against these invariants.
library;

export 'src/covering_array.dart';
export 'src/generator.dart';
export 'src/invariants.dart';
export 'src/oracle.dart';
export 'src/outcome.dart';
export 'src/parameter_model.dart';
export 'src/reporter.dart';
export 'src/scenario.dart';
