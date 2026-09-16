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
