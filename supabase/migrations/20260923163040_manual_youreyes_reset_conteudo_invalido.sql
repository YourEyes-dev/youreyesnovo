-- Reset do Manual do Sistema apos a correcao do caminho do arquivo.
--
-- A migration 20260923155532 esvaziou system_manual para re-semear do arquivo
-- public/MANUAL_YourEyes.md. Só que a tela buscava o arquivo por um caminho
-- ABSOLUTO ("/MANUAL_YourEyes.md"), fora do subcaminho do site de teste
-- (/youreyesnovo/teste/): o GitHub Pages devolvia sua pagina "Site not found"
-- e essa pagina HTML foi gravada como se fosse o manual.
--
-- A correcao no ManualSistema.tsx passa a buscar sob o base do build e a so
-- gravar conteudo que pareca Markdown. Esta migration limpa qualquer linha
-- invalida (a pagina 404, ou qualquer coisa que nao comece com '#') para que a
-- tela, ja corrigida, re-semeie a versao boa a partir do arquivo.
--
-- Idempotente: se nao houver linha invalida, nao apaga nada.

DELETE FROM public.system_manual
WHERE content IS NULL
   OR btrim(content) NOT LIKE '#%';
