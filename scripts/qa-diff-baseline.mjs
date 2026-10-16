#!/usr/bin/env node
// =====================================================================
// Rede de Segurança — diff DIFERENCIAL do Motor.
//
// Compara o resultado de uma passada do Motor (no banco efêmero) com a
// LINHA DE BASE versionada no repositório, e REPROVA só o que regrediu.
//
// Contrato (o que importa quando o sistema muda toda hora):
//   REGRESSÃO (reprova) = um caso que ESTAVA "passou" na baseline e agora
//                         está "falhou", "erro", "nao_implementado" ou
//                         sumiu. Ou seja: algo que funcionava parou de
//                         funcionar, ou perdeu a cobertura.
//   MELHOROU (avisa)     = "falhou"/"erro" -> "passou". Sugere atualizar a
//                         baseline (npm run qa:baseline) para travar o ganho.
//   NOVO / REMOVIDO / outras transições = informativo, nunca reprova.
//
// "Tudo verde" é inatingível (há lacunas conhecidas de estrutura). O alvo
// certo é: NADA que estava verde ficou vermelho.
//
// Uso: node scripts/qa-diff-baseline.mjs [baseline.tsv] [atual.tsv]
// Sai 1 se houver regressão; 0 caso contrário.
// =====================================================================
import { readFileSync } from 'node:fs';

const BASE = process.argv[2] || 'qa-harness/baseline.tsv';
const ATUAL = process.argv[3] || 'qa-harness/resultado-atual.tsv';

function carregar(caminho) {
  const mapa = new Map();
  let texto;
  try {
    texto = readFileSync(caminho, 'utf8');
  } catch (e) {
    console.error(`::error::não consegui ler ${caminho}: ${e.message}`);
    process.exit(2);
  }
  for (const linha of texto.split('\n')) {
    const l = linha.trim();
    if (!l || l.startsWith('#')) continue;
    const [codigo, situacao] = l.split('\t');
    if (codigo && situacao) mapa.set(codigo, situacao);
  }
  return mapa;
}

const base = carregar(BASE);
const atual = carregar(ATUAL);

const REGREDIDOS = ['falhou', 'erro', 'nao_implementado'];
const regressoes = [];
const melhoras = [];
const novos = [];
const removidos = [];

for (const [codigo, sitBase] of base) {
  const sitAtual = atual.get(codigo);
  if (sitBase === 'passou') {
    if (sitAtual === undefined) {
      regressoes.push([codigo, 'passou', 'SUMIU (caso removido/renomeado)']);
    } else if (REGREDIDOS.includes(sitAtual)) {
      regressoes.push([codigo, 'passou', sitAtual]);
    }
  } else if ((sitBase === 'falhou' || sitBase === 'erro') && sitAtual === 'passou') {
    melhoras.push([codigo, sitBase, 'passou']);
  }
}
for (const [codigo, sitAtual] of atual) {
  if (!base.has(codigo)) novos.push([codigo, sitAtual]);
}
for (const [codigo] of base) {
  if (!atual.has(codigo)) removidos.push(codigo);
}

const fmt = (linhas) => linhas.map(([c, de, para]) => `    ${c.padEnd(14)} ${de} → ${para}`).join('\n');

console.log('─'.repeat(64));
console.log(`Rede de Segurança — diff contra a baseline`);
console.log(`  baseline: ${base.size} casos   |   agora: ${atual.size} casos`);
console.log('─'.repeat(64));

if (melhoras.length) {
  console.log(`\n✓ ${melhoras.length} caso(s) MELHORARAM (passaram a verde):`);
  console.log(fmt(melhoras));
  console.log(`  → se for de propósito, trave o ganho: npm run qa:baseline`);
}
if (novos.length) {
  console.log(`\n＋ ${novos.length} caso(s) NOVOS (não estavam na baseline) — informativo.`);
}
if (removidos.length) {
  const soInfo = removidos.filter((c) => base.get(c) !== 'passou');
  if (soInfo.length) console.log(`\n－ ${soInfo.length} caso(s) removidos que não eram verdes — informativo.`);
}

if (regressoes.length) {
  console.log(`\n::error::✗ ${regressoes.length} REGRESSÃO(ÕES) — algo que estava verde quebrou:`);
  console.log(fmt(regressoes));
  console.log(`\nReprovado. Cada linha acima é um caso do Motor que passava e parou de passar.`);
  console.log(`Investigue com o campo "obtido" do caso (traz o achado + a correção sugerida).`);
  console.log(`Se a mudança de estado for legítima e aprovada, regenere: npm run qa:baseline`);
  process.exit(1);
}

console.log(`\n✓ Nenhuma regressão. Nada que estava verde ficou vermelho.`);
process.exit(0);
