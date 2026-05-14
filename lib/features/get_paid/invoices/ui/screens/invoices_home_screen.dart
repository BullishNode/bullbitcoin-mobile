import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InvoicesHomeScreen extends StatelessWidget {
  const InvoicesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GetPaidSlotCard(
              icon: Icons.add_circle_outline,
              title: 'Create new invoice',
              subtitle: 'Request a payment from a customer',
              onPressed: () => _openCreate(context),
            ),
            const SizedBox(height: 12),
            GetPaidSlotCard(
              icon: Icons.receipt_long,
              title: 'View invoices',
              subtitle: 'Track invoice status and payment history',
              onPressed: () => context.pushNamed(InvoicesRoute.list.name),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    final changed = await context.pushNamed<bool>(InvoicesRoute.create.name);
    if (changed == true && context.mounted) {
      context.pop(true);
    }
  }
}
