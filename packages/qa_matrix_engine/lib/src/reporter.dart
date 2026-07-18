import 'invariants.dart';
import 'outcome.dart';

/// Aggregates [EvidenceRecord]s into a diagnosis-by-cause-class run report
/// (GETPAID-APP-E2E-FAILURE-MATRIX §12). Only [CaseOutcome.passed] certifies;
/// every other outcome is counted separately so a red run means a real
/// regression, not a deploy-gated or unbuilt case.
class MatrixReport {
  MatrixReport(this.records);

  final List<EvidenceRecord> records;

  int get total => records.length;

  int countOf(CaseOutcome outcome) =>
      records.where((r) => r.outcome == outcome).length;

  int get passed => countOf(CaseOutcome.passed);
  int get failed => countOf(CaseOutcome.failed);

  /// The suite certifies only if every case passed (no `Fail`). Skips/Blocked/
  /// MissingFixture are non-fatal and do not certify a feature on their own.
  bool get certified => failed == 0 && records.isNotEmpty;

  /// Fail counts bucketed by defect class (§12 diagnosis-by-cause-class).
  Map<DefectClass, int> get failuresByDefectClass {
    final byClass = <DefectClass, int>{};
    for (final r in records) {
      if (r.outcome != CaseOutcome.failed) continue;
      final dc = r.defectClass ?? DefectClass.harnessBug;
      byClass.update(dc, (n) => n + 1, ifAbsent: () => 1);
    }
    return byClass;
  }

  /// Every distinct invariant that was violated by at least one case.
  Set<String> get violatedInvariants {
    final ids = <String>{};
    for (final r in records) {
      for (final v in r.violations) {
        ids.add(v.id);
      }
    }
    return ids;
  }

  /// A compact text report suitable for a CI log / stdout.
  String render() {
    final b = StringBuffer()
      ..writeln('QA matrix run — $total case(s)')
      ..writeln('  passed:                ${countOf(CaseOutcome.passed)}')
      ..writeln('  failed:                ${countOf(CaseOutcome.failed)}')
      ..writeln('  skipped:               ${countOf(CaseOutcome.skipped)}')
      ..writeln('  blocked:               ${countOf(CaseOutcome.blocked)}')
      ..writeln('  missingFixture:        ${countOf(CaseOutcome.missingFixture)}')
      ..writeln('  unsupportedEnv:        '
          '${countOf(CaseOutcome.unsupportedEnvironment)}')
      ..writeln('  inconclusive:          ${countOf(CaseOutcome.inconclusive)}')
      ..writeln('  manualOnly:            ${countOf(CaseOutcome.manualOnly)}');

    final byClass = failuresByDefectClass;
    if (byClass.isNotEmpty) {
      b.writeln('failures by defect class:');
      final entries = byClass.entries.toList()
        ..sort((a, z) => z.value.compareTo(a.value));
      for (final e in entries) {
        b.writeln('  ${e.key.label}: ${e.value}');
      }
    }

    for (final r in records) {
      if (r.outcome == CaseOutcome.failed) {
        final vios = r.violations.map((v) => v.id).join(',');
        b.writeln('FAIL ${r.scenarioId} [${r.feature}/${r.scenarioClass}] '
            '${r.defectClass?.label ?? '-'} violated=[$vios] '
            '${r.message ?? ''}');
      }
    }

    b.writeln(certified ? 'RESULT: CERTIFIED' : 'RESULT: NOT CERTIFIED');
    return b.toString();
  }

  /// A "next:" hint per defect class (§12 actionable diagnosis).
  static String nextHintFor(DefectClass dc) {
    switch (dc) {
      case DefectClass.recoveryLostBackup:
        return 'a real backup was lost — inspect the fetch/ordering path';
      case DefectClass.falseSuccess:
        return 'success was reported without proof — tighten the oracle path';
      case DefectClass.authenticityBroken:
        return 'a forged/tampered event was accepted — check sig-before-decrypt';
      case DefectClass.postureRegression:
        return 'a restored wallet lost hidden/autosweep posture';
      case DefectClass.doubleSpendOrStuckPay:
        return 'a direct-pay double-paid or got stuck — check the swap fallback';
      case DefectClass.corruptAfterInterrupt:
        return 'an interrupt left corrupt state — check the _operationId guard';
      case DefectClass.cleartextLeak:
        return 'identifying cleartext hit the wire — check the opacity codec';
      case DefectClass.harnessBug:
        return 'likely a harness/oracle bug, not a product regression';
      case DefectClass.externalDependency:
        return 'an external dependency failed — re-run or mark flaky';
      case DefectClass.deployGated:
        return 'gated on a deploy/coin — Blocked, not Fail';
    }
  }
}

/// Convenience: whether a set of records references every invariant at least
/// once (a coverage sanity check for the invariant library).
bool touchesEveryInvariant(List<EvidenceRecord> records) {
  final seen = <String>{};
  for (final r in records) {
    for (final ir in r.invariantResults) {
      if (ir.applicable) seen.add(ir.id);
    }
  }
  return InvariantLibrary.all.every((i) => seen.contains(i.id));
}
