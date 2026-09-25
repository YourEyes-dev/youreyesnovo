import { useMemo } from 'react';
import { useEmpresaAtiva } from '@/contexts/EmpresaAtivaContext';
import type { EmpresaCadastro } from '@/types/empresa';

/**
 * Empresas que estão no REGIME de Ponto — as únicas que devem aparecer no
 * seletor do módulo de Ponto.
 *
 * "Em regime" = a chave `usa_controle_ponto` está ligada no cadastro da
 * empresa (ligada pelo operador na aba Jornada e Turnos, quando o plano do
 * cliente inclui o módulo). Empresas que não usam o ponto — como os ~1.000+
 * clientes só-psicossocial de um prestador — ficam de fora, para não poluir
 * o seletor nem inflar contagens.
 *
 * Reaproveita a lista já escopada por tenant/vínculo do EmpresaAtivaContext:
 * profissional com vínculos continua vendo só as empresas permitidas.
 */
export function usePontoEmpresas() {
  const {
    empresas,
    empresaAtiva,
    empresaAtivaId,
    setEmpresaAtiva,
    isLoading,
    initialized,
  } = useEmpresaAtiva();

  const empresasPonto = useMemo<EmpresaCadastro[]>(
    () => empresas.filter((e) => e.usa_controle_ponto === true),
    [empresas],
  );

  const ativaEmRegime =
    !!empresaAtivaId && empresasPonto.some((e) => e.id === empresaAtivaId);

  return {
    /** Empresas com controle de ponto ligado (para o seletor do módulo). */
    empresasPonto,
    /** A empresa ativa está no regime de ponto? */
    ativaEmRegime,
    /** Nenhuma empresa do cliente usa ponto ainda. */
    nenhumaEmpresaPonto: !isLoading && empresasPonto.length === 0,
    empresaAtiva,
    empresaAtivaId,
    setEmpresaAtiva,
    isLoading,
    initialized,
  };
}
