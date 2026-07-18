import 'dart:convert';
import 'dart:io';

const fundedInvoiceLaneName = 'S-REAL-PROD-INVOICE-FUNDED';

enum FundedInvoiceRail {
  bitcoin,
  lightning,
  liquid;

  static FundedInvoiceRail parse(String? value) => switch (value?.trim()) {
    'bitcoin' => FundedInvoiceRail.bitcoin,
    'lightning' => FundedInvoiceRail.lightning,
    'liquid' => FundedInvoiceRail.liquid,
    _ => throw StateError(
      'GETPAID_INVOICE_RAIL must be bitcoin, lightning, or liquid',
    ),
  };
}

class FundedInvoiceFixtures {
  final String runId;
  final FundedInvoiceRail rail;
  final Directory handshakeDir;
  final Directory seedCaptureDir;
  final int amountSat;
  final int maxFeeSat;
  final double liquidFeeRateSatPerVb;
  final Duration paymentTimeout;
  final Duration returnTimeout;
  final Duration pollInterval;

  const FundedInvoiceFixtures._({
    required this.runId,
    required this.rail,
    required this.handshakeDir,
    required this.seedCaptureDir,
    required this.amountSat,
    required this.maxFeeSat,
    required this.liquidFeeRateSatPerVb,
    required this.paymentTimeout,
    required this.returnTimeout,
    required this.pollInterval,
  });

  factory FundedInvoiceFixtures.fromEnvironment() {
    final env = Platform.environment;
    if (env['GETPAID_E2E_LANE'] != fundedInvoiceLaneName) {
      throw StateError('GETPAID_E2E_LANE must be $fundedInvoiceLaneName');
    }
    final rail = FundedInvoiceRail.parse(env['GETPAID_INVOICE_RAIL']);
    final handshake = _required(env, 'GETPAID_FUNDED_HANDSHAKE_DIR');
    final handshakeDir = Directory(handshake);
    if (!handshakeDir.existsSync()) {
      throw StateError('handshake directory does not exist: $handshake');
    }
    final seedPath =
        env['GETPAID_FUNDED_SEED_CAPTURE_DIR']?.trim().isNotEmpty == true
        ? env['GETPAID_FUNDED_SEED_CAPTURE_DIR']!.trim()
        : '/home/francis/bull-bitcoin-workspace/.secrets-carry/getpaid-qa-seeds';
    final seedCaptureDir = Directory(seedPath);
    seedCaptureDir.createSync(recursive: true);

    final defaultAmount = rail == FundedInvoiceRail.bitcoin ? 50000 : 2000;
    return FundedInvoiceFixtures._(
      runId: _required(env, 'GETPAID_FUNDED_RUN_ID'),
      rail: rail,
      handshakeDir: handshakeDir,
      seedCaptureDir: seedCaptureDir,
      amountSat: _positiveInt(
        env['GETPAID_FUNDED_AMOUNT_SAT'],
        'GETPAID_FUNDED_AMOUNT_SAT',
        defaultAmount,
      ),
      maxFeeSat: _positiveInt(
        env['GETPAID_FUNDED_MAX_FEE_SAT'],
        'GETPAID_FUNDED_MAX_FEE_SAT',
        rail == FundedInvoiceRail.bitcoin ? 20000 : 10000,
      ),
      liquidFeeRateSatPerVb: _positiveDouble(
        env['GETPAID_FUNDED_FEE_RATE'],
        'GETPAID_FUNDED_FEE_RATE',
        0.1,
      ),
      paymentTimeout: Duration(
        seconds: _positiveInt(
          env['GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC'],
          'GETPAID_FUNDED_PAYMENT_TIMEOUT_SEC',
          rail == FundedInvoiceRail.bitcoin ? 3600 : 900,
        ),
      ),
      returnTimeout: Duration(
        seconds: _positiveInt(
          env['GETPAID_FUNDED_RETURN_TIMEOUT_SEC'],
          'GETPAID_FUNDED_RETURN_TIMEOUT_SEC',
          rail == FundedInvoiceRail.bitcoin ? 3600 : 900,
        ),
      ),
      pollInterval: Duration(
        seconds: _positiveInt(
          env['GETPAID_FUNDED_POLL_INTERVAL_SEC'],
          'GETPAID_FUNDED_POLL_INTERVAL_SEC',
          15,
        ),
      ),
    );
  }

  File get requestFile => _file('invoice_request.json');
  File get responseFile => _file('invoice_response.json');
  File get resultFile => _file('invoice_result.json');
  File get seedCaptureFile => File(
    '${seedCaptureDir.path}${Platform.pathSeparator}$runId-invoice.seed.json',
  );

  File _file(String name) =>
      File('${handshakeDir.path}${Platform.pathSeparator}$name');

  Future<void> writeJsonAtomic(File file, Map<String, Object?> value) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  Future<String> writeSeedCapture(Map<String, Object?> value) async {
    await seedCaptureFile.create(recursive: true);
    await _chmod(seedCaptureFile.path, '600');
    await seedCaptureFile.writeAsString(jsonEncode(value), flush: true);
    await _chmod(seedCaptureFile.path, '600');
    return seedCaptureFile.path;
  }

  Future<Map<String, Object?>?> readJson(File file) async {
    if (!file.existsSync()) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map).cast();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _chmod(String path, String mode) async {
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw StateError('chmod $mode $path failed: ${result.stderr}');
    }
  }

  static String _required(Map<String, String> env, String name) {
    final value = env[name]?.trim();
    if (value == null || value.isEmpty) throw StateError('$name is required');
    return value;
  }

  static int _positiveInt(String? raw, String name, int fallback) {
    final value = raw == null || raw.trim().isEmpty
        ? fallback
        : int.tryParse(raw.trim());
    if (value == null || value <= 0) {
      throw StateError('$name must be a positive integer');
    }
    return value;
  }

  static double _positiveDouble(String? raw, String name, double fallback) {
    final value = raw == null || raw.trim().isEmpty
        ? fallback
        : double.tryParse(raw.trim());
    if (value == null || value <= 0) {
      throw StateError('$name must be a positive number');
    }
    return value;
  }
}
