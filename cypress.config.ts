import { defineConfig } from "cypress";
import { readFileSync, statSync } from "fs";

// =====================================================================
// A suíte Cypress escreve dados (cria campanha, setor, função, EPI...).
// Por isso ela só pode existir contra o AMBIENTE DE TESTE. Rodar contra
// a produção criaria lixo em cima de dados reais de cliente — proibido
// pelas regras da casa (ver CLAUDE.md).
//
// O alvo padrão é o site de teste publicado pelo workflow staging.yml.
// Quem quiser outro alvo usa CYPRESS_BASE_URL, mas só passa pela trava
// abaixo se for um host da lista de permitidos.
// =====================================================================

const SITE_DE_TESTE = "https://youreyes-dev.github.io/youreyesnovo/teste/";

// Lista de PERMITIDOS (não de proibidos): uma lista de proibidos deixaria
// passar o que esquecêssemos. O site de teste vive no GitHub Pages do próprio
// repositório (algo.github.io/<repo>/teste/); quando a conta/dono do repo muda,
// o host muda junto — por isso aceitamos QUALQUER subdomínio .github.io, em vez
// de fixar o dono e quebrar no próximo renome. Nunca há produção num .github.io
// (produção é o Lovable), e a trava refProducao ainda barra em tempo de execução.
const HOSTS_DE_TESTE_EXATOS = ["localhost", "127.0.0.1"];
function hostDeTestePermitido(host: string): boolean {
  return HOSTS_DE_TESTE_EXATOS.includes(host) || host.endsWith(".github.io");
}

function exigirAmbienteDeTeste(url: string): string {
  let host: string;

  try {
    host = new URL(url).hostname;
  } catch {
    throw new Error(
      `[Cypress] CYPRESS_BASE_URL não é uma URL válida: ${url}\n` +
        `Alvo esperado: ${SITE_DE_TESTE}`,
    );
  }

  if (!hostDeTestePermitido(host)) {
    throw new Error(
      `[Cypress] ALVO RECUSADO: ${url}\n` +
        `Esta suíte grava dados e só roda no ambiente de teste.\n` +
        `Hosts permitidos: *.github.io, localhost, 127.0.0.1\n` +
        `Site de teste: ${SITE_DE_TESTE}`,
    );
  }

  return url;
}

// =====================================================================
// RELATÓRIO DE VOLTA PARA O MOTOR DE QA
//
// O motor SQL marca todo caso `nivel = 'e2e'` como "não implementado",
// dizendo que a cobertura vive no Cypress. Faltava o caminho de volta:
// a suíte rodava e o resultado morria no log da esteira.
//
// Isto usa o evento `after:run`, que dispara UMA vez no fim da corrida
// inteira. Vantagem sobre um hook dentro dos testes: nenhum spec precisa
// ser alterado, e a corrida vira uma execução só no histórico em vez de
// uma por arquivo.
//
// Sem QA_E2E_URL/QA_E2E_TOKEN no ambiente, não envia nada e não reclama:
// corrida local de quem está depurando não deve sujar o painel de QA.
// =====================================================================

interface TesteDaCorrida {
  spec: string;
  teste: string;
  situacao: "passou" | "falhou" | "pulado";
  duracao_ms?: number;
  erro?: string;
  // Print da falha (PNG em base64, sem prefixo data:). Só em teste falho.
  evidencia_png?: string;
}

function situacaoDoCypress(estado: string | undefined): TesteDaCorrida["situacao"] {
  if (estado === "passed") return "passou";
  if (estado === "failed") return "falhou";
  return "pulado"; // pending, skipped, ou estado que o Cypress não classificou
}

// Limites para o print não estourar o corpo do POST à Edge Function.
const MAX_PRINT_BYTES = 1_000_000; // por imagem (arquivo cru); acima, pula
const ORCAMENTO_BASE64 = 4_000_000; // teto do total de base64 numa corrida

const soAlfaNum = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "");

// Acha o print da falha deste teste entre as screenshots da corrida e
// devolve em base64. Casa pelo nome do arquivo — o Cypress batiza o print
// com o caminho de títulos do teste. Nada aqui pode derrubar a corrida:
// qualquer erro de leitura vira "sem print".
function acharPrintBase64(
  screenshots: Array<{ path?: string }> | undefined,
  titulos: string[],
): string | undefined {
  if (!Array.isArray(screenshots) || screenshots.length === 0) return undefined;
  const alvo = soAlfaNum(titulos.join(" "));
  if (!alvo) return undefined;

  const achado = screenshots.find((s) => {
    if (!s?.path) return false;
    const nome = soAlfaNum(s.path.split(/[/\\]/).pop() || "");
    return nome.includes(alvo); // o nome do arquivo contém o título do teste
  });
  if (!achado?.path) return undefined;

  try {
    if (statSync(achado.path).size > MAX_PRINT_BYTES) {
      console.log(`[QA] Print grande demais, enviado sem imagem: ${achado.path}`);
      return undefined;
    }
    return readFileSync(achado.path).toString("base64");
  } catch {
    return undefined; // arquivo sumiu / sem permissão — segue sem print
  }
}

async function enviarParaOQA(resultados: unknown): Promise<void> {
  const url = process.env.QA_E2E_URL;
  const token = process.env.QA_E2E_TOKEN;

  if (!url || !token) {
    console.log("[QA] QA_E2E_URL/QA_E2E_TOKEN ausentes — resultado não enviado ao painel.");
    return;
  }

  // A forma de `results` muda entre versões do Cypress e vem vazia quando
  // a corrida aborta antes de rodar. Nada disso pode derrubar a suíte:
  // o valor da corrida são os testes, não o relatório.
  const runs = (resultados as { runs?: unknown[] })?.runs;
  if (!Array.isArray(runs)) {
    console.log("[QA] Corrida sem resultados legíveis — nada a enviar.");
    return;
  }

  const testes: TesteDaCorrida[] = [];
  const prints: Array<{ spec: string; teste: string; evidencia_png: string }> = [];
  let gastoBase64 = 0;
  let printsPulados = 0; // falhas cujo print não coube no orçamento

  for (const corrida of runs as Array<Record<string, any>>) {
    const spec: string = corrida?.spec?.relative ?? corrida?.spec?.name ?? "(spec desconhecido)";
    const screenshots = corrida?.screenshots as Array<{ path?: string }> | undefined;

    for (const teste of corrida?.tests ?? []) {
      const titulo: string[] = Array.isArray(teste?.title) ? teste.title : [String(teste?.title ?? "")];
      const situacao = situacaoDoCypress(teste?.state);
      const nomeTeste = titulo[titulo.length - 1] ?? "";

      testes.push({
        spec,
        // Último pedaço do título = o texto do it(). É por ele que a
        // tabela qa_cobertura_e2e liga o teste ao caso documentado.
        teste: nomeTeste,
        situacao,
        duracao_ms: teste?.attempts?.[teste.attempts.length - 1]?.duration ?? teste?.duration,
        erro: teste?.displayError ?? teste?.attempts?.[teste.attempts.length - 1]?.error?.message,
      });

      // Print só em teste que falhou (o Cypress só fotografa falha). Ele
      // NÃO vai junto dos resultados — vai depois, um a um, para o corpo de
      // cada requisição ficar pequeno (corpo grande dava HTTP 504).
      if (situacao === "falhou") {
        const png = acharPrintBase64(screenshots, titulo);
        if (png && gastoBase64 + png.length <= ORCAMENTO_BASE64) {
          prints.push({ spec, teste: nomeTeste, evidencia_png: png });
          gastoBase64 += png.length;
        } else if (png) {
          printsPulados++;
        }
      }
    }
  }

  if (printsPulados > 0) {
    console.log(
      `[QA] ${printsPulados} print(s) de falha ficaram de fora por limite de tamanho ` +
        `(orçamento ${Math.round(ORCAMENTO_BASE64 / 1_000_000)}MB por corrida). Estão na esteira.`,
    );
  }

  // POST com timeout: um envio travado não pode segurar a corrida.
  const postar = async (corpo: unknown, ms: number): Promise<Response> => {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), ms);
    try {
      return await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-qa-token": token },
        body: JSON.stringify(corpo),
        signal: ctrl.signal,
      });
    } finally {
      clearTimeout(t);
    }
  };

  // ── Fase 1: os resultados (sem imagem, corpo leve) ──
  let execucaoId: string | undefined;
  try {
    const resposta = await postar(
      { origem: process.env.QA_E2E_ORIGEM || "esteira", resultados: testes },
      30_000,
    );
    const corpo = await resposta.text();
    if (!resposta.ok) {
      console.log(`[QA] Painel recusou os resultados (HTTP ${resposta.status}): ${corpo}`);
      return;
    }
    try {
      execucaoId = JSON.parse(corpo)?.execucao_id;
    } catch {
      /* resposta sem JSON — segue sem anexar prints */
    }
    console.log(`[QA] ${testes.length} teste(s) enviados ao painel. Resposta: ${corpo}`);
  } catch (erro) {
    console.log(`[QA] Não consegui enviar os resultados: ${(erro as Error).message}`);
    return;
  }

  // ── Fase 2: cada print numa requisição pequena e separada ──
  if (!execucaoId || prints.length === 0) return;

  let enviados = 0;
  for (const p of prints) {
    try {
      const r = await postar({ execucao_id: execucaoId, ...p }, 30_000);
      if (r.ok) enviados++;
      else console.log(`[QA] Print de "${p.teste}" recusado (HTTP ${r.status}).`);
    } catch (erro) {
      console.log(`[QA] Print de "${p.teste}" não enviado: ${(erro as Error).message}`);
    }
  }
  console.log(`[QA] ${enviados}/${prints.length} print(s) de falha anexados ao painel.`);
}

// Tira barra(s) final(is) do alvo. Sem isto, `${baseUrl}/login` nos specs
// vira `.../youreyesnovo//login` — a esteira passa CYPRESS_BASE_URL
// com barra final. A barra dupla ainda rotearia (o basename absorve), mas
// URL suja em log de teste é pegadinha para o próximo que for depurar.
const alvoNormalizado = (process.env.CYPRESS_BASE_URL || SITE_DE_TESTE).replace(/\/+$/, "");

export default defineConfig({
  e2e: {
    baseUrl: exigirAmbienteDeTeste(alvoNormalizado),
    setupNodeEvents(on) {
      on("after:run", enviarParaOQA);
      // Ponte para o diagnóstico de falha do support/e2e.ts: o que chega aqui
      // é impresso no stdout do CI (o único canal de log legível de fora).
      on("task", {
        diag(mensagem: string) {
          console.log("\n[DIAG] " + mensagem + "\n");
          return null;
        },
      });
    },
    defaultCommandTimeout: 10000,
    pageLoadTimeout: 120000,
    // A suíte roda contra o ambiente de teste compartilhado (site publicado +
    // Supabase de staging), cujo tempo de resposta varia: cache do TanStack
    // Query ainda sem um INSERT recém-feito, contexto de empresa assentando,
    // rede. Isso gera falhas INTERMITENTES (um run passa, o próximo não) que,
    // por serem não-determinísticas, reprovam a rodada inteira e travam a
    // validação das levas. runMode:2 re-executa um teste que falhou (só no CI);
    // se passar numa das tentativas, conta como verde. Regressão REAL
    // (determinística) falha nas 3 tentativas e continua sendo acusada. Em
    // openMode (debug local) fica 0 para o flake aparecer na cara de quem depura.
    // O relatório ao painel de QA usa a ÚLTIMA tentativa (ver after:run), então
    // o resultado enviado continua fiel.
    retries: { runMode: 2, openMode: 0 },
    supportFile: "cypress/support/e2e.ts",
    specPattern: "cypress/e2e/**/*.cy.ts",
    env: {
      // Conta de teste do robô. É uma conta descartável do ambiente de
      // teste, sobre dados fictícios — por decisão do dono do produto
      // ela fica aqui mesmo, para a suíte rodar sem depender de secret.
      //
      // O que NÃO pode voltar a acontecer: conta de pessoa real, ou
      // senha que também valha em produção. Foi assim que a senha de
      // uma cliente acabou versionada nos specs até 08/2026.
      //
      // Quem quiser trocar sem mexer no código usa as variáveis de
      // ambiente, que continuam tendo precedência.
      email: process.env.CYPRESS_EMAIL || "teste@lucas.com",
      senha: process.env.CYPRESS_PASSWORD || "7654321",
      // Projeto Supabase de produção — a suíte aborta se a aplicação
      // tentar falar com ele. Segunda trava, agora em tempo de execução.
      refProducao: "diayjpsrcerycycyaxst",
    },
  },
});
