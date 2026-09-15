-- =====================================================================
-- Desativa as contas de TESTE da produção (Faixa 1 — inequívocas)
--
-- Para colar no SQL Editor. Roda inteiro numa transação; rodar duas vezes
-- não muda nada.
--
-- O QUE FAZ
-- Marca como INATIVAS as contas criadas para teste. NÃO apaga nada: nenhum
-- DELETE, nenhuma cascata. O dado continua onde está.
--
-- EFEITO REAL DE DESATIVAR (medido no código antes de escrever)
--   · a conta sai da contagem "Empresas Ativas" do painel do Super Admin;
--   · as rotinas noturnas (vigilâncias e alertas do ponto) deixam de
--     processá-la;
--   · NÃO bloqueia login nem esconde os dados — nenhuma política de acesso
--     consulta este campo hoje. Fechar isso é um passo à parte.
--
-- COMO A LISTA FOI MONTADA
-- Só entraram contas com nome inequívoco de teste (ou lixo de digitação)
-- E com zero colaboradores, zero batidas de ponto e zero documentos.
-- Ficaram DE FORA de propósito:
--   · qa-sandbox e qa-sandbox-2 — são os cercados do motor de testes
--     automatizados; desativá-los quebra a bateria de QA;
--   · demo-seguramente — conta usada em demonstração comercial;
--   · toda conta com colaborador, documento ou batida, mesmo com nome de
--     teste: "sem batida de ponto" NÃO quer dizer "sem uso" (há cliente com
--     1.913 colaboradores e nenhuma batida).
--
-- TRAVA DE SEGURANÇA
-- Além da lista, o UPDATE exige zero colaboradores, zero batidas e zero
-- documentos. Se um slug tiver sido digitado errado e cair numa conta com
-- movimento, ela NÃO é desativada e aparece na conferência com aviso.
--
-- COMO DESFAZER
--   UPDATE public.tenants SET ativo = true WHERE slug = '<slug>';
-- A tabela backup_tenants_desativados_20260915 guarda o estado anterior.
-- =====================================================================

SET lock_timeout = '10s';

-- Retrato do estado anterior, antes de qualquer alteração.
CREATE TABLE IF NOT EXISTS public.backup_tenants_desativados_20260915 AS
SELECT t.*, now() AS momento_do_retrato
FROM public.tenants t
WHERE t.slug IN (
  'sony-ltda', 'wallas-monteiro-testes', 'empresa-testes', 'testando-',
  'gustavo-', 'alexandre', 'wallas-ltda', 'wallas-testando-',
  'teste-de-email', 'empresa-teste', 'teste-documento', '1212121212',
  'wallastestando', 'empresa-testes-', 'empresa-modelo'
);

-- Desativa apenas o que está na lista E não tem nenhum sinal de uso.
UPDATE public.tenants t
   SET ativo = false, updated_at = now()
 WHERE t.slug IN (
         'sony-ltda', 'wallas-monteiro-testes', 'empresa-testes', 'testando-',
         'gustavo-', 'alexandre', 'wallas-ltda', 'wallas-testando-',
         'teste-de-email', 'empresa-teste', 'teste-documento', '1212121212',
         'wallastestando', 'empresa-testes-', 'empresa-modelo'
       )
   AND t.ativo = true
   AND NOT EXISTS (SELECT 1 FROM public.admissoes a       WHERE a.tenant_id = t.id)
   AND NOT EXISTS (SELECT 1 FROM public.ponto_marcacoes m WHERE m.tenant_id = t.id)
   AND NOT EXISTS (SELECT 1 FROM public.documentos d      WHERE d.tenant_id = t.id);

-- =====================================================================
-- CONFERÊNCIA — o editor mostra só este resultado
-- Esperado: as 15 contas com situacao = 'desativada'.
-- Qualquer linha como 'NAO desativada' é uma conta com movimento: confira
-- antes de insistir, pode ser um slug errado.
-- =====================================================================
SELECT t.nome  AS cliente,
       t.slug,
       CASE WHEN t.ativo THEN 'NAO desativada — tem movimento, confira'
            ELSE 'desativada' END AS situacao,
       (SELECT count(*) FROM public.admissoes a       WHERE a.tenant_id = t.id) AS colaboradores,
       (SELECT count(*) FROM public.ponto_marcacoes m WHERE m.tenant_id = t.id) AS batidas,
       (SELECT count(*) FROM public.documentos d      WHERE d.tenant_id = t.id) AS documentos
FROM public.tenants t
WHERE t.slug IN (
  'sony-ltda', 'wallas-monteiro-testes', 'empresa-testes', 'testando-',
  'gustavo-', 'alexandre', 'wallas-ltda', 'wallas-testando-',
  'teste-de-email', 'empresa-teste', 'teste-documento', '1212121212',
  'wallastestando', 'empresa-testes-', 'empresa-modelo'
)
ORDER BY t.ativo DESC, t.nome;
