-- ============================================================================
-- FERIAS-016 — sinalizacao de estudante menor de 18 — ENTREGA producao.
--
-- O estudante menor de 18 tem direito a fazer coincidir as ferias com as
-- escolares (CLT art. 136, §2º). Sem um campo que registre a condicao de
-- estudante, a programacao de ferias nao tem como sinalizar esse direito.
--
-- Correcao minima: flag de estudante no cadastro da admissao (a tela de
-- programacao passa a poder alertar quando um menor estudante e programado
-- fora do recesso escolar). So CRIA coluna nova (metadados, sem rewrite),
-- sem tocar dado existente. Idempotente.
-- ============================================================================

ALTER TABLE public.admissoes
  ADD COLUMN IF NOT EXISTS estudante boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.admissoes.estudante IS
  'FERIAS-016: colaborador estudante — menor de 18 estudante tem direito a coincidir ferias com as escolares (CLT art. 136, §2º).';

-- Conferencia (leve)
SELECT 'FERIAS-016' AS caso,
       (public.qa_executar_descartavel('qa_caso_ferias_016')).situacao::text AS situacao;
