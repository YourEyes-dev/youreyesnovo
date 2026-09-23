-- =====================================================================
-- SCRIPT DE ENTREGA — Atualizacao do Manual do Sistema (YourEyes)
-- Alvo: SQL Editor do projeto de PRODUCAO
-- =====================================================================
--
-- CONTEXTO
-- A tela /admin/manual le o conteudo da tabela public.system_manual. Quando a
-- tabela esta vazia, o app recarrega o texto do arquivo public/MANUAL_YourEyes.md
-- (servido pelo proprio site) e o re-semeia. O manual novo, revisado por modulo,
-- ja esta nesse arquivo.
--
-- ORDEM OBRIGATORIA (dois gestos manuais):
--   1) PRIMEIRO clicar Publicar no Lovable. So assim o site de producao passa a
--      servir a versao NOVA do arquivo MANUAL_YourEyes.md. Se rodar este script
--      antes de publicar, o app re-semeia a versao ANTIGA do arquivo.
--   2) DEPOIS colar e rodar este script no SQL Editor de producao. Ele guarda o
--      conteudo atual em uma tabela de backup e esvazia system_manual, para que
--      a proxima abertura de /admin/manual (por um superadmin) re-semeie a versao
--      nova a partir do arquivo publicado.
--
-- SEGURANCA
-- O script guarda as linhas atuais antes de apagar (a producao nao tem PITR).
-- Rodar duas vezes nao quebra nem duplica o backup (IF NOT EXISTS).
-- =====================================================================

-- 1) Backup do conteudo atual (nao sobrescreve um backup ja existente do dia)
CREATE TABLE IF NOT EXISTS public.backup_system_manual_20260923 AS
SELECT * FROM public.system_manual;

-- 2) Esvazia a tabela para forcar o re-semeio a partir do arquivo publicado
DELETE FROM public.system_manual;

-- 3) Conferencia final (o SQL Editor mostra apenas o ultimo resultado)
SELECT
  (SELECT count(*) FROM public.system_manual)                    AS linhas_manual_agora,
  (SELECT count(*) FROM public.backup_system_manual_20260923)    AS linhas_no_backup,
  'Esvaziado. Publique no Lovable ANTES, depois abra /admin/manual como superadmin para re-semear a versao nova.' AS instrucao;

-- =====================================================================
-- COMO DESFAZER (restaurar o manual anterior), se necessario:
--   INSERT INTO public.system_manual
--   SELECT * FROM public.backup_system_manual_20260923;
-- =====================================================================
