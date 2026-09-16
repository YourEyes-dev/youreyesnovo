-- =========================================================
-- QA AUTH-001 — a tela de login tem DOIS convites válidos
--
-- O caso dizia "links Esqueceu a senha? e Cadastre sua empresa", e o
-- teste de tela cobrava esse texto. Mas a porta livre de cadastro passou
-- a ter chave (SuperAdmin → YourEyes/Empresas) e, fechada — o padrão de
-- hoje —, a tela oferece "Conheça os planos e contrate" no lugar.
--
-- O teste então acusava como defeito um estado legítimo da tela, e
-- deixava a esteira vermelha para todo mundo. O caso passa a descrever
-- os dois estados; o que ele cobra é que o convite EXISTA, não qual dos
-- dois aparece. Quem decide qual é a configuração da porta livre, e ela
-- tem caso proprio no modulo de Empresas.
--
-- Somente documentacao: nao altera tela nem regra.
-- =========================================================

SET lock_timeout = '10s';

UPDATE public.qa_casos_teste
   SET passos = '[{"ordem":1,"acao":"Abrir /login","resultado_esperado":"Título Login; campos E-mail e Senha; botão Entrar; link Esqueceu a senha?; e o convite de conta nova — Cadastre sua empresa com a porta livre aberta, ou Conheça os planos e contrate com ela fechada"}]'::jsonb,
       observacoes = COALESCE(observacoes || ' ', '')
         || 'A porta livre de cadastro tem chave (SuperAdmin → YourEyes/Empresas): fechada, o convite vira "Conheça os planos e contrate". Os dois textos satisfazem este caso.',
       updated_at = now()
 WHERE codigo = 'AUTH-001'
   AND position('Conheça os planos' IN COALESCE(passos::text, '')) = 0;

-- ── Conferencia ───────────────────────────────────────────────────────
SELECT 'caso AUTH-001 descreve os dois convites da tela de login' AS item,
       CASE WHEN position('Conheça os planos' IN passos::text) > 0 THEN 'OK' ELSE 'FALTOU' END AS situacao,
       NULL::text AS erro_tecnico
  FROM public.qa_casos_teste
 WHERE codigo = 'AUTH-001';
