// =====================================================================
// Monta a lista de specs do Cypress para a esteira (separada por vírgula).
//
//   node scripts/cypress-specs.mjs --fumaca        -> specs de cypress/smoke.txt
//   node scripts/cypress-specs.mjs --fatia 2/3     -> a 2ª de 3 fatias equilibradas
//   node scripts/cypress-specs.mjs --soma-fumaca   -> segundos estimados da fumaça
//
// A fatia usa cypress/duracoes.json (balanceamento guloso: o spec mais longo
// vai sempre para a fatia mais vazia). Todos os specs existentes entram em
// exatamente uma fatia; a união das N fatias é a suíte inteira.
// Falha (exit 1) se a fumaça citar spec que não existe — melhor quebrar aqui,
// com a causa dita, do que o Cypress rodar "zero testes" e passar em silêncio.
// =====================================================================

import { readFileSync, readdirSync, existsSync } from "node:fs";

const E2E = "cypress/e2e";
const args = process.argv.slice(2);

const todosOsSpecs = () =>
  readdirSync(E2E).filter((f) => f.endsWith(".cy.ts")).sort().map((f) => `${E2E}/${f}`);

function duracoes() {
  try {
    return JSON.parse(readFileSync("cypress/duracoes.json", "utf8"));
  } catch {
    return {};
  }
}
const seg = (d, spec) => (typeof d[spec] === "number" ? d[spec] : 30);

function fumaca() {
  const linhas = readFileSync("cypress/smoke.txt", "utf8")
    .split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
  const faltando = linhas.filter((l) => !existsSync(l));
  if (faltando.length) {
    console.error(`[fumaça] spec(s) inexistente(s) em cypress/smoke.txt: ${faltando.join(", ")}`);
    process.exit(1);
  }
  if (linhas.length === 0) {
    console.error("[fumaça] cypress/smoke.txt está vazio.");
    process.exit(1);
  }
  return linhas;
}

function fatia(spec) {
  const m = /^([1-9]\d*)\/([1-9]\d*)$/.exec(spec || "");
  if (!m || Number(m[1]) > Number(m[2])) {
    console.error(`[fatia] valor inválido "${spec}". Use N/M, por exemplo 2/3.`);
    process.exit(1);
  }
  const n = Number(m[1]);
  const total = Number(m[2]);
  const d = duracoes();
  const ordenados = todosOsSpecs().sort((a, b) => seg(d, b) - seg(d, a) || a.localeCompare(b));
  const baldes = Array.from({ length: total }, () => ({ s: 0, specs: [] }));
  for (const sp of ordenados) {
    const menor = baldes.reduce((acc, b) => (b.s < acc.s ? b : acc), baldes[0]);
    menor.s += seg(d, sp);
    menor.specs.push(sp);
  }
  return baldes[n - 1].specs;
}

if (args[0] === "--fumaca") {
  console.log(fumaca().join(","));
} else if (args[0] === "--soma-fumaca") {
  const d = duracoes();
  console.log(fumaca().reduce((t, sp) => t + seg(d, sp), 0));
} else if (args[0] === "--fatia") {
  console.log(fatia(args[1]).join(","));
} else {
  console.error("Uso: --fumaca | --soma-fumaca | --fatia N/M");
  process.exit(1);
}
