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
  "/ferias": "mod.ferias",
  "/atestados": "mod.ferias",
  "/onboarding-rh": "mod.onboarding",

  // Essential
  "/ponto": "mod.ponto",
  "/psicossocial": "mod.psicossocial",
  "/ergonomia": "mod.epi_ergo",
  "/epis": "mod.epi_ergo",
  "/analise-jornada": "mod.analise_jornada",
  "/saude-ocupacional": "mod.saude_ocupacional",
  "/incidentes-acidentes": "mod.incidentes",

  // Performance
  "/financeiro/beneficios": "mod.beneficios",
  "/documentos": "mod.beneficios",
  "/hub-contabil": "mod.beneficios",
  "/financeiro": "mod.financeiro",
  "/metas": "mod.metas",
  "/plano-acao": "mod.metas",
  "/trilhas": "mod.trilhas",
  "/aprendizado-papeis": "mod.trilhas",
  "/avaliacoes": "mod.avaliacoes",
  "/pdi": "mod.pdi",
  "/felicidade": "mod.bem_estar",
  "/contratos-experiencia": "mod.contratos_exp",
  "/cultura-celebracoes": "mod.cultura",
  "/feedback-ocorrencias": "mod.cultura",
  "/ouvidoria": "mod.cultura",
  "/feed": "mod.cultura",

  // Governança — a rota /estrategia é COMPARTILHADA: o Organograma é
  // Estrutura (Starter) e Identidade/Planejamento são Estratégia (Governança).
  // Por isso o gate é POR ABA (a chave inclui o ?tab=...); featureForPath
  // casa a chave com query ANTES da sem query.
  "/estrategia?tab=organograma": "mod.estrutura", // Organograma — nunca cadeia
  "/estrategia?tab=cultura": "mod.estrategia",     // Identidade Estratégica
  "/estrategia": "mod.estrategia",                 // Planejamento Estratégico

  // Enterprise: SSO/IA/API sem item de menu dedicado (sem tela). Ficam de
  // fora do mapa até virarem tela.
};

/**
 * Nome do plano em que cada funcionalidade passa a existir — para a mensagem
 * de upgrade ("Disponível no plano X").
 */
export const FEATURE_PLAN_NAME: Record<string, string> = {
  // Starter
  "mod.estrutura": "Starter",
  "mod.nr1": "Starter",
  "mod.ferias": "Starter",
  "mod.onboarding": "Starter",
  // Essential
  "mod.ponto": "Essential",
  "mod.gro_pgr": "Essential",
  "mod.psicossocial": "Essential",
  "mod.epi_ergo": "Essential",
  "mod.analise_jornada": "Essential",
  "mod.saude_ocupacional": "Essential",
  "mod.incidentes": "Essential",
  // Performance
  "mod.beneficios": "Performance",
  "mod.metas": "Performance",
  "mod.trilhas": "Performance",
  "mod.cultura": "Performance",
  "mod.contratos_exp": "Performance",
  "mod.avaliacoes": "Performance",
  "mod.pdi": "Performance",
  "mod.bem_estar": "Performance",
  "mod.financeiro": "Performance",
  // Governança
  "mod.estrategia": "Governança",
  "mod.kpis": "Governança",
  "mod.integracao": "Governança",
  // Enterprise
  "mod.sso": "Enterprise",
};

/** Funcionalidade associada a um caminho, ou null se o caminho não é gateado. */
export function featureForPath(pathname: string): string | null {
  const full = pathname.split("#")[0]; // mantém a query (gate por aba)
  // 1) casa exatamente COM a query — ex.: /estrategia?tab=cultura
  if (PATH_TO_FEATURE[full]) return PATH_TO_FEATURE[full];
  const cleanPath = full.split("?")[0];
  // 2) casa exatamente sem a query
  if (PATH_TO_FEATURE[cleanPath]) return PATH_TO_FEATURE[cleanPath];
  // 3) casa por prefixo (só chaves sem query)
  const sortedKeys = Object.keys(PATH_TO_FEATURE)
    .filter((k) => !k.includes("?"))
    .sort((a, b) => b.length - a.length);
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
