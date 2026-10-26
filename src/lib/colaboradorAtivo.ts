/**
 * Fonte única para esconder, dos lembretes/pendências/indicadores do Início, os
 * colaboradores que NÃO estão mais ativos (desligados ou reprovados).
 *
 * Por que precisa existir: desligar um colaborador só muda
 * `admissoes.status` para `'desligado'` (e grava `data_desligamento`). As linhas
 * dos outros módulos (férias pendentes, ajustes de ponto, avaliações, alertas de
 * saúde, afastamentos, documentos) PERMANECEM. Logo, sem um filtro de "ativo",
 * um lembrete sobra apontando para quem já saiu — foi o bug reportado pelo
 * cliente no Dashboard (tela inicial).
 *
 * Colaborador ATIVO no YourEyes = `admissoes.status = 'concluido'` (não existe
 * `'ativo'`), sem desligamento, dentro da(s) empresa(s) do tenant. Aqui tratamos
 * como "encerrado" quem está `desligado` ou `reprovado`: nunca deve aparecer em
 * lembrete. Admissões ainda em andamento (status diferente desses) seguem
 * visíveis — os documentos pendentes delas continuam sendo pendência legítima.
 *
 * A lógica é pura (sem Supabase) de propósito, para ter teste de unidade.
 */

/** Status de admissão que indicam colaborador encerrado (fora dos lembretes). */
export const STATUS_ENCERRADOS = ["desligado", "reprovado"] as const;

export function soDigitos(valor: string | null | undefined): string {
  return (valor ?? "").replace(/\D/g, "");
}

export function normalizarNome(valor: string | null | undefined): string {
  return (valor ?? "").trim().toLowerCase();
}

export interface AdmissaoStatusMinima {
  cpf: string | null;
  nome_completo: string | null;
  status: string | null;
}

export interface IndiceEncerrados {
  /** CPFs (só dígitos) de admissões encerradas. */
  cpfsEncerrados: Set<string>;
  /** CPFs (só dígitos) de admissões NÃO encerradas (ativas/em andamento). */
  cpfsAtivos: Set<string>;
  /** Nomes (normalizados) com ao menos uma admissão encerrada. */
  nomesEncerrados: Set<string>;
  /** Nomes (normalizados) com ao menos uma admissão NÃO encerrada. */
  nomesAtivos: Set<string>;
}

const ENCERRADOS = new Set<string>(STATUS_ENCERRADOS);

/** Monta o índice a partir da lista de admissões (cpf, nome, status) do tenant/empresa. */
export function construirIndiceEncerrados(admissoes: readonly AdmissaoStatusMinima[]): IndiceEncerrados {
  const idx: IndiceEncerrados = {
    cpfsEncerrados: new Set(),
    cpfsAtivos: new Set(),
    nomesEncerrados: new Set(),
    nomesAtivos: new Set(),
  };
  for (const a of admissoes) {
    const encerrado = ENCERRADOS.has((a.status ?? "").trim().toLowerCase());
    const cpf = soDigitos(a.cpf);
    const nome = normalizarNome(a.nome_completo);
    if (cpf) (encerrado ? idx.cpfsEncerrados : idx.cpfsAtivos).add(cpf);
    if (nome) (encerrado ? idx.nomesEncerrados : idx.nomesAtivos).add(nome);
  }
  return idx;
}

/**
 * Decide se um item de lembrete (identificado por CPF e/ou nome) pertence a um
 * colaborador ainda ATIVO — ou seja, se deve continuar aparecendo.
 *
 * Regras (falha para o lado de MOSTRAR, nunca esconde ativo por engano):
 * - CPF é a chave forte. Se o CPF bate com um encerrado → esconde. Se bate com
 *   um ativo, ou é desconhecido no índice → mostra.
 * - Sem CPF, cai no nome: só esconde se o nome aparece como encerrado E NÃO
 *   aparece como ativo (evita esconder um homônimo que ainda trabalha).
 * - Índice vazio (ex.: sem permissão de ler admissões) → mostra tudo, igual a
 *   antes (não regride o comportamento de quem não enxerga a base).
 */
export function colaboradorAtivo(
  idx: IndiceEncerrados,
  ref: { cpf?: string | null; nome?: string | null },
): boolean {
  const cpf = soDigitos(ref.cpf);
  if (cpf) {
    if (idx.cpfsEncerrados.has(cpf)) return false;
    return true;
  }
  const nome = normalizarNome(ref.nome);
  if (nome && idx.nomesEncerrados.has(nome) && !idx.nomesAtivos.has(nome)) return false;
  return true;
}
