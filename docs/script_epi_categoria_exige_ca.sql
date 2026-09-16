-- =====================================================================
-- Cadastro de EPI — o CA passa a ser obrigatório por CATEGORIA
--
-- Para colar no SQL Editor. Roda inteiro numa transação; rodar duas
-- vezes não muda nada.
--
-- O QUE O USUÁRIO RELATOU
-- "Cadastro de Uniformes: no cadastro de EPI não tem os campos CA e data
-- de validade como obrigatórios, mas não deixa cadastrar sem."
--
-- O QUE ESTAVA ACONTECENDO
-- A tela realmente não marcava os dois campos com asterisco, e mesmo
-- assim a validação barrava — porque a regra era fixa: TODO item pedia
-- CA, viesse ele de um capacete ou de uma camiseta. Capacete, luva e
-- bota têm Certificado de Aprovação (NR-06). Uniforme, crachá e camiseta
-- não têm, e nunca terão.
--
-- O QUE MUDA
-- Cada cliente passa a marcar quais das SUAS categorias exigem CA, em
-- EPI › Configurações › "Exigência de CA por Categoria". O padrão é
-- EXIGIR: nada que hoje é EPI de verdade deixa de pedir o CA por
-- descuido — a mudança só libera o que for marcado como isento.
--
-- SOBRE DADO EXISTENTE
-- O script cria uma coluna nova e uma política de escrita que faltava.
-- O único UPDATE mexe apenas nessa coluna recém-criada — que até este
-- momento não existia —, desmarcando de saída as categorias de uniforme
-- e vestuário. Nenhuma informação anterior é sobrescrita, por isso não
-- há tabela de resgate. Para desfazer:
--   UPDATE public.epi_categorias SET exige_ca = true;
-- (ou, para remover a marcação por completo,
--  ALTER TABLE public.epi_categorias DROP COLUMN exige_ca;)
-- =====================================================================

ALTER TABLE public.epi_categorias
  ADD COLUMN IF NOT EXISTS exige_ca boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.epi_categorias.exige_ca IS
  'Quando true (padrão), o cadastro de EPI desta categoria exige número do CA e data de validade (NR-06). Marque como false para categorias que não têm CA, como uniformes e vestuário comum.';

-- A tabela nascera só com SELECT/INSERT/DELETE: não havia como ALTERAR
-- uma categoria. Sem esta política, a marcação seria salva na tela e
-- silenciosamente descartada pelo banco.
DROP POLICY IF EXISTS "Tenant users can update categories" ON public.epi_categorias;
CREATE POLICY "Tenant users can update categories"
  ON public.epi_categorias
  FOR UPDATE
  USING (tenant_id IN (SELECT profiles.tenant_id FROM profiles WHERE profiles.user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT profiles.tenant_id FROM profiles WHERE profiles.user_id = auth.uid()));

-- Já deixa desmarcado o que claramente não tem CA, para que ninguém
-- precise descobrir a marcação no susto do primeiro cadastro. Só toca em
-- categoria que ainda está no padrão — quem já tiver marcado à mão fica
-- como está.
UPDATE public.epi_categorias
   SET exige_ca = false
 WHERE exige_ca = true
   AND (
        nome ILIKE '%uniforme%'
     OR nome ILIKE '%fardamento%'
     OR nome ILIKE '%vestuário%'
     OR nome ILIKE '%vestuario%'
     OR nome ILIKE '%vestimenta%'
     OR nome ILIKE '%camiseta%'
     OR nome ILIKE '%crachá%'
     OR nome ILIKE '%cracha%'
   );

-- =====================================================================
-- CONFERÊNCIA — o editor mostra só o último resultado
-- Esperado: coluna_criada = true, politica_de_edicao = true, e a
-- contagem de categorias isentas (pode ser 0 se o cliente ainda não tem
-- categoria de uniforme cadastrada — nesse caso ele marca pela tela).
-- =====================================================================
WITH marcacao AS MATERIALIZED (
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'epi_categorias'
       AND column_name = 'exige_ca'
  ) AS coluna_criada,
  EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'epi_categorias'
       AND policyname = 'Tenant users can update categories'
  ) AS politica_de_edicao
), isentas AS MATERIALIZED (
  SELECT count(*) AS quantas,
         COALESCE(string_agg(DISTINCT nome, ', ' ORDER BY nome), '(nenhuma)') AS quais
    FROM public.epi_categorias WHERE exige_ca = false
)
SELECT m.coluna_criada,
       m.politica_de_edicao,
       i.quantas AS categorias_isentas_de_ca,
       i.quais   AS quais_categorias
  FROM marcacao m, isentas i;
