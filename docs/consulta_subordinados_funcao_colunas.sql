-- SOMENTE LEITURA — a funcao que define "subordinado direto" bate com as colunas reais?
-- Mostra: (1) se admissoes tem departamento_id e departamento (texto); (2) se departamentos tem gestor_admissao_id;
-- (3) se o corpo da funcao ye_cpfs_subordinados_diretos ainda cita s.departamento_id (que quebraria na execucao).
SELECT
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='departamento_id')   AS admissoes_tem_departamento_id,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admissoes' AND column_name='departamento')      AS admissoes_tem_departamento_texto,
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='departamentos' AND column_name='gestor_admissao_id') AS departamentos_tem_gestor_admissao_id,
  position('s.departamento_id' IN pg_get_functiondef('public.ye_cpfs_subordinados_diretos(uuid)'::regprocedure)) > 0 AS funcao_cita_departamento_id;
