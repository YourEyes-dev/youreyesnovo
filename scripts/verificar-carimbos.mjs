#!/usr/bin/env node
/**
 * Guarda: carimbo de migration é ÚNICO.
 *
 * Duas migrations com o mesmo carimbo quebram a esteira inteira, e o erro que
 * aparece não ajuda ninguém:
 *   ERROR: duplicate key value violates unique constraint "schema_migrations_pkey"
 *   Key (version)=(20260916180000) already exists.
 * Ele não diz QUAIS arquivos colidiram, e a primeira migration da leva já foi
 * registrada — então a esteira fica vermelha em TODA entrega seguinte, de todo
 * mundo, até alguém descobrir a causa. Aconteceu em 16/09/2026 com três
 * arquivos no mesmo carimbo, de três frentes diferentes.
 *
 * Esta guarda roda antes do db push e falha na hora, dizendo os nomes.
 */
import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const PASTA = join(dirname(fileURLToPath(import.meta.url)), "..", "supabase", "migrations");

const porCarimbo = new Map();
for (const arquivo of readdirSync(PASTA)) {
  if (!arquivo.endsWith(".sql")) continue;
  const carimbo = arquivo.slice(0, 14);
  if (!/^\d{14}$/.test(carimbo)) {
    console.error(`[carimbos] ERRO: "${arquivo}" não começa com um carimbo de 14 dígitos.`);
    process.exit(1);
  }
  porCarimbo.set(carimbo, [...(porCarimbo.get(carimbo) ?? []), arquivo]);
}

// Aviso (não reprova): a MESMA migration aparecendo sob dois carimbos.
// Acontece quando duas frentes desfazem a mesma colisão ao mesmo tempo, cada
// uma escolhendo um carimbo. As duas aplicam, e como o conteúdo costuma ser
// idempotente nada quebra — mas fica uma cópia a mais para sempre, e quem ler
// depois não sabe qual vale. Não reprova porque, quando as duas já foram
// aplicadas, apagar uma é decisão de quem conhece o histórico.
const porNome = new Map();
for (const [carimbo, arquivos] of porCarimbo) {
  for (const a of arquivos) {
    const nome = a.slice(15);
    porNome.set(nome, [...(porNome.get(nome) ?? []), a]);
  }
}
const repetidas = [...porNome.entries()].filter(([, arquivos]) => arquivos.length > 1);
if (repetidas.length > 0) {
  console.warn("[carimbos] aviso: a mesma migration aparece sob mais de um carimbo:");
  for (const [nome, arquivos] of repetidas) {
    console.warn(`  ${nome}`);
    for (const a of arquivos) console.warn(`    · ${a}`);
  }
  console.warn("  Se as duas ja foram aplicadas, nao ha o que consertar no banco —");
  console.warn("  mas vale apagar a redundante para quem ler depois saber qual vale.\n");
}

const colisoes = [...porCarimbo.entries()].filter(([, arquivos]) => arquivos.length > 1);

if (colisoes.length === 0) {
  console.log(`[carimbos] ok — ${porCarimbo.size} migrations, nenhum carimbo repetido.`);
  process.exit(0);
}

console.error("[carimbos] CARIMBO REPETIDO — a esteira quebraria no db push:\n");
for (const [carimbo, arquivos] of colisoes) {
  console.error(`  ${carimbo}`);
  for (const a of arquivos) console.error(`    · ${a}`);
}
console.error(
  "\nComo resolver: renomeie a(s) migration(is) AINDA NÃO APLICADA(S) para um" +
  "\ncarimbo livre, mantendo o conteúdo. A que já foi aplicada no staging tem de" +
  "\nficar com o carimbo dela — renomeá-la faria o banco tentar aplicá-la de novo."
);
process.exit(1);
