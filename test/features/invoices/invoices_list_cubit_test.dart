import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/presentation/invoices_list_cubit.dart';
import 'package:bb_mobile/features/invoices/presentation/invoices_list_state.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFacade extends Mock implements InvoicesFacade {}

Invoice _invoice(String id, InvoiceStatus status) => Invoice(
  id: InvoiceId(id),
  status: status,
  amountSat: 1000,
  remainingAmountSat: 1000,
  acceptBtc: false,
  acceptLn: false,
  acceptLiquid: true,
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2030),
);

void main() {
  setUpAll(() => registerFallbackValue(const ListInvoicesCommand()));

  late _MockFacade facade;

  setUp(() => facade = _MockFacade());

  test('load fetches with NO server status filter and marks loaded', () async {
    when(() => facade.list(any())).thenAnswer(
      (_) async => Ok(
        ListInvoicesResult(
          invoices: [_invoice('a', InvoiceStatus.unpaid)],
          page: 1,
          pageSize: 100,
          hasMore: false,
        ),
      ),
    );

    final cubit = InvoicesListCubit(list: facade.list);
    await cubit.load();

    expect(cubit.state.status, InvoicesListStatus.loaded);
    expect(cubit.state.invoices, hasLength(1));
    final sent =
        verify(() => facade.list(captureAny())).captured.single
            as ListInvoicesCommand;
    expect(sent.status, isNull); // no server-side filter
    await cubit.close();
  });

  test(
    'the status filter is applied CLIENT-SIDE over the loaded set',
    () async {
      when(() => facade.list(any())).thenAnswer(
        (_) async => Ok(
          ListInvoicesResult(
            invoices: [
              _invoice('a', InvoiceStatus.unpaid),
              _invoice('b', InvoiceStatus.paid),
              _invoice('c', InvoiceStatus.unpaid),
            ],
            page: 1,
            pageSize: 100,
            hasMore: false,
          ),
        ),
      );

      final cubit = InvoicesListCubit(list: facade.list);
      await cubit.load();

      cubit.setFilter(InvoiceStatus.paid);
      expect(cubit.state.visibleInvoices.map((i) => i.id.value), ['b']);
      // No extra wire call for a client-side filter.
      verify(() => facade.list(any())).called(1);

      cubit.setFilter(null);
      expect(cubit.state.visibleInvoices, hasLength(3));
      await cubit.close();
    },
  );

  test('an empty result yields the honest empty state (no error)', () async {
    when(() => facade.list(any())).thenAnswer(
      (_) async => const Ok(
        ListInvoicesResult(
          invoices: [],
          page: 1,
          pageSize: 100,
          hasMore: false,
        ),
      ),
    );

    final cubit = InvoicesListCubit(list: facade.list);
    await cubit.load();

    expect(cubit.state.status, InvoicesListStatus.loaded);
    expect(cubit.state.isEmpty, isTrue);
    await cubit.close();
  });

  test('loadMore appends and de-duplicates the next invoice page', () async {
    when(() => facade.list(any())).thenAnswer((invocation) async {
      final command =
          invocation.positionalArguments.single as ListInvoicesCommand;
      return Ok(
        ListInvoicesResult(
          invoices: command.page == 1
              ? [
                  _invoice('a', InvoiceStatus.unpaid),
                  _invoice('b', InvoiceStatus.paid),
                ]
              : [
                  _invoice('b', InvoiceStatus.paid),
                  _invoice('c', InvoiceStatus.expired),
                ],
          page: command.page,
          pageSize: 100,
          hasMore: command.page == 1,
        ),
      );
    });
    final cubit = InvoicesListCubit(list: facade.list);
    await cubit.load();

    await cubit.loadMore();

    expect(cubit.state.invoices.map((invoice) => invoice.id.value), [
      'a',
      'b',
      'c',
    ]);
    expect(cubit.state.page, 2);
    expect(cubit.state.hasMore, isFalse);
    final commands = verify(
      () => facade.list(captureAny()),
    ).captured.cast<ListInvoicesCommand>();
    expect(commands.map((command) => command.page), [1, 2]);
    await cubit.close();
  });

  test('loadMore failure keeps the loaded invoices and offers retry', () async {
    var calls = 0;
    when(() => facade.list(any())).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) {
        return Ok(
          ListInvoicesResult(
            invoices: [_invoice('a', InvoiceStatus.unpaid)],
            page: 1,
            pageSize: 100,
            hasMore: true,
          ),
        );
      }
      return const Err<ListInvoicesResult, InvoicesFailure>(
        InvoicesFailure.network(),
      );
    });
    final cubit = InvoicesListCubit(list: facade.list);
    await cubit.load();

    await cubit.loadMore();

    expect(cubit.state.status, InvoicesListStatus.loaded);
    expect(cubit.state.invoices.single.id.value, 'a');
    expect(cubit.state.loadMoreFailed, isTrue);
    expect(cubit.state.hasMore, isTrue);
    await cubit.close();
  });

  test('a refresh invalidates an older page request', () async {
    final pageTwo = Completer<Result<ListInvoicesResult, InvoicesFailure>>();
    var pageOneCalls = 0;
    when(() => facade.list(any())).thenAnswer((invocation) {
      final command =
          invocation.positionalArguments.single as ListInvoicesCommand;
      if (command.page == 2) return pageTwo.future;
      pageOneCalls += 1;
      return Future.value(
        Ok(
          ListInvoicesResult(
            invoices: [_invoice('fresh-$pageOneCalls', InvoiceStatus.unpaid)],
            page: 1,
            pageSize: 100,
            hasMore: true,
          ),
        ),
      );
    });
    final cubit = InvoicesListCubit(list: facade.list);
    await cubit.load();

    final olderPage = cubit.loadMore();
    await cubit.refresh();
    pageTwo.complete(
      Ok(
        ListInvoicesResult(
          invoices: [_invoice('stale-page', InvoiceStatus.paid)],
          page: 2,
          pageSize: 100,
          hasMore: false,
        ),
      ),
    );
    await olderPage;

    expect(cubit.state.invoices.single.id.value, 'fresh-2');
    expect(cubit.state.page, 1);
    await cubit.close();
  });

  test('an older refresh cannot replace a newer refresh', () async {
    final older = Completer<Result<ListInvoicesResult, InvoicesFailure>>();
    final newer = Completer<Result<ListInvoicesResult, InvoicesFailure>>();
    var calls = 0;
    when(() => facade.list(any())).thenAnswer((_) {
      calls += 1;
      return calls == 1 ? older.future : newer.future;
    });
    final cubit = InvoicesListCubit(list: facade.list);

    final first = cubit.refresh();
    final second = cubit.refresh();
    newer.complete(
      Ok(
        ListInvoicesResult(
          invoices: [_invoice('newer', InvoiceStatus.paid)],
          page: 1,
          pageSize: 100,
          hasMore: false,
        ),
      ),
    );
    await second;
    older.complete(
      Ok(
        ListInvoicesResult(
          invoices: [_invoice('older', InvoiceStatus.unpaid)],
          page: 1,
          pageSize: 100,
          hasMore: false,
        ),
      ),
    );
    await first;

    expect(cubit.state.invoices.single.id.value, 'newer');
    await cubit.close();
  });

  test(
    'a facade error flips to the error state with the typed failure',
    () async {
      when(
        () => facade.list(any()),
      ).thenAnswer((_) async => const Err(InvoicesFailure.network()));

      final cubit = InvoicesListCubit(list: facade.list);
      await cubit.load();

      expect(cubit.state.status, InvoicesListStatus.error);
      expect(cubit.state.failure?.kind, InvoicesFailureKind.network);
      await cubit.close();
    },
  );
}
