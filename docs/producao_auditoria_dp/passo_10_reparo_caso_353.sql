-- ============================================================================
-- REPARO — o caso PONTO-353 na bancada de testes da producao
--
-- POR QUE ESTE PASSO EXISTE
-- O passo 03 aplicou a correcao da tolerancia com sucesso ("regua unica
-- aplicada | OK"), mas a conferencia dele acusou:
--
--     casos de teste | 1 de 2 documentados; 1 com rotina ativa | PENDENTE
--
-- O motivo nao tem nada a ver com o calculo: o caso PONTO-353 nunca chegou a
-- esta base. Ele nasceu numa migration que ficou de fora das 16 partes
-- entregues em 08/2026, e o passo 03 tentou ATUALIZAR um caso que nao existia
-- — um UPDATE em zero linhas nao da erro, so nao faz nada.
--
-- A correcao do calculo esta aplicada e conferida. O que falta e o registro na
-- Documentacao de testes, para o PONTO-353 aparecer na lista e rodar na
-- bateria como roda no ambiente de teste.
--
-- O QUE ESTE ARQUIVO FAZ
-- Grava o caso PONTO-353 com o texto ja reescrito (a fronteira da sobra e a
-- mesma do atraso) e registra a rotina dele no motor. Se o caso ja existir,
-- so atualiza o texto. Idempotente: rodar duas vezes nao duplica.
--
-- NAO MEXE EM CALCULO NENHUM e nao toca em dado de colaborador: escreve
-- apenas nas tabelas da bancada de testes (qa_casos_teste, qa_implementacoes).
-- ============================================================================

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) O caso, com o texto reescrito
-- ---------------------------------------------------------------------
INSERT INTO public.qa_casos_teste
  (codigo, modulo_id, titulo, objetivo, tipo, nivel, prioridade, status,
   base_legal, passos, disposicao, observacoes)
SELECT
  'PONTO-353',
  m.id,
  'Fronteira da sobra é a mesma do atraso: 5 min absorve, 6 computa inteiro',
  'O art. 58, §1º é simétrico: as variações de até 5 minutos por marcação, observado o '
  || 'limite de 10 minutos diários, não são descontadas NEM computadas como extra. Não existe '
  || 'na lei um teto para o atraso e outro, maior, para a sobra. Ultrapassado o limite, '
  || 'computa-se a totalidade (Súmula 366), para os dois lados.',
  'feliz',
  'api',
  'critica',
  'aprovado',
  'CLT art. 58, §1º; Súmula 366 do TST',
  jsonb_build_array(
    jsonb_build_object('ordem', 1,
      'acao', 'Apurar um dia com exatos 5 minutos a MAIS que a jornada',
      'esperado', 'Saldo 0 — dentro do limite legal'),
    jsonb_build_object('ordem', 2,
      'acao', 'Apurar um dia com 6 minutos a MAIS que a jornada',
      'esperado', 'Saldo +6 INTEIRO — estourou o limite, computa-se a totalidade')
  ),
  'em_triagem',
  'Reescrito em 01/09/2026. A versão anterior documentava "+10 no dia não computa", que era '
  || 'justamente a assimetria apontada pela auditoria de fechamento: o atraso de 6 min era '
  || 'descontado e a sobra de 10 min não era paga. A simetria é provada pelo PONTO-471.'
FROM public.qa_modulos m
WHERE m.path = 'jornada-rotina/ponto'
ON CONFLICT (codigo) DO UPDATE SET
  titulo      = EXCLUDED.titulo,
  objetivo    = EXCLUDED.objetivo,
  base_legal  = EXCLUDED.base_legal,
  passos      = EXCLUDED.passos,
  observacoes = EXCLUDED.observacoes;

-- ---------------------------------------------------------------------
-- 2) A rotina, registrada no motor
-- ---------------------------------------------------------------------
INSERT INTO public.qa_implementacoes (codigo, funcao_sql, ativo)
SELECT 'PONTO-353', 'qa_caso_ponto_353', true
WHERE EXISTS (SELECT 1 FROM public.qa_casos_teste WHERE codigo = 'PONTO-353')
  AND to_regprocedure('public.qa_caso_ponto_353()') IS NOT NULL
ON CONFLICT (codigo) DO UPDATE SET funcao_sql = EXCLUDED.funcao_sql, ativo = true;

-- ============================================================================
-- CONFERENCIA — o SQL Editor mostra apenas o ultimo resultado.
-- Esperado: 2 de 2 documentados, 2 com rotina ativa, OK.
-- ============================================================================
SELECT
  (SELECT count(*) FROM public.qa_casos_teste
    WHERE codigo IN ('PONTO-353', 'PONTO-471'))::text || ' de 2 documentados'   AS casos,
  (SELECT count(*) FROM public.qa_implementacoes
    WHERE codigo IN ('PONTO-353', 'PONTO-471') AND ativo)::text
    || ' com rotina ativa'                                                       AS rotinas,
  CASE WHEN to_regprocedure('public.qa_caso_ponto_353()') IS NULL
       THEN 'a rotina qa_caso_ponto_353 nao existe nesta base'
       ELSE 'a rotina existe' END                                                AS rotina_353,
  CASE
    WHEN (SELECT count(*) FROM public.qa_casos_teste
           WHERE codigo IN ('PONTO-353', 'PONTO-471')) = 2
     AND (SELECT count(*) FROM public.qa_implementacoes
           WHERE codigo IN ('PONTO-353', 'PONTO-471') AND ativo) = 2
      THEN 'OK'
    WHEN NOT EXISTS (SELECT 1 FROM public.qa_modulos WHERE path = 'jornada-rotina/ponto')
      THEN 'PENDENTE: o modulo jornada-rotina/ponto nao existe na Documentacao de testes desta base'
    ELSE 'PENDENTE: me envie este resultado'
  END                                                                            AS erro_tecnico;
