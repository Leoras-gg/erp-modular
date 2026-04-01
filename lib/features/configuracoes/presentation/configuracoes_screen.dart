// lib/features/configuracoes/presentation/configuracoes_screen.dart
//
// PLACEHOLDER — será implementado quando o sistema de permissões
// e preferências de usuário estiverem prontos

import 'package:flutter/material.dart';

class ConfiguracoesScreen extends StatelessWidget {
  const ConfiguracoesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Configurações',
              style: TextStyle(fontSize: 24, color: Colors.grey)),
          SizedBox(height: 8),
          Text('Em desenvolvimento', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}