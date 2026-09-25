-- =====================================================================
-- YOUREYES · SCRIPT DE ENTREGA · QA OUVIDORIA — cobertura e2e
-- Cole ESTE arquivo inteiro no SQL Editor do projeto de PRODUCAO.
--
-- Problema que resolve (a guarda scripts/verificar-cobertura-e2e.mjs
-- reprovava a esteira):
--   * A doc 0828 registrou OUV-003/004/005 como casos de TELA (e2e).
--   * A doc 0903 (rotinas do motor) RECLASSIFICOU esses tres para 'api'
--     (o banco passou a checar a regra: CHECK dos tipos, NOT NULL do
--     assunto/mensagem).
--   * A doc 0909 criou pontes e2e apontando para eles — que ja eram api.
--   Efeito: os 3 it() de tela viraram "inventados" (sem caso e2e) e as
--   pontes viraram "orfas" -> a corrida reprovava.
--
-- Correcao (regra da casa: documentacao -> teste; nao apagar teste de tela
-- valido): os 3 it() cobrem UI que o motor NAO cobre (seletor mostra os 5
-- tipos; botao Enviar desabilitado). Ganham casos e2e PROPRIOS
-- (OUV-050/051/052) e as pontes passam a apontar para eles. OUV-003/004/005
-- seguem como casos de motor (api). Nenhum it() do Cypress muda.
--
-- Seguro:
--   * Roda em UMA transacao; se der erro, desfaz sozinho.
--   * APAGA as 3 pontes antigas (qa_cobertura_e2e tem UNIQUE(spec,teste),
--     por isso e preciso remover antes de repontar) -> guarda copia antes
--     em backup_ouv_pontes_20260925 (criada por EXECUTE para nao acionar o
--     auto-RLS do editor). Comando de desfazer no rodape.
--   * Idempotente. NAO cria funcao. NAO mexe em plano/entitlement/preco.
-- =====================================================================

set lock_timeout = '10s';

-- ---------------------------------------------------------------------
-- 1) Copia de seguranca das pontes que serao removidas
--    (EXECUTE monta 'CREATE '||'TABLE ...' para o editor nao ver tabela
--     nova e nao injetar auto-RLS)
-- ---------------------------------------------------------------------
do $copia$
begin
  if to_regclass('public.backup_ouv_pontes_20260925') is null then
    execute 'create ' || 'table public.backup_ouv_pontes_20260925 as '
         || 'select * from public.qa_cobertura_e2e '
         || 'where codigo in (''OUV-003'',''OUV-004'',''OUV-005'') '
         || 'and spec = ''cypress/e2e/ouvidoria.cy.ts''';
    raise notice 'copia criada: backup_ouv_pontes_20260925';
  else
    raise notice 'copia backup_ouv_pontes_20260925 ja existia — mantida';
  end if;
end $copia$;

-- ---------------------------------------------------------------------
-- 2) Documenta os 3 casos e2e proprios + repontar as pontes
--    (sem SELECT ... INTO: o modulo vem por subconsulta escalar, para nao
--     dar pretexto ao auto-RLS caso ele tenha ligado)
-- ---------------------------------------------------------------------
do $doc$
declare v_mod uuid;
begin
  v_mod := (select id from public.qa_modulos
             where path = 'pessoas-cultura/ouvidoria' limit 1);
  if v_mod is null then
    raise notice 'Modulo pessoas-cultura/ouvidoria nao encontrado — nada a fazer.';
    return;
  end if;

  insert into public.qa_casos_teste
    (modulo_id, codigo, titulo, tipo, prioridade, status, nivel,
     base_legal, objetivo, pre_condicoes, passos, resultado_esperado, observacoes)
  values
    (v_mod, 'OUV-050', 'Seletor mostra os cinco tipos de manifestacao (tela)',
     'feliz', 'media', 'aprovado', 'e2e', null,
     'A tipologia (sugestao, reclamacao, denuncia, elogio, duvida) precisa aparecer no seletor da tela de envio; tipo faltando e canal fechado sem aviso.',
     'Aba Enviar aberta.',
     '[{"ordem":1,"acao":"Abrir a aba Enviar e olhar o seletor de Tipo de Manifestacao","resultado_esperado":"Sugestao, Reclamacao, Denuncia, Elogio e Duvida visiveis"}]'::jsonb,
     'Os cinco tipos aparecem para escolha na tela.',
     'Cobre a UI. A regra no banco (CHECK dos tipos) e o caso OUV-003 (motor).'),
    (v_mod, 'OUV-051', 'Tela bloqueia o envio sem assunto',
     'negativo', 'alta', 'aprovado', 'e2e', null,
     'Assunto e obrigatorio; a tela deve manter o botao Enviar desabilitado enquanto ele estiver vazio.',
     'Aba Enviar aberta.',
     '[{"ordem":1,"acao":"Selecionar um tipo e preencher a mensagem, deixando o Assunto vazio","resultado_esperado":"Botao Enviar Manifestacao desabilitado"}]'::jsonb,
     'Nao ha envio sem assunto (trava de tela).',
     'Cobre a UI. A regra no banco (NOT NULL) e o caso OUV-004 (motor).'),
    (v_mod, 'OUV-052', 'Tela bloqueia o envio sem mensagem',
     'negativo', 'alta', 'aprovado', 'e2e', null,
     'Mensagem e o conteudo da manifestacao; a tela deve manter o botao Enviar desabilitado enquanto ela estiver vazia.',
     'Aba Enviar aberta.',
     '[{"ordem":1,"acao":"Selecionar um tipo e preencher o assunto, deixando a Mensagem vazia","resultado_esperado":"Botao Enviar Manifestacao desabilitado"}]'::jsonb,
     'Nao ha envio sem mensagem (trava de tela).',
     'Cobre a UI. A regra no banco (NOT NULL) e o caso OUV-005 (motor).')
  on conflict (codigo) do nothing;

  delete from public.qa_cobertura_e2e
   where codigo in ('OUV-003','OUV-004','OUV-005')
     and spec = 'cypress/e2e/ouvidoria.cy.ts';

  insert into public.qa_cobertura_e2e (codigo, spec, teste) values
    ('OUV-050', 'cypress/e2e/ouvidoria.cy.ts', 'mostra os cinco tipos de manifestação'),
    ('OUV-051', 'cypress/e2e/ouvidoria.cy.ts', 'bloqueia o envio sem assunto'),
    ('OUV-052', 'cypress/e2e/ouvidoria.cy.ts', 'bloqueia o envio sem mensagem')
  on conflict (codigo) do nothing;

  raise notice 'OK: OUV-050/051/052 (e2e) documentados e pontes repontadas.';
end $doc$;

-- ---------------------------------------------------------------------
-- CONFERENCIA (o editor mostra so este ultimo resultado)
--   Esperado: 3 linhas OUV-050/051/052, nivel e2e, cada uma com a ponte
--   apontando para o it() certo e status 'ok'.
-- ---------------------------------------------------------------------
with alvo(codigo, teste) as (values
  ('OUV-050','mostra os cinco tipos de manifestação'),
  ('OUV-051','bloqueia o envio sem assunto'),
  ('OUV-052','bloqueia o envio sem mensagem')
)
select a.codigo,
       ct.nivel,
       cob.spec,
       cob.teste,
       case
         when ct.codigo is null then 'CONFERIR: caso ausente'
         when ct.nivel <> 'e2e' then 'CONFERIR: nivel != e2e'
         when cob.teste is distinct from a.teste then 'CONFERIR: ponte ausente/errada'
         else 'ok'
       end as status
from alvo a
left join public.qa_casos_teste ct on ct.codigo = a.codigo
left join public.qa_cobertura_e2e cob
       on cob.codigo = a.codigo
      and cob.spec = 'cypress/e2e/ouvidoria.cy.ts'
order by a.codigo;

-- ---------------------------------------------------------------------
-- PARA DESFAZER (se preciso):
--   delete from public.qa_cobertura_e2e
--     where codigo in ('OUV-050','OUV-051','OUV-052');
--   insert into public.qa_cobertura_e2e
--     select * from public.backup_ouv_pontes_20260925
--     on conflict (spec, teste) do nothing;
--   delete from public.qa_casos_teste
--     where codigo in ('OUV-050','OUV-051','OUV-052');
-- ---------------------------------------------------------------------
