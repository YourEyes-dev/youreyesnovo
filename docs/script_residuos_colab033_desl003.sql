-- ============================================================================
-- Residuos do motor — COLAB-033 e DESL-003 — ENTREGA producao (SO DDL).
--
-- Diagnostico: nos dois ambientes falta o CONTROLE (a rotina de QA existe):
--  - COLAB-033: indice unico de CPF NORMALIZADO em usuarios_base (mesma pessoa
--    com CPF pontuado x cru escapava do indice cru). Controle = o indice.
--  - DESL-003: gatilho que barra dispensa sem justa causa com afastamento ativo
--    (contrato suspenso, CLT art. 476). Controle = o gatilho.
--
-- So DDL (funcao + gatilho + indice), curto. A CONFERENCIA (roda as rotinas)
-- esta em docs/conferencia_residuos.sql, para rodar DEPOIS em transacao propria
-- (nao juntar — evita deadlock). Idempotente.
--
-- Legado: o indice de COLAB-033 valida as linhas existentes; se houver a mesma
-- pessoa duplicada por CPF, ele NAO cria (bloco DO cai em NOTICE) e a
-- confirmacao conta os grupos duplicados, para decidir a limpeza a parte.
-- O gatilho de DESL-003 so age em gravacoes novas — sem risco de legado.
-- ============================================================================

SET lock_timeout = '10s';

-- DESL-003: dispensa imotivada vedada com afastamento ativo (CLT art. 476) ----
CREATE OR REPLACE FUNCTION public.admissao_bloqueia_dispensa_com_afastamento()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
    v_afast_ativos integer;
BEGIN
    IF NEW.status = 'desligado'
       AND (OLD.status IS DISTINCT FROM NEW.status)
       AND lower(coalesce(NEW.motivo_desligamento, '')) IN ('sem_justa_causa', 'dispensa_arbitraria') THEN
        SELECT count(*) INTO v_afast_ativos
          FROM public.afastamentos a
         WHERE a.tenant_id = NEW.tenant_id
           AND regexp_replace(coalesce(a.colaborador_cpf, ''), '\D', '', 'g')
             = regexp_replace(coalesce(NEW.cpf, ''), '\D', '', 'g')
           AND a.status = 'ativo';
        IF v_afast_ativos > 0 THEN
            RAISE EXCEPTION 'Dispensa sem justa causa vedada: colaborador com afastamento ativo — o contrato esta suspenso (CLT art. 476). Encerre o afastamento antes, ou registre motivo permitido (falecimento, termino de contrato a termo, justa causa).';
        END IF;
    END IF;
    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_admissao_bloqueia_dispensa_afastamento ON public.admissoes;
CREATE TRIGGER trg_admissao_bloqueia_dispensa_afastamento
  BEFORE UPDATE ON public.admissoes
  FOR EACH ROW EXECUTE FUNCTION public.admissao_bloqueia_dispensa_com_afastamento();

-- COLAB-033: indice unico de CPF normalizado (so onde a base esta limpa) ------
DO $do$
BEGIN
  IF to_regclass('public.usuarios_base_cpf_norm_tenant_uidx') IS NULL THEN
    CREATE UNIQUE INDEX usuarios_base_cpf_norm_tenant_uidx
      ON public.usuarios_base (tenant_id, regexp_replace(cpf, '[^0-9]', '', 'g'))
      WHERE cpf IS NOT NULL AND regexp_replace(cpf, '[^0-9]', '', 'g') <> '';
  END IF;
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'usuarios_base_cpf_norm_tenant_uidx nao criado: ha CPF normalizado duplicado no legado (mesma pessoa em duplicidade). COLAB-033 segue vermelho ate a limpeza a parte.';
END $do$;

-- Confirmacao leve (so catalogo) + legado de CPF duplicado --------------------
SELECT 'DESL-003 gatilho' AS item,
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                          WHERE tgname='trg_admissao_bloqueia_dispensa_afastamento'
                            AND tgrelid='public.admissoes'::regclass)
            THEN 'instalado' ELSE 'AUSENTE' END AS valor
UNION ALL
SELECT 'COLAB-033 indice',
       COALESCE((SELECT 'presente' FROM pg_class WHERE relname='usuarios_base_cpf_norm_tenant_uidx'),
                'ausente (legado duplicado — ver linha abaixo)')
UNION ALL
SELECT 'LEGADO: grupos de CPF normalizado duplicado em usuarios_base',
       (SELECT count(*)::text FROM (
          SELECT tenant_id, regexp_replace(cpf,'[^0-9]','','g') AS d
          FROM public.usuarios_base
          WHERE cpf IS NOT NULL AND regexp_replace(cpf,'[^0-9]','','g') <> ''
          GROUP BY 1,2 HAVING count(*) > 1) x)
ORDER BY item;
