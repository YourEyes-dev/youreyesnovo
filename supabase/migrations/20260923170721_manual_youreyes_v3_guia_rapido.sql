-- Atualizacao do Manual do Usuario (YourEyes) — versao com "Como utilizar" por modulo.
--
-- A tela /admin/manual le o conteudo de public.system_manual e, quando a tabela
-- esta vazia, re-semeia do arquivo public/MANUAL_YourEyes.md (ja atualizado neste
-- repositorio: passo a passo por modulo, sem os gatilhos de video).
--
-- O conteudo atual gravado em staging e valido (comeca com '#'), mas e a versao
-- anterior — por isso a tela nao o substituiria sozinha. Este DELETE esvazia a
-- tabela para forcar o re-semeio da versao nova a partir do arquivo.
--
-- Idempotente: rodar de novo apenas esvazia de novo (DELETE sem linhas e no-op).

DELETE FROM public.system_manual;
