// =====================================================================
// Credenciais do usuário de teste.
//
// Por que este arquivo existe: até 08/2026 os specs traziam o e-mail e a
// senha de uma pessoa real de cliente escritos no código, versionados no
// Git. Isso é dado pessoal exposto no repositório e senha em texto puro.
// A conta de teste agora é uma conta de robô, descartável, do ambiente
// de teste — o padrão vive no cypress.config.ts e pode ser trocado por
// CYPRESS_EMAIL / CYPRESS_PASSWORD sem tocar no código.
//
// Se alguém esvaziar as duas, a suíte para aqui com uma mensagem que diz
// o que fazer — melhor do que quebrar lá na frente com "não achei o
// campo de senha".
// =====================================================================

export interface CredenciaisDeTeste {
  email: string;
  senha: string;
}

export function credenciaisDeTeste(): CredenciaisDeTeste {
  const email = String(Cypress.env("email") || "");
  const senha = String(Cypress.env("senha") || "");

  if (!email || !senha) {
    throw new Error(
      "[Cypress] Faltam as credenciais do usuário de teste.\n" +
        "Defina as variáveis de ambiente antes de rodar:\n" +
        "  CYPRESS_EMAIL=<conta de teste do staging>\n" +
        "  CYPRESS_PASSWORD=<senha dessa conta>\n" +
        "Na esteira elas vêm dos secrets do repositório.\n" +
        "Nunca escreva credencial dentro de um spec.",
    );
  }

  return { email, senha };
}

// ---------------------------------------------------------------------
// Usuário RESTRITO (testes de permissão).
//
// Conta de colaborador comum com um perfil que só libera Documentos (escopo
// próprio). É semeada pela função seed-e2e-user junto com a conta-robô, no
// mesmo tenant de teste, com a MESMA senha da conta-robô (a suíte só conhece
// uma). O e-mail é fixo e fictício: não é pessoa real.
// ---------------------------------------------------------------------
export const EMAIL_USUARIO_RESTRITO = "restrito.e2e@youreyes.local";

export function credenciaisRestrito(): CredenciaisDeTeste {
  const { senha } = credenciaisDeTeste();
  return { email: EMAIL_USUARIO_RESTRITO, senha };
}
