import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import 'support/matrix_runner.dart';

// Phase-1 combinatorial generation (GETPAID-APP-E2E-FAILURE-MATRIX §5.2):
// CG-1 (smoke floor) ∪ CG-2 (pairwise over the 9 dimensions) ∪ CG-3 (the
// full-factorial D3×D4×D9 recovery core, folded). This spec proves the seeded
// generator produces a reproducible, bounded case list and that a bounded
// feasible SAMPLE drives green against real app code — the full sweep and the
// two-relay/crafted cells are the documented Phase-1 remainder (they assert as
// non-fatal Blocked, never Fail).
//
// Fork-only overlay; run directly:
//   fvm flutter test integration_test/qa_matrix/qa_matrix_generative_test.dart
Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  // The bounded in-process sample size (each case is a full stage+recover, so
  // the whole generated set is a background/nightly run; this keeps the on-demand
  // spec inside the foreground budget while exercising every tier).
  const sampleCap = 40;

  test('CG generation is reproducible and a bounded sample certifies', timeout:
      const Timeout(Duration(minutes: 15)), () async {
    final generator = MatrixGenerator();
    final all = generator.generateAll(seed: 0);
    final feasible = all.where((c) => c.isFeasible).toList();

    // Reproducibility: the same seed yields the identical case list.
    final again = generator.generateAll(seed: 0);
    expect(
      again.map((c) => c.tuple.describe()).toList(),
      all.map((c) => c.tuple.describe()).toList(),
    );

    int tier(CoverageTier t) => all.where((c) => c.tier == t).length;
    // ignore: avoid_print
    print(
      'CG generated: ${all.length} total '
      '(CG-1=${tier(CoverageTier.cg1Smoke)}, '
      'CG-2=${tier(CoverageTier.cg2Pairwise)}, '
      'CG-3=${tier(CoverageTier.cg3Recovery)}); '
      'feasible=${feasible.length}, pruned=${all.length - feasible.length}',
    );

    // Deterministic stride so the sample spans all three tiers, not just the
    // pairwise head.
    final stride = (feasible.length / sampleCap).ceil().clamp(1, feasible.length);
    final sample = <GeneratedCase>[];
    for (var i = 0; i < feasible.length && sample.length < sampleCap; i += stride) {
      sample.add(feasible[i]);
    }

    final records = <EvidenceRecord>[];
    for (final c in sample) {
      records.add(await runCase(locator, c));
    }
    final report = MatrixReport(records);
    // ignore: avoid_print
    print(report.render());

    // Only a real invariant/oracle violation fails the run; Blocked (two-relay /
    // crafted-fixture remainder) and Skipped (infeasible) are non-fatal.
    expect(report.failed, 0, reason: 'no generated case may violate an invariant');
  });
}
