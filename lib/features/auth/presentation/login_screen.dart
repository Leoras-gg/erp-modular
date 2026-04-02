// lib/features/auth/presentation/login_screen.dart
//
// CAMADA: presentation
// RESPONSABILIDADE: tela de login com suporte a:
// - Email salvo localmente (opt-in via checkbox)
// - Confirmação de senha quando há sessão ativa (devMode = false)
// - Feedback visual de todos os estados de autenticação
//
// COMPORTAMENTO POR ESTADO:
// AuthNaoAutenticado       → formulário normal, email pode estar preenchido
// AuthAguardandoConfirmacao → formulário com email preenchido e readonly,
//                             mensagem explicativa de segurança
// AuthCarregando           → loading indicator
// AuthErro                 → erro já tratado no Notifier, estado volta para
//                             AuthNaoAutenticado automaticamente

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: switch (authState) {
            AuthCarregando() || AuthInicial() => const Center(
                child: CircularProgressIndicator(),
              ),

            AuthAutenticado() => const Center(
                child: CircularProgressIndicator(),
              ),

            // Sessão ativa mas app exige senha — mostra aviso de segurança
            AuthAguardandoConfirmacao(:final emailPreenchido) => _LoginForm(
                emailInicial: emailPreenchido,
                emailReadOnly: true, // não deixa trocar o email
                mensagemSeguranca:
                    'Por segurança, confirme sua senha para continuar.',
              ),

            // Login normal — email pode estar preenchido por "lembrar email"
            AuthNaoAutenticado(:final emailPreenchido) => _LoginForm(
                emailInicial: emailPreenchido,
                emailReadOnly: false,
              ),

            // Erro — o Notifier já volta para AuthNaoAutenticado após 2s
            AuthErro(:final mensagem) => _LoginForm(
                erro: mensagem,
                emailReadOnly: false,
              ),
          },
        ),
      ),
    );
  }
}

class _LoginForm extends ConsumerStatefulWidget {
  final String? emailInicial;
  final bool emailReadOnly;
  final String? erro;
  final String? mensagemSeguranca;

  const _LoginForm({
    this.emailInicial,
    required this.emailReadOnly,
    this.erro,
    this.mensagemSeguranca,
  });

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Estado local do checkbox "Lembrar meu email"
  bool _lembrarEmail = false;

  @override
  void initState() {
    super.initState();

    // Preenche o email se foi passado (salvo anteriormente ou da sessão)
    if (widget.emailInicial != null) {
      _emailController.text = widget.emailInicial!;
      // Se o email veio preenchido, assume que "lembrar" estava ativo
      _lembrarEmail = true;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _submeter() {
    if (_formKey.currentState?.validate() != true) return;

    ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _senhaController.text,
          lembrarEmail: _lembrarEmail,
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
          // ---- CABEÇALHO ----
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
          const SizedBox(height: 40),

          // ---- AVISO DE SEGURANÇA (quando há sessão ativa) ----
          if (widget.mensagemSeguranca != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.mensagemSeguranca!,
                      style: TextStyle(color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ---- MENSAGEM DE ERRO ----
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

          // ---- CAMPO EMAIL ----
          TextFormField(
            controller: _emailController,
            // emailReadOnly = true quando há sessão ativa (confirmar senha)
            // O usuário não pode trocar de conta sem deslogar primeiro
            readOnly: widget.emailReadOnly,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email_outlined),
              // Indica visualmente que o campo está bloqueado
              filled: widget.emailReadOnly,
              fillColor: widget.emailReadOnly
                  ? Colors.grey.shade100
                  : null,
              suffixIcon: widget.emailReadOnly
                  ? const Tooltip(
                      message: 'Para trocar de usuário, clique em Sair',
                      child: Icon(Icons.lock_outline, size: 18),
                    )
                  : null,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Informe o email';
              }
              if (!value.contains('@')) return 'Email inválido';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // ---- CAMPO SENHA ----
          TextFormField(
            controller: _senhaController,
            obscureText: true,
            autofocus: widget.emailReadOnly, // foca na senha quando email já está preenchido
            decoration: const InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outlined),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Informe a senha';
              if (value.length < 6) return 'Senha deve ter ao menos 6 caracteres';
              return null;
            },
            onFieldSubmitted: (_) => _submeter(),
          ),
          const SizedBox(height: 8),

          // ---- CHECKBOX LEMBRAR EMAIL ----
          // Só aparece quando o email não está bloqueado (não é confirmação)
          if (!widget.emailReadOnly)
            CheckboxListTile(
              value: _lembrarEmail,
              onChanged: (value) {
                setState(() => _lembrarEmail = value ?? false);
              },
              title: const Text('Lembrar meu email neste dispositivo'),
              subtitle: const Text(
                'A senha nunca é salva — apenas o email.',
                style: TextStyle(fontSize: 11),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),

          const SizedBox(height: 24),

          // ---- BOTÃO ENTRAR ----
          ElevatedButton(
            onPressed: _submeter,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Entrar'),
          ),

          // ---- LINK TROCAR USUÁRIO (quando email está bloqueado) ----
          if (widget.emailReadOnly) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Faz logout completo — limpa sessão Supabase
                // Na próxima tela, email NÃO estará bloqueado
                ref.read(authProvider.notifier).logout();
              },
              child: const Text('Não sou eu — trocar usuário'),
            ),
          ],
        ],
      ),
    );
  }
}