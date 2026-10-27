/**
 * Mapeia rotas e itens do sidebar para os "módulos" usados em
 * `perfil_permissoes.modulo`. Quando um usuário tem um perfil de acesso
 * vinculado, o sidebar e o ProtectedRoute usam este mapa para esconder/bloquear
 * páginas que ele não pode acessar.
 *
 * Owners (proprietário) e superadmins ignoram este mapa (acesso total).
 *
 * Comportamento de fallback: para usuários COM perfil vinculado, qualquer
 * rota não mapeada e não listada em `ALWAYS_ALLOWED_PATHS` é considerada
 * RESTRITA (bloqueada). Para usuários sem perfil vinculado, vale a hierarquia
 * de roles (definida no ProtectedRoute / AppSidebar).
 */
/**
 * Cada rota aceita UM OU MAIS módulos. A trava libera a rota se o perfil tiver
 * QUALQUER um deles.
 *
 * Por que uma lista, e não um módulo só: o editor de perfis (MODULOS_SISTEMA em
 * usePerfisAcesso) oferece módulos granulares — "empresa", "filiais", "cargos",
 * "ponto", "ferias", "metas"… — e grava exatamente esse id em
 * `perfil_permissoes.modulo`. Antes, este mapa guardava só o id GROSSO
 * ("configuracoes", "colaboradores", "admissoes", "avaliacoes", "bem_estar"),
 * então marcar "Empresa", "Ponto" ou "Metas" no editor não surtia efeito: a
 * trava nunca checava esses ids, e o usuário com perfil ficava SEM as telas que
 * o administrador havia liberado ("faltou acesso"). Agora cada rota lista o id
 * grosso legado (mantém TODOS os perfis antigos funcionando, sem regressão) MAIS
 * o(s) id(s) granular(es) do editor (faz a definição do perfil valer de fato). É
 * aditivo: só ACRESCENTA formas de liberar a rota, nunca remove acesso.
 *
 * O primeiro id de cada lista é o grosso/legado (usado por `getModuloForPath`).
 */
export const PATH_TO_MODULOS: Record<string, string[]> = {
  // Estrutura organizacional
  "/empresa": ["configuracoes", "empresa"],
  "/cadastros/filiais": ["configuracoes", "filiais"],
  "/cadastros/departamentos": ["configuracoes", "departamentos"],
  "/cadastros/cargos": ["configuracoes", "cargos"],
  "/colaboradores": ["colaboradores"],
  // "/marketplace" — acesso global (ver ALWAYS_ALLOWED_PATHS)

  // Estratégia & Governança (link de topo do sidebar)
  "/estrategia": ["configuracoes", "identidade_estrategica", "planejamento_estrategico"],

  // Saúde & Segurança
  "/compliance-sst": ["sst"],
  // Faltava no mapa, e rota fora do mapa é rota BLOQUEADA para quem tem
  // perfil vinculado: ninguém com perfil alcançava Saúde Ocupacional.
  // Achado ao revisar as ressalvas do parecer de 07/08.
  "/saude-ocupacional": ["sst"],
  "/incidentes-acidentes": ["incidentes"],
  "/ergonomia": ["ergonomia"],
  "/psicossocial": ["psicossocial"],
  "/epis": ["epi"],
  "/terceiros": ["sst", "terceiros"],

  // Planos & Desenvolvimento
  "/metas": ["avaliacoes", "metas"],
  "/plano-acao": ["plano_acao"],
  "/avaliacoes": ["avaliacoes"],
  "/pdi": ["pdi"],
  "/mapa-comportamental": ["mapa_comportamental"],

  // Pessoas
  "/cultura-celebracoes": ["bem_estar", "cultura_celebracoes"],
  "/contratos-experiencia": ["admissoes", "contratos_experiencia"],
  "/onboarding-rh": ["admissoes", "onboarding"],
  "/ferias": ["colaboradores", "ferias"],
  "/atestados": ["atestados"],
  "/felicidade": ["bem_estar"],
  "/feedback-ocorrencias": ["feedback"],
  "/ouvidoria": ["ouvidoria"],
  "/aprendizado-papeis": ["trilhas", "aprendizado"],
  "/trilhas": ["trilhas"],
  "/feed": ["bem_estar", "feed"],
  "/ponto": ["colaboradores", "ponto"],
  "/analise-jornada": ["colaboradores", "analise_jornada"],

  // Documentos
  "/documentos": ["configuracoes", "documentos"],

  // Gestão de usuários — também faltava no mapa, com o mesmo efeito.
  "/usuarios": ["configuracoes", "usuarios"],

  // Financeiro
  "/financeiro": ["financeiro"],
  "/financeiro/beneficios": ["beneficios"],
  "/hub-contabil": ["hub_contabil"],

  // Academia (acessível via perfil/roles)
  "/academia": ["trilhas", "academia"],
};

/**
 * Compatibilidade: versão achatada (rota → módulo grosso/legado), para quem
 * ainda consome um id único. É o PRIMEIRO item de cada lista acima.
 */
export const PATH_TO_MODULO: Record<string, string> = Object.fromEntries(
  Object.entries(PATH_TO_MODULOS).map(([path, modulos]) => [path, modulos[0]])
);

/**
 * Rotas administrativas: exigem que o perfil tenha pelo menos UMA permissão
 * no módulo com escopo diferente de `proprio_usuario`. Sem isso, a rota é
 * bloqueada mesmo quando o módulo aparece em `perfil_permissoes`.
 *
 * Exemplo: um Colaborador com `colaboradores:visualizar (proprio_usuario)`
 * pode ver o próprio perfil em /meu-perfil, mas NÃO pode entrar em
 * /colaboradores (listagem geral / botões de gestão).
 */
export const ADMIN_PATHS = new Set<string>([
  "/empresa",
  "/cadastros/filiais",
  "/cadastros/departamentos",
  "/cadastros/cargos",
  "/colaboradores",
  
  "/contratos-experiencia",
  "/onboarding-rh",
  "/ferias",
  "/atestados",
  "/feedback-ocorrencias",
  "/analise-jornada",
  "/ponto",
  // /documentos NÃO é admin-only: com escopo "próprio usuário" a pessoa acessa
  // a tela para ver apenas a própria pasta (a RLS e a própria tela já limitam o
  // que aparece). Admin-only aqui esconderia o módulo de quem tem escopo próprio.
  "/financeiro",
  "/financeiro/beneficios",
  "/hub-contabil",
  "/compliance-sst",
  "/incidentes-acidentes",
  "/ergonomia",
  "/psicossocial",
  "/epis",
  "/terceiros",
  "/metas",
  "/plano-acao",
  "/avaliacoes",
  "/estrategia",
]);

/**
 * Rotas sempre liberadas para usuários autenticados, mesmo com perfil restrito.
 * Inclui itens essenciais ao auto-serviço (próprio perfil, suporte, etc).
 */
export const ALWAYS_ALLOWED_PATHS = new Set<string>([
  "/",
  "/marketplace", // MarketYE (marketplace de serviços): módulo global no header

  "/meu-perfil",
  "/meu-plano", // autosserviço: cada empresa vê o próprio plano/consumo
  "/suporte",
  "/sobre-sistema", // página informativa, está no menu de todos; sem módulo mapeado ela ficava bloqueada para quem tem perfil
  "/pendencias",
  "/configuracoes", // endereço antigo da tela de Usuários: só redireciona para /usuarios
  "/usuarios", // a página em si filtra por role (abas só para admin); sempre liberada, como era /configuracoes
  "/onboarding-rh-self",
  "/bem-estar", // espaço pessoal de auto-percepção
]);

/**
 * Devolve o módulo associado a uma rota, ou null se a rota é considerada
 * "global" (sempre liberada — vide `ALWAYS_ALLOWED_PATHS`).
 *
 * IMPORTANTE: para o gating estrito por perfil, a checagem deve ser feita
 * em duas etapas pelo chamador:
 *   1) se a rota está em `ALWAYS_ALLOWED_PATHS` → liberada
 *   2) caso contrário, exigir mapeamento em `PATH_TO_MODULO` e validar a permissão
 *      Rotas não mapeadas para usuários COM perfil vinculado devem ser BLOQUEADAS.
 */
export function getModulosForPath(pathname: string): string[] | null {
  // Normaliza: remove query string e hash
  const cleanPath = pathname.split("?")[0].split("#")[0];

  // Match exato
  if (PATH_TO_MODULOS[cleanPath]) return PATH_TO_MODULOS[cleanPath];

  // Match por prefixo (mais longo primeiro)
  const sortedKeys = Object.keys(PATH_TO_MODULOS).sort((a, b) => b.length - a.length);
  for (const key of sortedKeys) {
    if (cleanPath === key || cleanPath.startsWith(key + "/")) {
      return PATH_TO_MODULOS[key];
    }
  }
  return null;
}

/**
 * Compatibilidade: devolve só o módulo grosso/legado (primeiro da lista).
 * Prefira `getModulosForPath` para o gating, que considera também os módulos
 * granulares do editor.
 */
export function getModuloForPath(pathname: string): string | null {
  return getModulosForPath(pathname)?.[0] ?? null;
}

/**
 * Indica se a rota é "administrativa" (listagem/gestão), exigindo permissão
 * com escopo diferente de `proprio_usuario`.
 */
export function isAdminPath(pathname: string): boolean {
  const cleanPath = pathname.split("?")[0].split("#")[0];
  if (ADMIN_PATHS.has(cleanPath)) return true;
  for (const p of ADMIN_PATHS) {
    if (cleanPath.startsWith(p + "/")) return true;
  }
  return false;
}

/**
 * Rotas que NÃO precisam de módulo, declaradas de propósito.
 *
 * Existe por causa de uma ressalva do parecer de perfis de acesso (07/08):
 * "rota nova esquecida fica inacessível a todos, inclusive a quem deveria
 * ver. É falha visível — melhor que o contrário, mas gera chamado."
 *
 * O problema real não é o bloqueio: é não haver como distinguir a rota que
 * ficou de fora POR ESQUECIMENTO da que está fora DE PROPÓSITO. Sem essa
 * distinção, ninguém consegue auditar o mapa — foi assim que
 * /saude-ocupacional e /usuarios ficaram inacessíveis a todo usuário com
 * perfil vinculado, sem ninguém notar.
 *
 * Declarar aqui o que é intencional transforma o risco invisível numa
 * conferência possível: `rotasNaoClassificadas` acusa o resto.
 */
export const ROTAS_PUBLICAS = new Set<string>([
  "/login",
  "/register",
  "/forgot-password",
  "/reset-password",
  "/ativar-conta",
  "/onboarding",
  "/onboarding-rh-self",
  "/admissao",
  "/ponto-externo",          // batida por link externo, sem sessão
  "/lp",
  "/site",
  "/politica-de-privacidade",
  "/termos-de-uso",
  "/marketye",               // MarketYE: página pública de captação de especialistas
  "/marketye/cadastro",      // MarketYE: cadastro do especialista sem acesso ao sistema
  "/marketye/entrar",        // MarketYE: login do especialista
  "/marketye/portal",        // MarketYE: portal restrito do especialista (guarda própria)
]);

/** Rotas internas da YourEyes, liberadas apenas para superadmin. */
export const ROTAS_SUPERADMIN = new Set<string>([
  "/admin",
  "/admin/blog",
  "/admin/contratos",
  "/admin/manual",
  "/admin/qa",
  "/admin/qa/docs",
  "/admin/qa/runner",
  "/admin/controle-clientes",
  "/admin/youreyes",
]);

/**
 * Recebe as rotas declaradas na aplicação e devolve as que não estão em
 * lugar nenhum: nem no mapa de módulos, nem entre as sempre liberadas,
 * nem entre as públicas, nem entre as de superadmin.
 *
 * Cada rota devolvida aqui está hoje BLOQUEADA para todo usuário com
 * perfil vinculado — ou é esquecimento, ou falta declarar a intenção.
 */
export function rotasNaoClassificadas(rotasDeclaradas: string[]): string[] {
  return rotasDeclaradas
    .filter((r) => !r.includes(":") && !r.includes("*"))
    .filter(
      (r) =>
        !PATH_TO_MODULO[r] &&
        !ALWAYS_ALLOWED_PATHS.has(r) &&
        !ROTAS_PUBLICAS.has(r) &&
        !ROTAS_SUPERADMIN.has(r)
    )
    .sort();
}
