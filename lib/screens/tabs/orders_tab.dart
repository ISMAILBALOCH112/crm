import 'package:flutter/material.dart';

import 'placeholder_tab.dart';

class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTab(icon: Icons.receipt_long_outlined, title: 'Orders');
  }
}
