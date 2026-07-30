import 'dart:async';

import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/claim_payment_page_nym_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/get_payment_page_permanent_name_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/get_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/update_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/payment_page/presentation/payment_page_state.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGetPaymentPagePermanentNameUsecase permanentName;
  late _FakePaymentPageFacade facade;
  late _FakeGetGetPaidWalletBehaviorsUsecase walletBehaviors;
  late _FakeUpdateWalletBehaviorUsecase updateWalletBehavior;
  late _FakeClaimPaymentPageNymUsecase claimNym;

  PaymentPageCubit build() {
    final settings = GetPaidSettingsFacade(
      walletBehaviors: walletBehaviors.execute,
      updateWalletBehavior: updateWalletBehavior.execute,
    );
    return PaymentPageCubit(
      find: facade.find,
      save: facade.save,
      archive: facade.archive,
      supportedCurrencies: facade.supportedCurrencies,
      getPermanentName: permanentName,
      claimNym: claimNym,
      getWalletBehavior: GetPaymentPageWalletBehaviorUsecase(
        getPaidSettings: settings,
      ),
      updateWalletBehavior: UpdatePaymentPageWalletBehaviorUsecase(
        getPaidSettings: settings,
      ),
    );
  }

  PaymentPage buildPage({
    bool archived = false,
    String description = 'Support my work',
    String? alias,
  }) => PaymentPage(
    nym: 'alice',
    header: 'Tip me',
    description: description,
    displayCurrency: 'USD',
    enabled: true,
    isArchived: archived,
    alias: alias,
    publicUrl: alias == null
        ? 'https://bullpay.ca/alice'
        : 'https://bullpay.ca/a/$alias',
  );

  setUp(() {
    permanentName = _FakeGetPaymentPagePermanentNameUsecase();
    facade = _FakePaymentPageFacade();
    walletBehaviors = _FakeGetGetPaidWalletBehaviorsUsecase();
    updateWalletBehavior = _FakeUpdateWalletBehaviorUsecase();
    claimNym = _FakeClaimPaymentPageNymUsecase();
    facade.currencies = const [
      DisplayCurrency(code: 'CAD', precision: 2),
      DisplayCurrency(code: 'USD', precision: 2),
    ];
  });

  group('load', () {
    test('no nym -> needsNym', () async {
      permanentName.value = const PaymentPagePermanentName.unclaimed();
      final cubit = build();

      await cubit.load();

      expect(cubit.state.status, PaymentPageStatus.needsNym);
    });
  });

  group('claimNym', () {
    test(
      'claims in-flow, then reloads straight into the create form',
      () async {
        permanentName.value = const PaymentPagePermanentName.unclaimed();
        facade.page = null;
        final cubit = build();
        await cubit.load();
        expect(cubit.state.status, PaymentPageStatus.needsNym);

        cubit.nymDraftChanged('  Alice  ');
        // The nym the server sees is the normalized one the field displayed.
        expect(cubit.state.nymDraft, 'alice');

        permanentName.value = const PaymentPagePermanentName.claimed(
          nym: 'alice',
        );
        await cubit.claimNym();

        expect(claimNym.calls, ['alice']);
        expect(cubit.state.status, PaymentPageStatus.create);
        expect(cubit.state.nym, 'alice');
        expect(cubit.state.claimingNym, isFalse);
        expect(cubit.state.nymDraft, '');
      },
    );

    test('a locally invalid nym never reaches the server', () async {
      permanentName.value = const PaymentPagePermanentName.unclaimed();
      final cubit = build();
      await cubit.load();

      cubit.nymDraftChanged('-alice');
      await cubit.claimNym();

      expect(claimNym.calls, isEmpty);
      expect(cubit.state.status, PaymentPageStatus.needsNym);
      expect(cubit.state.invalidField, PaymentPageField.nym);
      expect(cubit.state.failure?.kind, PaymentPageErrorKind.nymInvalid);
    });

    test('a taken nym flags the claim field and stays on the step', () async {
      permanentName.value = const PaymentPagePermanentName.unclaimed();
      final cubit = build();
      await cubit.load();
      cubit.nymDraftChanged('alice');
      claimNym.error = const PaymentPageException.nymTaken();

      await cubit.claimNym();

      expect(cubit.state.status, PaymentPageStatus.needsNym);
      expect(cubit.state.invalidField, PaymentPageField.nym);
      expect(cubit.state.failure?.kind, PaymentPageErrorKind.nymTaken);
      expect(cubit.state.claimingNym, isFalse);
    });

    test('is inert once a nym exists', () async {
      final cubit = build();
      await cubit.load();
      expect(cubit.state.status, isNot(PaymentPageStatus.needsNym));

      cubit.nymDraftChanged('bob');
      await cubit.claimNym();

      expect(claimNym.calls, isEmpty);
    });
  });

  group('load (continued)', () {
    test('nym but no page -> create with the fallback currency', () async {
      facade.page = null;
      final cubit = build();

      await cubit.load();

      expect(cubit.state.status, PaymentPageStatus.create);
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.displayCurrency, 'CAD');
    });

    test('existing live page -> edit with populated fields', () async {
      facade.page = buildPage();
      final cubit = build();

      await cubit.load();

      expect(cubit.state.status, PaymentPageStatus.edit);
      expect(cubit.state.header, 'Tip me');
      expect(cubit.state.displayCurrency, 'USD');
    });

    test('archived page -> archived', () async {
      facade.page = buildPage(archived: true);
      final cubit = build();

      await cubit.load();

      expect(cubit.state.status, PaymentPageStatus.archived);
    });

    test('nym lookup failure -> loadFailed', () async {
      permanentName.error = const PaymentPageException.network();
      final cubit = build();

      await cubit.load();

      expect(cubit.state.status, PaymentPageStatus.loadFailed);
    });

    test('programmer errors during load propagate', () async {
      permanentName.error = StateError('broken permanent-name adapter');
      final cubit = build();

      await expectLater(cubit.load(), throwsA(isA<StateError>()));
    });

    test('keeps an unavailable wallet read distinct from absence', () async {
      walletBehaviors.error = Exception('settings unavailable');
      final cubit = build();

      await cubit.load();

      expect(cubit.state.walletBehavior, isNull);
      expect(cubit.state.walletBehaviorUnavailable, isTrue);
    });

    test('confirmed wallet absence does not report unavailability', () async {
      final cubit = build();

      await cubit.load();

      expect(cubit.state.walletBehavior, isNull);
      expect(cubit.state.walletBehaviorUnavailable, isFalse);
    });

    test(
      'wallet retry preserves dirty form state and coalesces duplicate taps',
      () async {
        facade.page = buildPage();
        walletBehaviors.error = Exception('settings unavailable');
        final cubit = build();
        await cubit.load();
        cubit.headerChanged('Unsaved heading');

        walletBehaviors
          ..error = null
          ..behaviors = const [
            GetPaidWalletBehavior(
              product: GetPaidWalletProduct.paymentPage,
              walletId: 'wallet-102',
              hideOnHome: false,
              autoSweepEnabled: false,
            ),
          ];
        final gate = Completer<void>();
        walletBehaviors.gate = gate.future;

        final first = cubit.retryWalletBehavior();
        await Future<void>.delayed(Duration.zero);
        await cubit.retryWalletBehavior();

        expect(walletBehaviors.calls, 2); // initial load + one retry
        expect(cubit.state.header, 'Unsaved heading');
        gate.complete();
        await first;

        expect(cubit.state.header, 'Unsaved heading');
        expect(cubit.state.walletBehavior?.walletId, 'wallet-102');
        expect(cubit.state.walletBehaviorUnavailable, isFalse);
      },
    );

    test(
      'server load failure still exposes the local wallet behavior',
      () async {
        permanentName.error = const PaymentPageException.network();
        walletBehaviors.behaviors = const [
          GetPaidWalletBehavior(
            product: GetPaidWalletProduct.paymentPage,
            walletId: 'wallet-102',
            hideOnHome: true,
            autoSweepEnabled: true,
          ),
        ];
        final cubit = build();

        await cubit.load();

        expect(cubit.state.status, PaymentPageStatus.loadFailed);
        expect(cubit.state.walletBehavior?.walletId, 'wallet-102');
      },
    );

    test(
      'currency fetch failure degrades but still reaches the form',
      () async {
        facade.page = null;
        facade.currenciesError = const PaymentPageException.network();
        final cubit = build();

        await cubit.load();

        expect(cubit.state.status, PaymentPageStatus.create);
        expect(cubit.state.currenciesUnavailable, isTrue);
      },
    );

    test(
      'missing exact capability hides alias and availability actions',
      () async {
        permanentName.value = const PaymentPagePermanentName.unsupported();
        facade.page = buildPage();

        final cubit = build();
        await cubit.load();

        expect(cubit.state.status, PaymentPageStatus.unsupported);
        expect(facade.findCallCount, 0);
        expect(cubit.state.permanentAlias, isNull);
      },
    );

    test('reconstructs the permanent alias from server ownership', () async {
      permanentName.value = const PaymentPagePermanentName.claimed(
        nym: 'alice',
        alias: 'shop',
      );
      facade.page = buildPage(alias: 'shop');

      final first = build();
      await first.load();
      expect(first.state.permanentAlias, 'shop');
      await first.close();

      // A fresh cubit has no local alias state; the next owner lookup restores
      // it and the server page must agree.
      final afterAppStateWipe = build();
      await afterAppStateWipe.load();
      expect(afterAppStateWipe.state.permanentAlias, 'shop');
      expect(afterAppStateWipe.state.aliasDraft, isEmpty);
    });

    test(
      'fails closed when the page alias disagrees with owner state',
      () async {
        permanentName.value = const PaymentPagePermanentName.claimed(
          nym: 'alice',
          alias: 'shop',
        );
        facade.page = buildPage(alias: 'other');

        final cubit = build();
        await cubit.load();

        expect(cubit.state.status, PaymentPageStatus.loadFailed);
        expect(
          cubit.state.failure?.kind,
          PaymentPageErrorKind.invalidServerResponse,
        );
      },
    );
  });

  test('an unclaimed nym exposes no product-owned name mutation', () async {
    permanentName.value = const PaymentPagePermanentName.unclaimed();
    final cubit = build();
    await cubit.load();

    expect(cubit.state.status, PaymentPageStatus.needsNym);
    expect(facade.saveCallCount, 0);
    expect(facade.archiveCallCount, 0);
  });

  group('save', () {
    test('success moves to edit with the returned page', () async {
      facade.page = null;
      final cubit = build();
      await cubit.load();

      cubit
        ..headerChanged('Tip me')
        ..descriptionChanged('Support my work');
      facade.savedPage = buildPage();
      await cubit.save();

      expect(facade.saveCallCount, 1);
      expect(cubit.state.status, PaymentPageStatus.edit);
      expect(cubit.state.submitting, isFalse);
    });

    test(
      'does not convert a post-save programmer error into UI failure',
      () async {
        facade.page = null;
        final cubit = build();
        await cubit.load();
        cubit
          ..headerChanged('Tip me')
          ..descriptionChanged('Support my work');
        facade.savedPage = buildPage();
        walletBehaviors.error = StateError('broken wallet behavior adapter');

        await expectLater(cubit.save(), throwsA(isA<StateError>()));
        expect(facade.saveCallCount, 1);
      },
    );

    test('surfaces an uncertain submission failure', () async {
      facade.page = null;
      final cubit = build();
      await cubit.load();
      cubit
        ..headerChanged('Tip me')
        ..descriptionChanged('Support my work');
      facade.saveError = PaymentPageSaveException.submission(
        cause: const PaymentPageException.timeout(),
      );

      await cubit.save();

      expect(cubit.state.failure, isNotNull);
      expect(cubit.state.submissionUncertain, isTrue);
      expect(cubit.state.submitting, isFalse);
    });

    test('invalid input is refused without a wire call', () async {
      facade.page = null;
      final cubit = build();
      await cubit.load();
      // header left empty -> invalid
      cubit.descriptionChanged('Support my work');

      await cubit.save();

      expect(facade.saveCallCount, 0);
      expect(cubit.state.failure?.kind, PaymentPageErrorKind.invalidInput);
    });

    test(
      'legacy archived content can be corrected before reactivation',
      () async {
        facade.page = buildPage(archived: true, description: 'a' * 121);
        final cubit = build();
        await cubit.load();

        expect(cubit.state.status, PaymentPageStatus.archived);
        expect(cubit.state.canSubmit, isFalse);
        await cubit.save();
        expect(facade.saveCallCount, 0);

        cubit.descriptionChanged('A new short description');
        facade.savedPage = buildPage(description: 'A new short description');
        await cubit.save();

        expect(facade.saveCallCount, 1);
        expect(cubit.state.status, PaymentPageStatus.edit);
      },
    );

    test('a double-tap yields exactly one wire call', () async {
      facade.page = null;
      final cubit = build();
      await cubit.load();
      cubit
        ..headerChanged('Tip me')
        ..descriptionChanged('Support my work');

      final gate = Completer<void>();
      facade.saveGate = gate.future;
      facade.savedPage = buildPage();

      final first = cubit.save();
      final second = cubit.save(); // inert: a save is already in flight
      gate.complete();
      await Future.wait([first, second]);

      expect(facade.saveCallCount, 1);
    });

    test(
      'normalizes and submits the optional first shared alias claim',
      () async {
        facade.page = null;
        final cubit = build();
        await cubit.load();
        cubit
          ..aliasDraftChanged('  Shop  ')
          ..headerChanged('Tip me')
          ..descriptionChanged('Support my work');
        facade.savedPage = buildPage(alias: 'shop');

        await cubit.save();

        expect(facade.lastCommand?.aliasClaim, 'shop');
        expect(cubit.state.permanentAlias, 'shop');
        expect(cubit.state.aliasDraft, isEmpty);
      },
    );

    test('structured owned-alias conflict adopts the server alias', () async {
      facade.page = null;
      final cubit = build();
      await cubit.load();
      cubit
        ..aliasDraftChanged('other')
        ..headerChanged('Tip me')
        ..descriptionChanged('Support my work');
      facade.saveError = PaymentPageSaveException.submission(
        cause: const PaymentPageException.aliasAlreadyAssigned(
          ownedAlias: 'shop',
        ),
      );

      await cubit.save();

      expect(cubit.state.permanentAlias, 'shop');
      expect(cubit.state.aliasDraft, isEmpty);
      expect(cubit.state.submissionUncertain, isFalse);
    });

    test('alias namespace conflict points at only the alias field', () async {
      facade.page = null;
      final cubit = build();
      await cubit.load();
      cubit
        ..aliasDraftChanged('taken')
        ..headerChanged('Tip me')
        ..descriptionChanged('Support my work');
      facade.saveError = PaymentPageSaveException.submission(
        cause: const PaymentPageException.aliasTaken(),
      );

      await cubit.save();

      expect(cubit.state.invalidField, PaymentPageField.alias);
      expect(cubit.state.submissionUncertain, isFalse);
    });
  });

  test(
    'availability switch archives only Donation Page and preserves alias',
    () async {
      permanentName.value = const PaymentPagePermanentName.claimed(
        nym: 'alice',
        alias: 'shop',
      );
      facade.page = buildPage(alias: 'shop');
      final cubit = build();
      await cubit.load();

      facade.page = buildPage(archived: true, alias: 'shop');
      await cubit.setOnline(false);

      expect(facade.archiveCallCount, 1);
      expect(facade.saveCallCount, 0);
      expect(cubit.state.status, PaymentPageStatus.archived);
      expect(cubit.state.permanentAlias, 'shop');
    },
  );
}

/// Stands in for the wallet-behavior read the facade callback is wired to.
class _FakeGetGetPaidWalletBehaviorsUsecase {
  List<GetPaidWalletBehavior> behaviors = const [];
  Object? error;
  Future<void>? gate;
  int calls = 0;

  Future<List<GetPaidWalletBehavior>> execute({
    GetPaidWalletProduct? only,
  }) async {
    calls += 1;
    final currentGate = gate;
    if (currentGate != null) await currentGate;
    final currentError = error;
    if (currentError != null) throw currentError;
    if (only == null) return behaviors;
    return behaviors.where((b) => b.product == only).toList();
  }
}

class _FakeUpdateWalletBehaviorUsecase implements UpdateWalletBehaviorUsecase {
  @override
  Future<void> execute({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  }) async {}
}

class _FakeGetPaymentPagePermanentNameUsecase
    implements GetPaymentPagePermanentNameUsecase {
  PaymentPagePermanentName value = const PaymentPagePermanentName.claimed(
    nym: 'alice',
  );
  Object? error;

  @override
  Future<PaymentPagePermanentName> execute() async {
    final currentError = error;
    if (currentError != null) throw currentError;
    return value;
  }
}

class _FakePaymentPageFacade implements PaymentPageFacade {
  PaymentPage? page;
  PaymentPage? savedPage;
  Object? saveError;
  List<DisplayCurrency> currencies = const [];
  Object? currenciesError;
  Future<void>? saveGate;
  int saveCallCount = 0;
  int findCallCount = 0;
  int archiveCallCount = 0;
  SavePaymentPageCommand? lastCommand;

  @override
  Future<PaymentPage?> find({required String nym}) async {
    findCallCount += 1;
    return page;
  }

  @override
  Future<PaymentPage> save(SavePaymentPageCommand command) async {
    saveCallCount += 1;
    lastCommand = command;
    final gate = saveGate;
    if (gate != null) await gate;
    final error = saveError;
    if (error != null) throw error;
    return savedPage ?? page!;
  }

  @override
  Future<PaymentPage?> archive() async {
    archiveCallCount += 1;
    return page;
  }

  @override
  Future<List<DisplayCurrency>> supportedCurrencies() async {
    final error = currenciesError;
    if (error != null) throw error;
    return currencies;
  }

  @override
  Future<PaymentPageHealOutcome> ensurePageLive() async =>
      throw UnimplementedError();

  @override
  Future<PreparedPaymentPageWallet> prepareWallet() async =>
      throw UnimplementedError();
}

class _FakeClaimPaymentPageNymUsecase implements ClaimPaymentPageNymUsecase {
  final List<String> calls = [];
  Object? error;

  @override
  Future<String> execute({required String nym}) async {
    calls.add(nym);
    final failure = error;
    if (failure != null) throw failure;
    return nym;
  }
}
