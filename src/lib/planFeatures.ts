/**
 * Mapa da EMBALAGEM COMERCIAL: qual caminho do menu pertence a qual
 * funcionalidade (feature_key) do motor de entitlements, e em qual plano
 * essa funcionalidade passa a existir.
 *
 * É usado SÓ pela camada visual (menu): módulos fora do plano da empresa
 * aparecem com cadeado + convite de upgrade. NÃO é bloqueio de dado — a
 * trava "de verdade" no banco é um passo separado.
 *
 * Regras:
 *  - Caminho NÃO mapeado aqui = sempre visível (à prova de falha).
 *  - Planos internos (tester/early_adopter) e Super Admin veem tudo — o
 *    tratamento fica no chamador (useTenantFeatures / AppSidebar).
 *
 * Fonte: página comercial (youreyes.com.br) + catálogo public.plans.
 */
export const PATH_TO_FEATURE: Record<string, string> = {
  // Starter (todos os planos têm — nunca cadeia)
  "/empresa": "mod.estrutura",
  "/cadastros/filiais": "mod.estrutura",
  "/cadastros/departamentos": "mod.estrutura",
  "/cadastros/cargos": "mod.estrutura",
  "/colaboradores": "mod.estrutura",
  "/terceiros": "mod.estrutura",
  "/compliance-sst": "mod.nr1",
  "/ponto": "mod.ponto",
  "/ferias": "mod.ferias",
  "/atestados": "mod.ferias",
  "/onboarding-rh": "mod.onboarding",

  // Essential
  "/psicossocial": "mod.psicossocial",
  "/ergonomia": "mod.epi_ergo",
  "/epis": "mod.epi_ergo",
  "/analise-jornada": "mod.analise_jornada",

  // Performance
  "/financeiro/beneficios": "mod.beneficios",
  "/documentos": "mod.beneficios",
  "/hub-contabil": "mod.beneficios",
  "/metas": "mod.metas",
  "/plano-acao": "mod.metas",
  "/trilhas": "mod.trilhas",
  "/aprendizado-papeis": "mod.trilhas",
  "/contratos-experiencia": "mod.contratos_exp",
  "/cultura-celebracoes": "mod.cultura",
  "/feedback-ocorrencias": "mod.cultura",
  "/ouvidoria": "mod.cultura",
  "/feed": "mod.cultura",

  // Governança / Enterprise: hoje sem item de menu dedicado (SSO, KPIs,
  // integração ERP, etc.). Ficam de fora do mapa até virarem tela.
};

/**
 * Nome do plano em que cada funcionalidade passa a existir — para a mensagem
 * de upgrade ("Disponível no plano X").
 */
export const FEATURE_PLAN_NAME: Record<string, string> = {
  // Starter
  "mod.estrutura": "Starter",
  "mod.nr1": "Starter",
  "mod.ponto": "Starter",
  "mod.ferias": "Starter",
  "mod.onboarding": "Starter",
  // Essential
  "mod.gro_pgr": "Essential",
  "mod.psicossocial": "Essential",
  "mod.epi_ergo": "Essential",
  "mod.analise_jornada": "Essential",
  // Performance
  "mod.beneficios": "Performance",
  "mod.metas": "Performance",
  "mod.trilhas": "Performance",
  "mod.cultura": "Performance",
  "mod.contratos_exp": "Performance",
  // Governança
  "mod.sso": "Governança",
  "mod.kpis": "Governança",
  "mod.integracao": "Governança",
};

/** Funcionalidade associada a um caminho, ou null se o caminho não é gateado. */
export function featureForPath(pathname: string): string | null {
  const cleanPath = pathname.split("?")[0].split("#")[0];
  if (PATH_TO_FEATURE[cleanPath]) return PATH_TO_FEATURE[cleanPath];
  const sortedKeys = Object.keys(PATH_TO_FEATURE).sort((a, b) => b.length - a.length);
  for (const key of sortedKeys) {
    if (cleanPath === key || cleanPath.startsWith(key + "/")) return PATH_TO_FEATURE[key];
  }
  return null;
}

/** Nome do plano que libera o caminho (para a mensagem de upgrade). */
export function planNameForPath(pathname: string): string | null {
  const feature = featureForPath(pathname);
  if (!feature) return null;
  return FEATURE_PLAN_NAME[feature] ?? null;
}
