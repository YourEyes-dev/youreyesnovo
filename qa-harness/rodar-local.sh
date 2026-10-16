#!/usr/bin/env bash
# =====================================================================
# Rede de Segurança — sobe um Postgres EFÊMERO, aplica o preflight e
# TODAS as migrations, e (opcional) roda o Motor extraindo os resultados.
#
# Uso:
#   qa-harness/rodar-local.sh            # aplica migrations e roda o Motor
#   qa-harness/rodar-local.sh --so-migrations   # só prova que aplicam
#
# Pré-requisitos: binários do PostgreSQL 16 no PATH (ou em
# /usr/lib/postgresql/16/bin) e permissão de escrita no sharedir de
# extensões (para instalar as extensões-falsas pg_cron/pg_net). Roda como
# usuário comum — NÃO como root (initdb recusa root).
#
# Não toca em rede, não depende de Docker, não alcança staging/produção.
# =====================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$RAIZ/qa-harness"
MIGR="$RAIZ/supabase/migrations"
SO_MIGRATIONS=0
[ "${1:-}" = "--so-migrations" ] && SO_MIGRATIONS=1

# ─── localizar binários do PG ────────────────────────────────────────
if ! command -v initdb >/dev/null 2>&1; then
  for d in /usr/lib/postgresql/16/bin /usr/lib/postgresql/*/bin; do
    [ -x "$d/initdb" ] && export PATH="$d:$PATH" && break
  done
fi
command -v initdb >/dev/null 2>&1 || { echo "::error::initdb não encontrado"; exit 1; }

WORK="$(mktemp -d /tmp/rede-seg.XXXXXX)"
DATA="$WORK/data"; SOCK="$WORK/sock"; PORT="${PGPORT_REDE:-55440}"
mkdir -p "$SOCK"
PSQL=(psql -h "$SOCK" -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1)

limpar() { pg_ctl -D "$DATA" -w stop >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap limpar EXIT

echo "▸ initdb ($WORK)"
initdb -D "$DATA" -U postgres --auth=trust --no-sync >/dev/null

# ─── instalar as extensões-falsas no sharedir ────────────────────────
EXTDIR="$(pg_config --sharedir)/extension"
echo "▸ instalando extensões-falsas pg_cron/pg_net em $EXTDIR"
for f in "$HARNESS"/ext/*; do
  cp "$f" "$EXTDIR/" 2>/dev/null || sudo cp "$f" "$EXTDIR/" 2>/dev/null || true
done
[ -f "$EXTDIR/pg_cron.control" ] && [ -f "$EXTDIR/pg_net.control" ] || {
  echo "::error::extensões-falsas não puderam ser instaladas em $EXTDIR"; exit 1; }

echo "unix_socket_directories='$SOCK'" >> "$DATA/postgresql.conf"
echo "port=$PORT"                      >> "$DATA/postgresql.conf"
echo "fsync=off"                       >> "$DATA/postgresql.conf"
echo "▸ subindo servidor"
pg_ctl -D "$DATA" -l "$WORK/log" -w start >/dev/null

echo "▸ preflight (papéis, schemas, auth/storage stubs)"
"${PSQL[@]}" -f "$HARNESS/preflight.sql" >/dev/null

echo "▸ aplicando migrations (ordem de carimbo)"
n=0; total=$(ls "$MIGR"/*.sql | wc -l | tr -d ' ')
for arq in $(ls "$MIGR"/*.sql | sort); do
  n=$((n+1))
  if ! "${PSQL[@]}" -f "$arq" >/dev/null 2> "$WORK/err"; then
    echo ""
    echo "::error::FALHOU na migration $(basename "$arq") ($n/$total)"
    tail -25 "$WORK/err"
    exit 1
  fi
  [ $((n % 100)) -eq 0 ] && echo "  … $n/$total"
done
echo "✓ todas as $total migrations aplicaram limpo"

if [ "$SO_MIGRATIONS" -eq 1 ]; then
  echo "✓ (--so-migrations) encerrando sem rodar o Motor"
  exit 0
fi

# ─── rodar o Motor em todos os módulos e extrair resultados ──────────
echo "▸ rodando o Motor em todos os módulos"
SAIDA="${REDE_SAIDA:-$RAIZ/qa-harness/resultado-atual.tsv}"
"${PSQL[@]}" -f "$HARNESS/rodar-motor.sql" >/dev/null
"${PSQL[@]}" -t -A -F $'\t' -f "$HARNESS/extrair-resultados.sql" > "$SAIDA"
echo "✓ resultados em $SAIDA ($(wc -l < "$SAIDA" | tr -d ' ') casos)"
