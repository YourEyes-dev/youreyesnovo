// Lógica pura (sem API do Deno) da função ai-cultura-dia-profissao: prompt e,
// principalmente, a VALIDAÇÃO do que a IA devolve. A IA erra datas
// comemorativas; nada que ela devolva vale sem passar por aqui e, depois, pela
// aprovação de uma pessoa na tela. Fica em _shared para o vitest importar.

export const MAX_CARGOS_POR_CHAMADA = 30;
export const MAX_TAMANHO_CARGO = 80;

export type Confianca = "alta" | "media" | "baixa";

export interface SugestaoDiaProfissao {
  /** exatamente como foi enviado */
  cargo: string;
  profissao: string | null;
  nome_data: string | null;
  mes: number | null;
  dia: number | null;
  confianca: Confianca | null;
  base: string | null;
  observacao: string | null;
}

export const SISTEMA = `Você conhece o calendário brasileiro de dias de profissões (datas fixadas em lei federal ou decreto e datas consagradas pela categoria).
Para cada cargo recebido, identifique a profissão correspondente e o dia comemorativo dela no Brasil.
Regras obrigatórias:
- Só informe a data quando tiver ALTA certeza de que ela existe. Na dúvida, devolva mes e dia como null. Nunca invente data.
- Prefira datas oficiais (lei ou decreto). Se for data consagrada sem lei, diga isso em "base".
- Ignore nível, senioridade e flexão de gênero ao identificar a profissão (Júnior, Pleno, Sênior, I, II, III, Líder, Auxiliar de, Assistente de, (a)).
- Cargos diferentes da mesma profissão recebem a mesma data.
- Cargo genérico ou interno, sem profissão regulamentada ou consagrada, recebe mes e dia null.
- "confianca": "alta" só para data oficial ou amplamente consagrada; "media" quando a categoria comemora em mais de uma data ou há divergência; "baixa" se houver dúvida real.
Responda APENAS com JSON no formato:
{"resultados":[{"cargo":"<exatamente como recebido>","profissao":"<nome da profissão ou null>","nome_data":"<ex.: Dia do Motorista, ou null>","mes":<1-12 ou null>,"dia":<1-31 ou null>,"confianca":"alta|media|baixa","base":"<ex.: Lei 13.103/2015, ou Data consagrada, ou null>","observacao":"<até 120 caracteres ou null>"}]}`;

export function montarPrompt(cargos: string[]): string {
  return `Cargos da empresa:\n${cargos.map((c, i) => `${i + 1}. ${c}`).join("\n")}`;
}

/** Remove vazios e repetidos (sem diferenciar maiúsculas) e limita tamanho e quantidade. */
export function prepararCargos(entrada: unknown): string[] {
  if (!Array.isArray(entrada)) return [];
  const vistos = new Set<string>();
  const saida: string[] = [];
  for (const item of entrada) {
    if (typeof item !== "string") continue;
    const cargo = item.trim().replace(/\s+/g, " ").slice(0, MAX_TAMANHO_CARGO);
    if (!cargo) continue;
    const k = cargo.toLowerCase();
    if (vistos.has(k)) continue;
    vistos.add(k);
    saida.push(cargo);
    if (saida.length >= MAX_CARGOS_POR_CHAMADA) break;
  }
  return saida;
}

const DIAS_DO_MES = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]; // fevereiro aceita 29

export function dataValida(mes: unknown, dia: unknown): mes is number {
  return (
    typeof mes === "number" && typeof dia === "number" &&
    Number.isInteger(mes) && Number.isInteger(dia) &&
    mes >= 1 && mes <= 12 && dia >= 1 && dia <= DIAS_DO_MES[mes - 1]
  );
}

const texto = (v: unknown, max: number): string | null =>
  typeof v === "string" && v.trim() ? v.trim().slice(0, max) : null;

/**
 * Casa o que a IA devolveu com os cargos enviados (na ordem de envio), descarta
 * data impossível e nunca aceita cargo que não foi pedido. Sem data válida o
 * resultado vira "sem data conhecida" em vez de um palpite.
 */
export function sanitizarResultados(cargos: string[], bruto: unknown): SugestaoDiaProfissao[] {
  const lista = Array.isArray((bruto as { resultados?: unknown })?.resultados)
    ? ((bruto as { resultados: unknown[] }).resultados)
    : [];
  const porCargo = new Map<string, Record<string, unknown>>();
  for (const r of lista) {
    if (r && typeof r === "object" && typeof (r as Record<string, unknown>).cargo === "string") {
      porCargo.set(((r as Record<string, unknown>).cargo as string).trim().toLowerCase(), r as Record<string, unknown>);
    }
  }
  return cargos.map((cargo) => {
    const r = porCargo.get(cargo.toLowerCase());
    const vazio: SugestaoDiaProfissao = { cargo, profissao: null, nome_data: null, mes: null, dia: null, confianca: null, base: null, observacao: null };
    if (!r) return vazio;
    const nomeData = texto(r.nome_data, 80);
    if (!dataValida(r.mes, r.dia) || !nomeData) {
      return { ...vazio, profissao: texto(r.profissao, 80), observacao: texto(r.observacao, 120) };
    }
    const confianca: Confianca = r.confianca === "alta" || r.confianca === "media" || r.confianca === "baixa" ? r.confianca : "baixa";
    return {
      cargo,
      profissao: texto(r.profissao, 80),
      nome_data: nomeData,
      mes: r.mes as number,
      dia: r.dia as number,
      confianca,
      base: texto(r.base, 120),
      observacao: texto(r.observacao, 120),
    };
  });
}
