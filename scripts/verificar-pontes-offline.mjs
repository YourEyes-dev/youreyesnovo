// =====================================================================
// Confere, SEM rede e SEM banco, se cada ponte qa_cobertura_e2e escrita nas
// migrations aponta para o título EXATO de um it() que existe no spec.
//
// Por que existe: a guarda da esteira (qa:cobertura-e2e) só enxerga o banco do
// staging, DEPOIS do merge. Em 21/10/2026 uma migration gravou o título do CASO
// (maiúscula inicial) em vez do título do it() e reprovou o job de telas de todo
// mundo. Rodar isto antes do commit pega a mesma classe de erro em segundos.
//
//   node scripts/verificar-pontes-offline.mjs            -> lista divergências (exit 0)
//   node scripts/verificar-pontes-offline.mjs --estrito  -> exit 1 se houver alguma
//   node scripts/verificar-pontes-offline.mjs AUTH-05    -> só códigos com esse prefixo (e exit 1 se divergir)
//
// Vale a ÚLTIMA gravação de cada código (migrations em ordem de carimbo). Pontes antigas
// que outro trabalho renomeou podem aparecer como aviso; o prefixo isola o seu lote.
// =====================================================================

import { readFileSync, readdirSync } from "node:fs";

const norm = (s) => s.replace(/\s+/g, " ").trim();

const its = new Map();
for (const f of readdirSync("cypress/e2e").filter((x) => x.endsWith(".cy.ts"))) {
  const src = readFileSync(`cypress/e2e/${f}`, "utf8");
  const re = /\bit(?:\.\w+)?\(\s*(['"`])((?:\\.|(?!\1)[\s\S])*?)\1/g;
  const set = new Set();
  let m;
  while ((m = re.exec(src)) !== null) set.add(norm(m[2].replace(/\\(['"`\\])/g, "$1")));
  its.set(`cypress/e2e/${f}`, set);
}

const ponte = new Map();
const reP = /\(\s*'([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+)'\s*,\s*'(cypress\/e2e\/[a-z0-9-]+\.cy\.ts)'\s*,\s*'((?:[^']|'')*)'/g;
for (const f of readdirSync("supabase/migrations").filter((x) => x.endsWith(".sql")).sort()) {
  const src = readFileSync(`supabase/migrations/${f}`, "utf8");
  let m;
  while ((m = reP.exec(src)) !== null) ponte.set(m[1], { spec: m[2], teste: m[3].replace(/''/g, "'"), arq: f });
}

const prefixo = process.argv.slice(2).find((a) => !a.startsWith("--"));
const estrito = process.argv.includes("--estrito") || !!prefixo;

const ruins = [...ponte.entries()].filter(
  ([cod, p]) => (!prefixo || cod.startsWith(prefixo)) && !(its.get(p.spec) ?? new Set()).has(norm(p.teste)),
);

console.log(`${ponte.size} pontes lidas${prefixo ? ` (filtro ${prefixo})` : ""}; ${ruins.length} sem it() de mesmo título.`);
for (const [cod, p] of ruins) console.log(`  - ${cod} → ${p.spec} :: "${p.teste}"  [${p.arq}]`);
process.exit(estrito && ruins.length ? 1 : 0);
