-- Corrige CEN-e4653a (incidente de produção pego pela Sentinela) / caso de QA JOR-AJ-001.
-- Sintoma: ao retificar uma marcação, o gestor recebia erro técnico e a operação falhava.
-- Causa: a retificação direta do gestor (RPC ponto_retificar_marcacao, migration
--        20260807184604) grava tipo_ajuste = 'retificacao' em public.ponto_ajustes,
--        mas o CHECK da coluna (definido em 20260122115807) só aceitava
--        'inclusao','correcao','justificativa','abono' — violando
--        ponto_ajustes_tipo_ajuste_check.
-- Correção: ampliar o CHECK para aceitar 'retificacao'. É um tipo legítimo, gravado
--           como status 'aprovado' e com trilha em ponto_audit_log; manter o rótulo
--           próprio preserva a auditoria (melhor que rebaixar para 'correcao').
-- Seguro: ampliar um CHECK nunca viola linha existente (o conjunto antigo é subconjunto
--         do novo) e hoje não há linhas 'retificacao' (sempre falhavam ao inserir).

SET lock_timeout = '10s';

ALTER TABLE public.ponto_ajustes
  DROP CONSTRAINT IF EXISTS ponto_ajustes_tipo_ajuste_check;

ALTER TABLE public.ponto_ajustes
  ADD CONSTRAINT ponto_ajustes_tipo_ajuste_check
  CHECK (tipo_ajuste IN ('inclusao', 'correcao', 'justificativa', 'abono', 'retificacao'));
