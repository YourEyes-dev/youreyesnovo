-- Cadastro de EPI: o CA passa a ser obrigatório por CATEGORIA
-- ===========================================================
--
-- Sintoma relatado: "Cadastro de Uniformes: no cadastro de EPI não tem os
-- campos CA e data de validade como obrigatórios, mas não deixa cadastrar
-- sem." A tela realmente não marcava os dois campos com asterisco, e mesmo
-- assim a validação barrava — porque a regra era fixa: TODO item precisava de
-- CA, viesse ele de um capacete ou de uma camiseta.
--
-- Capacete, luva e bota têm Certificado de Aprovação (NR-06). Uniforme,
-- crachá e camiseta não têm — e nunca terão. Em vez de escolher por eles,
-- cada cliente passa a marcar quais das SUAS categorias exigem CA.
--
-- Padrão: exige. Assim nada que hoje é EPI de verdade deixa de pedir o CA por
-- descuido — a mudança só libera o que for marcado como isento.

ALTER TABLE public.epi_categorias
  ADD COLUMN IF NOT EXISTS exige_ca boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.epi_categorias.exige_ca IS
  'Quando true (padrão), o cadastro de EPI desta categoria exige número do CA e data de validade (NR-06). Marque como false para categorias que não têm CA, como uniformes e vestuário comum.';

-- A tabela nascera só com SELECT/INSERT/DELETE: não havia como ALTERAR uma
-- categoria. Sem esta política, a marcação seria salva e silenciosamente
-- descartada pelo RLS.
DROP POLICY IF EXISTS "Tenant users can update categories" ON public.epi_categorias;
CREATE POLICY "Tenant users can update categories"
  ON public.epi_categorias
  FOR UPDATE
  USING (tenant_id IN (SELECT profiles.tenant_id FROM profiles WHERE profiles.user_id = auth.uid()))
  WITH CHECK (tenant_id IN (SELECT profiles.tenant_id FROM profiles WHERE profiles.user_id = auth.uid()));

-- Já deixa desmarcado o que claramente não tem CA, para que ninguém precise
-- descobrir a marcação no susto do primeiro cadastro. Só toca em categoria
-- que ainda está no padrão (true) — quem já tiver marcado à mão fica como
-- está. Rodar duas vezes não muda nada.
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
