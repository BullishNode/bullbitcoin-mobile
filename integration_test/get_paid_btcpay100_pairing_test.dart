import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_failure.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/funded_btcpay100_fixtures.dart';
import 'support/get_paid_fixtures.dart';
import 'support/test_locator_overrides.dart';
import 'support/wipe_app_state.dart';

// SPEC-BTCPAY100-PAIRING — the DETERMINISTIC, no-pay prerequisites that gate the
// funded BTCPay-100 pairing (get_paid_btcpay100_funded_test.dart). They move NO
// funds and use NO real credential: a bad/fake/malformed pairing URL is rejected
// by the parser with the right typed BtcpayFailure before any network work; a
// well-formed-but-server-rejected / interrupted submission is driven with a
// stubbed SamRock port (no server, no funds); and the redaction proof shows a
// sample URL-shaped secret never survives into an emitted CHECKPOINT line.
//
// AUTHORED-BUT-CI-ONLY: excluded from the aggregated L1 suite
// (tools/gen_all_test.dart skip set), same rationale as the other Get Paid
// app-process lifecycle specs (live startup timers/blocs make a single-process
// aggregate run non-deterministic). Run via the explicit lane.
//
// A syntactically well-formed, entirely SYNTHETIC pairing URL (never the real
// credential) used only to reach the submission stage under a stubbed port.
const _sampleWellFormedUrl =
    'https://btcpay.example.com/plugins/STORE-SAMPLE/samrock/protocol'
    '?otp=sample-otp-value&setup=all';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  group('BTCPay-100 pairing — parser rejects bad URLs with typed failures',
      () {
    // Each malformed input is rejected by SamRockPairingRequestParser BEFORE any
    // wallet or network work, so these need no fakes and have no side effects.
    final invalidInputs = <String, String>{
      'not a URI at all': 'not a url',
      'relative path': '/plugins/STORE/samrock/protocol?otp=x&setup=all',
      'non-https scheme':
          'http://btcpay.example.com/plugins/STORE/samrock/protocol?otp=x&setup=all',
      'wrong protocol path':
          'https://btcpay.example.com/plugins/STORE/samrock/other?otp=x&setup=all',
      'missing store id':
          'https://btcpay.example.com/samrock/protocol?otp=x&setup=all',
      'missing otp':
          'https://btcpay.example.com/plugins/STORE/samrock/protocol?setup=all',
      'missing setup':
          'https://btcpay.example.com/plugins/STORE/samrock/protocol?otp=x',
      'unsupported setup capability':
          'https://btcpay.example.com/plugins/STORE/samrock/protocol?otp=x&setup=nope',
    };

    invalidInputs.forEach((name, url) {
      test('rejects $name as InvalidBtcpayPairingRequestFailure', () async {
        final result = await locator<CompleteBtcpaySamRockPairingUsecase>()
            .execute(pairingUrl: url);
        expect(result, isA<Err<dynamic, BtcpayFailure>>());
        final failure = (result as Err).failure;
        expect(failure, isA<InvalidBtcpayPairingRequestFailure>(),
            reason: 'a malformed pairing URL must fail closed at the parser, '
                'before any wallet or network work');
      });
    });
  });

  group('BTCPay-100 pairing — submission failures are handled fail-closed', () {
    late Environment environment;

    Future<void> restoreAndConsent() async {
      final bullnym = FakeBullnymClient();
      await wipeAppState(locator);
      await overrideBoundariesForTest(locator, bullnym: bullnym);
      await overrideClockForTest(locator);
      await locator<CreateDefaultWalletsUsecase>().execute(
        mnemonicWords: getPaidFixtureMnemonicWords,
      );
      await locator<GetPaidSettingsFacade>().setAutomatedBackupEnabled(true);
      environment = (await locator<GetSettingsUsecase>().execute()).environment;
    }

    // Re-register the SamRock port with a stub BEFORE resolving the pairing
    // usecase (a registerFactory that captures the port at construction), so the
    // real network datasource is never touched.
    Future<void> stubPort(Result<void, BtcpayFailure> outcome) async {
      await locator.unregister<SamRockPairingServicePort>();
      locator.registerLazySingleton<SamRockPairingServicePort>(
        () => _StubSamRockPort(outcome),
      );
    }

    Future<Wallet?> btcpayBitcoinWallet() async {
      final wallets = await locator<WalletRepository>().getWallets(
        environment: environment,
        onlyBitcoin: true,
      );
      for (final wallet in wallets) {
        if (wallet.label == 'BTCPay Bitcoin' && !wallet.isDefault) return wallet;
      }
      return null;
    }

    test('an expired/invalid OTP (explicit server rejection) returns '
        'BtcpayPairingRejectedFailure and retains the prepared wallet 100',
        () async {
      await restoreAndConsent();
      await stubPort(
        const Err(BtcpayPairingRejectedFailure('stub: expired OTP rejected')),
      );

      final result = await locator<CompleteBtcpaySamRockPairingUsecase>()
          .execute(pairingUrl: _sampleWellFormedUrl);

      expect(result, isA<Err<dynamic, BtcpayFailure>>());
      expect((result as Err).failure, isA<BtcpayPairingRejectedFailure>());
      // The pairing contract keeps materialized wallets on rejection so a later
      // attempt reuses them without re-derivation.
      expect(await btcpayBitcoinWallet(), isNotNull,
          reason: 'prepared BTCPay Bitcoin wallet 100 must be retained after '
              'an explicit rejection');
    });

    test('an interrupted/timed-out submission returns '
        'BtcpayPairingUncertainFailure and retains the prepared wallet 100',
        () async {
      await restoreAndConsent();
      await stubPort(
        const Err(BtcpayPairingUncertainFailure('stub: transport interrupted')),
      );

      final result = await locator<CompleteBtcpaySamRockPairingUsecase>()
          .execute(pairingUrl: _sampleWellFormedUrl);

      expect(result, isA<Err<dynamic, BtcpayFailure>>());
      expect((result as Err).failure, isA<BtcpayPairingUncertainFailure>(),
          reason: 'a transport interruption cannot prove the server did not '
              'apply the descriptors, so pairing is uncertain, not rejected');
      expect(await btcpayBitcoinWallet(), isNotNull,
          reason: 'prepared BTCPay Bitcoin wallet 100 must be retained after '
              'an uncertain submission');
    });
  });

  group('BTCPay-100 pairing — credential redaction proof', () {
    // A SAMPLE URL-shaped secret. It is NEVER the real credential; the real
    // pairing URL only ever enters the funded spec at run time from
    // GETPAID_BTCPAY_PAIRING_URL. This proves the emitter scrubs such a value.
    const sampleSecret =
        'https://btcpay.merchant.example/plugins/REALSTORE/samrock/protocol'
        '?otp=SUPER-SECRET-OTP-9f8e7d&token=merchant-bearer-abc123';
    const otp = 'SUPER-SECRET-OTP-9f8e7d';
    const token = 'merchant-bearer-abc123';

    test('redactBtcpaySecrets scrubs the URL, its OTP, and the token '
        '(with the secret supplied explicitly)', () {
      final scrubbed = redactBtcpaySecrets(
        'pairing with $sampleSecret failed',
        secrets: const [sampleSecret],
      );
      expect(scrubbed, isNot(contains(sampleSecret)));
      expect(scrubbed, isNot(contains(otp)));
      expect(scrubbed, isNot(contains(token)));
      expect(scrubbed, contains('[REDACTED]'));
    });

    test('redactBtcpaySecrets scrubs a SamRock/OTP URL even without knowing the '
        'secret in advance (defence in depth)', () {
      final scrubbed = redactBtcpaySecrets('leaked: $sampleSecret end');
      expect(scrubbed, isNot(contains(sampleSecret)));
      expect(scrubbed, isNot(contains(otp)));
      expect(scrubbed, isNot(contains('/samrock/protocol')));
    });

    test('a CHECKPOINT line never emits a pairing secret even if a value '
        'accidentally embeds one', () {
      final line = btcpayCheckpointLine(
        'leak_probe',
        data: {'accidental': sampleSecret},
        redactor: (s) => redactBtcpaySecrets(s, secrets: const [sampleSecret]),
      );
      expect(line, startsWith('CHECKPOINT '));
      expect(line, isNot(contains(sampleSecret)));
      expect(line, isNot(contains(otp)));
      expect(line, isNot(contains(token)));
      expect(line, contains('[REDACTED]'));
    });
  });
}

/// Stubbed SamRock port for the deterministic submission-failure specs. It never
/// touches the network; it replays a scripted [Result] so the real pairing
/// usecase's post-submission handling (rejection vs uncertain, wallet
/// retention) is exercised without a server or any funds.
class _StubSamRockPort implements SamRockPairingServicePort {
  final Result<void, BtcpayFailure> _outcome;

  const _StubSamRockPort(this._outcome);

  @override
  Future<Result<void, BtcpayFailure>> submitSetup({
    required SamRockPairingRequest request,
    required Map<String, Object?> payload,
  }) async {
    return _outcome;
  }
}
