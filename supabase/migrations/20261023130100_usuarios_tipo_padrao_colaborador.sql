-- ============================================================================
-- TIPO PADRAO = COLABORADOR (menor acesso por omissao)
--
-- usuarios_base.tipo_usuario e usuario_vinculos.tipo_vinculo tinham DEFAULT 'gestor'. Quem criava um usuario sem
-- escolher o tipo entrava como gestor: perfil "Gestor (padrao)" (acesso amplo a 44 modulos) e papel de gestao.
-- Decisao do dono do produto (10/2026): sem tipo definido, a pessoa entra como COLABORADOR (perfil Colaborador
-- padrao, so autosservico); o RH corrige depois, em vez do contrario.
--
-- Conferido: os 68 INSERT em usuarios_base das migrations e os seeds informam o tipo explicitamente, entao a mudanca
-- do padrao da coluna nao altera nenhum caminho existente; vale so para INSERT que OMITA a coluna (SQL manual, scripts).
-- A tela de Novo Usuario passa a sugerir "colaborador" (NovoUsuarioDialog). Linhas existentes NAO mudam.
-- Idempotente; so troca o valor padrao das colunas.
-- ============================================================================

SET lock_timeout = '10s';

DO $tp$
BEGIN
  IF to_regclass('public.usuarios_base') IS NOT NULL THEN
    ALTER TABLE public.usuarios_base ALTER COLUMN tipo_usuario SET DEFAULT 'colaborador';
    RAISE NOTICE 'usuarios_base.tipo_usuario: padrao agora colaborador.';
  END IF;
  IF to_regclass('public.usuario_vinculos') IS NOT NULL THEN
    ALTER TABLE public.usuario_vinculos ALTER COLUMN tipo_vinculo SET DEFAULT 'colaborador';
    RAISE NOTICE 'usuario_vinculos.tipo_vinculo: padrao agora colaborador.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ATENCAO: padrao de tipo nao alterado: %', SQLERRM;
END $tp$;
