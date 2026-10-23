-- ============================================================================
-- ENTREGA — Tipo padrao = colaborador (menor acesso por omissao)
-- Cole no SQL Editor (TESTE e HOMOLOGACAO primeiro; depois PRODUCAO). Idempotente. So troca o valor padrao de 2 colunas;
-- usuarios ja existentes NAO mudam. A tela de Novo Usuario (codigo) passa a sugerir colaborador quando o app for publicado.
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

-- ── Conferencia ─────────────────────────────────────────────────────────────
SELECT
  (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE d.adrelid = 'public.usuarios_base'::regclass AND a.attname = 'tipo_usuario')   AS padrao_tipo_usuario,
  (SELECT pg_get_expr(d.adbin, d.adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE d.adrelid = 'public.usuario_vinculos'::regclass AND a.attname = 'tipo_vinculo') AS padrao_tipo_vinculo;
-- Esperado: 'colaborador'::usuario_tipo nas duas.
-- DESFAZER: ALTER TABLE public.usuarios_base ALTER COLUMN tipo_usuario SET DEFAULT 'gestor'; ALTER TABLE public.usuario_vinculos ALTER COLUMN tipo_vinculo SET DEFAULT 'gestor';
