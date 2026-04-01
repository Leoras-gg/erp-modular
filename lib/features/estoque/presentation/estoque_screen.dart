// lib/features/estoque/presentation/estoque_screen.dart
//
// PLACEHOLDER — será implementado nas Semanas 3 a 10
// Esta tela será a home do módulo de Almoxarifado e Estoque

import 'package:flutter/material.dart';

class EstoqueScreen extends StatelessWidget {
  const EstoqueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Estoque', style: TextStyle(fontSize: 24, color: Colors.grey)),
          SizedBox(height: 8),
          Text('Em desenvolvimento — Módulo 1',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}