import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Compass, Info } from "lucide-react";
import { useAderenciaFuncao } from "@/hooks/useMapaComportamentalTime";
import {
  calcularAderencia,
  NIVEL_ADERENCIA_LABEL,
  type MapaPessoaResumo,
  type PerfilIdealCargo,
  type NivelAderencia,
} from "@/data/instrumentos/aderenciaCargo";
import type { Arquetipo, Motor, Modo } from "@/data/instrumentos/mapaComportamental";

interface Props {
  mapaId: string;
  // ficha.resultado (MapaResultado serializado); vem destipado da RPC.
  resultado: Record<string, unknown> | null | undefined;
}

// Cores de DESENVOLVIMENTO — nunca avaliativas (sem vermelho de "reprovado").
const NIVEL_META: Record<NivelAderencia, string> = {
  flui: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/30 dark:text-emerald-300",
  adapta: "bg-sky-100 text-sky-800 dark:bg-sky-900/30 dark:text-sky-300",
  energia: "bg-violet-100 text-violet-800 dark:bg-violet-900/30 dark:text-violet-300",
};

function resumoDoResultado(resultado: Props["resultado"]): MapaPessoaResumo | null {
  if (!resultado || typeof resultado !== "object") return null;
  const r = resultado as {
    arquetipos?: Arquetipo[];
    motor?: { predominantes?: Motor[] };
    modo?: { resultado?: Modo | "misto" };
    confiabilidade?: "alta" | "baixa";
  };
  if (!r.arquetipos || !r.modo?.resultado || !r.confiabilidade) return null;
  return {
    arquetipos: r.arquetipos,
    motores: r.motor?.predominantes ?? [],
    modo: r.modo.resultado,
    confiabilidade: r.confiabilidade,
  };
}

export function AderenciaFuncaoCard({ mapaId, resultado }: Props) {
  const { data: perfil, isLoading } = useAderenciaFuncao(mapaId);

  // Sem cargo resolvido para a pessoa → não exibe nada (evita ruído).
  if (isLoading || !perfil) return null;

  const resumo = resumoDoResultado(resultado);

  const ideal: PerfilIdealCargo | null = perfil.tem_perfil
    ? {
        arquetipoIdeal: (perfil.arquetipo_ideal as Arquetipo) ?? null,
        motorIdeal: (perfil.motor_ideal as Motor[]) ?? [],
        modoIdeal: (perfil.modo_ideal as Modo | "misto") ?? null,
      }
    : null;

  const aderencia = calcularAderencia(resumo, ideal);

  return (
    <Card className="max-w-2xl mx-auto">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Compass className="w-4 h-4" /> Aderência ao estilo da função
          {perfil.cargo_nome && (
            <span className="text-sm font-normal text-muted-foreground">· {perfil.cargo_nome}</span>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {!perfil.tem_perfil ? (
          <p className="text-sm text-muted-foreground">
            Esta função ainda não tem um perfil comportamental ideal definido. Defina-o em
            Aprendizado &amp; Papéis (aba <strong>Perfil comportamental</strong> da função) para ver a aderência de estilo.
          </p>
        ) : !aderencia.disponivel && aderencia.motivoIndisponivel === "confiabilidade_baixa" ? (
          <p className="text-sm text-muted-foreground">
            A aderência não é exibida porque a <strong>confiabilidade</strong> deste mapa está baixa —
            o resultado pode não refletir bem o estilo da pessoa.
          </p>
        ) : !aderencia.disponivel ? (
          <p className="text-sm text-muted-foreground">Não há dados suficientes para calcular a aderência.</p>
        ) : (
          <>
            <div className="space-y-2">
              {aderencia.dimensoes.map((d) => (
                <div key={d.dimensao} className="flex items-start gap-2">
                  <Badge className={`text-[11px] shrink-0 ${NIVEL_META[d.nivel]}`}>
                    {NIVEL_ADERENCIA_LABEL[d.nivel]}
                  </Badge>
                  <span className="text-sm text-muted-foreground">{d.frase}</span>
                </div>
              ))}
            </div>

            {aderencia.resumoGeral && (
              <p className="text-sm font-medium text-foreground pt-1">{aderencia.resumoGeral}</p>
            )}
          </>
        )}

        <div className="flex items-start gap-2 rounded-md bg-muted/50 p-2.5 text-xs text-muted-foreground">
          <Info className="w-3.5 h-3.5 shrink-0 mt-0.5" />
          <span>
            Aderência de <strong>estilo</strong>, em linguagem de tendência — onde a pessoa tende a fluir e onde pode
            precisar de mais apoio/energia. Não é medida de competência e <strong>não serve para movimentação,
            promoção ou desligamento</strong>.
          </span>
        </div>
      </CardContent>
    </Card>
  );
}
