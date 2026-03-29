// lib/features/auth/presentation/login_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: exibir a UI e capturar eventos do usuário.
// Esta camada NÃO contém lógica de negócio — só chama métodos
// do Notifier e reage aos estados que recebe.
//
// CONCEITOS APLICADOS:
// - ConsumerWidget: widget que acessa providers do Riverpod
// - Pattern matching com switch sobre sealed class AuthState
// - Separação clara: UI decide COMO exibir, application decide O QUÊ

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/auth_provider.dart';

// ConsumerWidget — substituto do StatelessWidget quando o widget
// precisa acessar providers. O parâmetro 'ref' dá acesso ao Riverpod.
// Conceito: a UI observa o estado, não o gerencia.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ref.watch — observa o estado e reconstrói o widget quando muda.
    // Conceito Riverpod: reatividade declarativa —
    // você não chama setState(), o Riverpod reconstrói automaticamente.
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          // switch sobre sealed class — Dart exige que todos os
          // casos sejam tratados. Se adicionarmos um novo AuthState,
          // o compilador avisa aqui imediatamente.
          child: switch (authState) {
            AuthCarregando() => const Center(
                child: CircularProgressIndicator(),
              ),
            AuthErro(:final mensagem) => _LoginForm(
                erro: mensagem,
              ),
            AuthAutenticado(:final usuario) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Bem-vindo, ${usuario.nome}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      usuario.role,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () =>
                          ref.read(authProvider.notifier).logout(),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            // Todos os demais estados exibem o formulário
            _ => const _LoginForm(),
          },
        ),
      ),
    );
  }
}

// Widget privado — só LoginScreen pode usar
// Conceito POO: encapsulamento de componente visual
// O underscore no nome torna a classe privada ao arquivo
class _LoginForm extends ConsumerStatefulWidget {
  final String? erro;

  const _LoginForm({this.erro});

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  // Controllers gerenciam o texto dos campos
  // São criados aqui pois pertencem ao ciclo de vida deste widget
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  // Chave do formulário — permite validação programática
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // Conceito: gerenciamento de recursos — sempre liberar
    // controllers quando o widget é removido da árvore
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _submeter() {
    // Valida todos os campos do formulário antes de chamar o login
    if (_formKey.currentState?.validate() != true) return;

    // ref.read — usado para ações pontuais, não observação contínua.
    // Conceito: a UI chama o método do Notifier, não modifica estado.
    ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _senhaController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ERP Modular',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Almoxarifado e Estoque',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),

          // Exibe erro se existir — recebido como parâmetro,
          // não gerado aqui. A camada application define a mensagem.
          if (widget.erro != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                widget.erro!,
                style: TextStyle(color: Colors.red.shade700),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
            // Validação inline — retorna String (erro) ou null (válido)
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Informe o email';
              }
              if (!value.contains('@')) {
                return 'Email inválido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _senhaController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outlined),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Informe a senha';
              }
              if (value.length < 6) {
                return 'Senha deve ter pelo menos 6 caracteres';
              }
              return null;
            },
            // Permite submeter pelo teclado sem tocar no botão
            onFieldSubmitted: (_) => _submeter(),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _submeter,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }
}