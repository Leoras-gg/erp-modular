// lib/features/dashboard/presentation/dashboard_screen.dart
//
// PLACEHOLDER — será implementado no Módulo 4
// Existe agora para que o GoRouter funcione sem erros de importação

import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Dashboard', style: TextStyle(fontSize: 24, color: Colors.grey)),
          SizedBox(height: 8),
          Text('Em desenvolvimento — Módulo 4',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}