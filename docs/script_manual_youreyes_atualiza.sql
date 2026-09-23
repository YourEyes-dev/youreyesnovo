-- =====================================================================
-- SCRIPT DE ENTREGA — Atualizacao do Manual do Sistema (YourEyes)
-- Alvo: SQL Editor do projeto de PRODUCAO
-- =====================================================================
--
-- CONTEXTO
-- A tela /admin/manual le o conteudo da tabela public.system_manual. Quando a
-- tabela nao tem um manual valido, o app carrega o texto do arquivo
-- public/MANUAL_YourEyes.md (servido pelo proprio site, sob o caminho do build)
-- e o re-semeia. O manual novo, revisado por modulo, ja esta nesse arquivo, e a
-- tela ja foi corrigida para buscar o arquivo no caminho certo e so gravar
-- conteudo que seja Markdown de verdade.
--
-- ORDEM OBRIGATORIA (dois gestos manuais):
--   1) PRIMEIRO clicar Publicar no Lovable. So assim a producao passa a servir
--      a versao NOVA do arquivo E o codigo corrigido da tela. Rodar este script
--      antes disso faria a tela re-semear a versao antiga.
--   2) DEPOIS colar e rodar este script no SQL Editor de producao. Ele guarda o
--      conteudo atual em uma tabela de backup e apaga apenas linhas INVALIDAS
--      (vazias ou que nao comecem com '#', ex.: uma pagina de erro do host).
--      Se a producao ja tiver um manual valido gravado e voce quiser trocar
--      pela versao do arquivo, troque o filtro do DELETE por um TRUE (ver nota
--      no fim) para limpar tudo e forcar o re-semeio.
--
-- SEGURANCA
-- O script guarda as linhas atuais antes de apagar (a producao nao tem PITR).
-- Rodar duas vezes nao quebra nem duplica o backup (IF NOT EXISTS).
-- =====================================================================

-- 1) Backup do conteudo atual (nao sobrescreve um backup ja existente do dia)
CREATE TABLE IF NOT EXISTS public.backup_system_manual_20260923 AS
SELECT * FROM public.system_manual;

-- 2) Remove apenas conteudo invalido, para a tela re-semear do arquivo publicado
DELETE FROM public.system_manual
WHERE content IS NULL
   OR btrim(content) NOT LIKE '#%';

-- 3) Conferencia final (o SQL Editor mostra apenas o ultimo resultado)
SELECT
  (SELECT count(*) FROM public.system_manual)                                  AS linhas_manual_agora,
  (SELECT count(*) FROM public.system_manual WHERE btrim(content) LIKE '#%')   AS linhas_validas,
  (SELECT count(*) FROM public.backup_system_manual_20260923)                  AS linhas_no_backup,
  'Publique no Lovable ANTES; depois abra /admin/manual como superadmin para re-semear a versao nova a partir do arquivo.' AS instrucao;

-- =====================================================================
-- TROCAR UM MANUAL VALIDO PELO ARQUIVO (opcional): substitua o passo 2 por
--   DELETE FROM public.system_manual;
-- para limpar tudo e forcar o re-semeio a partir do arquivo publicado.
--
-- COMO DESFAZER (restaurar o manual anterior), se necessario:
--   INSERT INTO public.system_manual
--   SELECT * FROM public.backup_system_manual_20260923;
-- =====================================================================
