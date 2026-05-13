import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_cubit.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/screens/invoice_create_screen.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/screens/invoice_detail_screen.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/screens/invoices_list_screen.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

enum InvoicesRoute {
  list('invoices'),
  create('invoices/create'),
  detail('invoices/:invoiceId');

  final String path;

  const InvoicesRoute(this.path);
}

class InvoicesRouter {
  static final routes = [
    GoRoute(
      name: InvoicesRoute.list.name,
      path: InvoicesRoute.list.path,
      builder: (context, state) => BlocProvider(
        create: (_) => locator<InvoicesListCubit>(),
        child: const InvoicesListScreen(),
      ),
    ),
    GoRoute(
      name: InvoicesRoute.create.name,
      path: InvoicesRoute.create.path,
      builder: (context, state) => BlocProvider(
        create: (_) => locator<InvoiceCreateCubit>(),
        child: InvoiceCreateScreen(
          paymentPageNym: state.uri.queryParameters['nym'],
        ),
      ),
    ),
    GoRoute(
      name: InvoicesRoute.detail.name,
      path: InvoicesRoute.detail.path,
      builder: (context, state) {
        final id = InvoiceId(state.pathParameters['invoiceId'] ?? '');
        return BlocProvider(
          create: (_) => locator<InvoiceDetailCubit>(),
          child: InvoiceDetailScreen(
            invoiceId: id,
            nymOwner: state.uri.queryParameters['nymOwner'],
            shareUrl: state.uri.queryParameters['shareUrl'],
          ),
        );
      },
    ),
  ];
}
