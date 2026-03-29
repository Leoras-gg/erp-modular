// lib/features/auth/domain/usuario.dart

// Conceito POO: Classe com encapsulamento correto
// - Todos os campos são final (imutáveis após criação)
// - Nenhum setter público — o objeto não muda depois de criado
// - Criação controlada via factory constructors (Factory Pattern)

class Usuario {
  final String id;
  final String email;
  final String nome;
  final String role; // 'admin' ou 'operador'
  final String empresaId;

  // Construtor privado — só os factories abaixo podem criar um Usuario
  // Conceito: encapsulamento da criação
  const Usuario({
    required this.id,
    required this.email,
    required this.nome,
    required this.role,
    required this.empresaId,
  });

  // Factory Pattern: cria Usuario a partir dos dados do Supabase
  // Conceito: o resto do código não sabe como o banco organiza os dados
  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] as String,
      email: map['email'] as String,
      nome: map['nome'] as String? ?? 'Sem nome',
      role: map['role'] as String? ?? 'operador',
      empresaId: map['empresa_id'] as String,
    );
  }

  // Converte o Usuario de volta para Map — usado ao salvar no banco
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'nome': nome,
      'role': role,
      'empresa_id': empresaId,
    };
  }

  // Conceito: objetos de domínio devem ser comparáveis pelo valor,
  // não pela referência de memória
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Usuario && other.id == id;

  @override
  int get hashCode => id.hashCode;

  // Útil para debug — print(usuario) mostra algo legível
  @override
  String toString() => 'Usuario(id: $id, email: $email, role: $role)';
}