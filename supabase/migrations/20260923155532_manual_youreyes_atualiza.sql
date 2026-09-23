-- Atualizacao do Manual do Sistema (YourEyes)
--
-- A tela /admin/manual (ManualSistema.tsx) le o conteudo da tabela
-- public.system_manual. Quando a tabela esta vazia, o app recarrega o texto
-- do arquivo estatico public/MANUAL_YourEyes.md e o re-semeia.
--
-- Esta migration esvazia system_manual para que o ambiente de teste passe a
-- exibir a versao nova do manual (revisada por modulo, ja publicada no arquivo
-- MANUAL_YourEyes.md deste repositorio). Nao ha perda de dado relevante: o
-- conteudo antigo estava desatualizado e a fonte da verdade e o arquivo.
--
-- Idempotente: rodar de novo apenas esvazia novamente (DELETE sem linhas e no-op).

DELETE FROM public.system_manual;
