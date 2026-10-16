/**
 * Guarda de segurança das Edge Functions de IA e de QA (leitura estática do código).
 *
 * Motivo: funções com `verify_jwt = false` e chave de serviço já aceitaram
 * `tenantId` do corpo da requisição e chamadas sem login. Este teste falha se
 * alguém desfizer a proteção. Não substitui teste de invasão; é a trava barata
 * que roda em toda corrida.
 *
 * Regras guardadas (ver docs/ESPECIFICACAO_CENTRAL_DE_AGENTES_UI.md, seção 14):
 *  1) funções protegidas chamam o auxiliar de `_shared/auth.ts`;
 *  2) a empresa vem do cadastro do usuário, nunca do corpo (sem `tenantId` em req.json);
 *  3) nenhuma credencial fixa em código;
 *  4) funções de semeadura sem trava não existem.
 */
import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const FUNCOES = resolve(__dirname, "../../supabase/functions");
const ler = (f: string) => readFileSync(resolve(FUNCOES, f, "index.ts"), "utf8");

const COM_EMPRESA = ["ai-cultura-manual", "ai-cultura-sugestao", "ai-pop-generator", "ai-sst-analise"];
const SO_USUARIO = ["ai-chat"];
const SO_SUPERADMIN = ["ai-qa-scan", "ai-qa-agent"];

describe("Edge Functions de IA: autenticação", () => {
  it.each(COM_EMPRESA)("%s exige login e deriva a empresa do cadastro", (f) => {
    const src = ler(f);
    expect(src).toMatch(/_shared\/auth\.ts/);
    expect(src).toMatch(/await autenticar\(req\)/);
    // tenantId nunca é lido do corpo
    expect(src).not.toMatch(/(tenantId|tenant_id)[^;\n]*\}\s*=\s*(body|await req\.json\(\))/);
    expect(src).not.toMatch(/\{[^}]*\btenantId\b[^}]*\}\s*=\s*(body|await req\.json\(\))/);
  });

  it.each(SO_USUARIO)("%s exige usuário logado", (f) => {
    expect(ler(f)).toMatch(/await exigirUsuario\(req\)/);
  });

  it.each(SO_SUPERADMIN)("%s exige superadmin", (f) => {
    expect(ler(f)).toMatch(/await exigirSuperadmin\(req\)/);
  });

  it("ai-sst-analise só baixa arquivo da própria empresa", () => {
    const src = ler("ai-sst-analise");
    expect(src).toMatch(/startsWith\(`\$\{tenantId\}\//);
  });

  it("ai-qa-agent não tem credencial fixa no código", () => {
    const src = ler("ai-qa-agent");
    expect(src).not.toMatch(/TEST_PASSWORD\s*=\s*["'`]/);
    expect(src).not.toMatch(/TEST_EMAIL\s*=\s*["'`]/);
    expect(src).toMatch(/Deno\.env\.get\("QA_AGENT_PASSWORD"\)/);
  });

  it("ai-qa-agent só escreve na ilha de QA e nunca na empresa vinda do corpo", () => {
    const src = ler("ai-qa-agent");
    expect(src).toMatch(/TENANT_ILHA_QA/);
    expect(src).toMatch(/authTenantId === TENANT_ILHA_QA/);
    // a empresa não é lida do corpo da requisição nem serve de alternativa ao login
    expect(src).not.toMatch(/\{[^}]*\btenantId\b[^}]*\}\s*=\s*await req\.json\(\)/);
    expect(src).not.toMatch(/authTenantId\s*=\s*[^;\n]*\|\|\s*tenantId/);
    expect(src).not.toMatch(/effectiveTenant\s*=\s*authTenantId\s*\|\|/);
  });

  it("auxiliar de autenticação confere o login no Auth e não decodifica o token na mão", () => {
    const src = readFileSync(resolve(FUNCOES, "_shared/auth.ts"), "utf8");
    expect(src).toMatch(/auth\.getUser\(\)/);
    expect(src).not.toMatch(/atob\(/);
  });

  it("função de semeadura sem trava (seed-test-user) não existe mais", () => {
    expect(existsSync(resolve(FUNCOES, "seed-test-user"))).toBe(false);
    const toml = readFileSync(resolve(__dirname, "../../supabase/config.toml"), "utf8");
    expect(toml).not.toMatch(/functions\.seed-test-user/);
  });

  it("as demais funções de semeadura continuam fechadas por token + trava de ambiente", () => {
    for (const f of ["seed-e2e-user", "seed-demo-empresa"]) {
      const src = ler(f);
      expect(src).toMatch(/x-qa-token/);
      expect(src).toMatch(/QA_E2E_TOKEN/);
    }
  });
});
