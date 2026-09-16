import { Link } from "react-router-dom";
import { Store } from "lucide-react";
import { Button } from "@/components/ui/button";

interface Props {
  /** Obrigação legal do alerta (ex.: "NR-1", "NR-7"). Entra no matching por fit. */
  obrigacao?: string;
  /** Slug da categoria do MarketYE (ex.: "psicossocial-nr1"). */
  categoriaSlug?: string;
  /** Módulo de origem (vai no lead como origem_modulo). */
  origem?: string;
  origemId?: string;
  size?: "sm" | "default";
  variant?: "outline" | "default" | "ghost" | "secondary";
  className?: string;
  children?: React.ReactNode;
}

/**
 * "Encontrar especialista": de um alerta/não-conformidade para a vitrine do
 * MarketYE já filtrada pela obrigação legal (RF-015). O sistema traduz a
 * obrigação em categoria; o cliente não precisa saber o que buscar.
 */
export function EncontrarEspecialistaLink({ obrigacao, categoriaSlug, origem, origemId, size = "sm", variant = "outline", className, children }: Props) {
  const params = new URLSearchParams();
  if (obrigacao) params.set("obrigacao", obrigacao);
  if (categoriaSlug) params.set("categoria", categoriaSlug);
  if (origem) params.set("origem", origem);
  if (origemId) params.set("origem_id", origemId);
  const qs = params.toString();
  return (
    <Button asChild size={size} variant={variant} className={className}>
      <Link to={`/marketplace${qs ? `?${qs}` : ""}`} data-testid="encontrar-especialista">
        <Store className="h-4 w-4 mr-1.5" />{children ?? "Encontrar especialista"}
      </Link>
    </Button>
  );
}
