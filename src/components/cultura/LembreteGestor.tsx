import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Lock, MessageSquareText, Users, X } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useCelebracoes } from "@/hooks/useCelebracoes";
import { useMeuTime } from "@/hooks/useMeuTime";
import { usePublicarNoMural } from "@/hooks/usePublicarNoMural";
import { celebracoesDoTime, pessoaReservada, type Celebracao } from "@/lib/celebracoes";
import { MensagemSugerida } from "@/components/cultura/MensagemSugerida";
import type { CulturaPreferencia, TomMensagem } from "@/types/cultura";

const rotuloDias = (d: number) => (d === 0 ? "Hoje!" : d === 1 ? "Amanhã" : `em ${d} dias`);

/**
 * Lembrete ao gestor, no Mural: as celebrações do PRÓPRIO time dentro da janela da
 * Configuração, com texto sugerido de um toque. Só aparece quando o RH liga
 * "Lembrar os gestores" e a pessoa logada tem time.
 */
export const LembreteGestor = () => {
  const { tenantId, user } = useAuth();
  const queryClient = useQueryClient();
  const { celebracoes, config } = useCelebracoes();
  const ativo = !!config?.lembrar_gestor;
  const { data: idsDoTime = [] } = useMeuTime(ativo);
  const publicar = usePublicarNoMural();
  const [redigindo, setRedigindo] = useState<Celebracao | null>(null);

  const { data: dispensados = [] } = useQuery({
    queryKey: ["lembretes-dispensados", tenantId, user?.id],
    queryFn: async () => {
      const { data, error } = await fromTable("lembretes_dispensados")
        .select("chave")
        .eq("tenant_id", tenantId)
        .eq("usuario_id", user!.id);
      if (error) throw error;
      return (data || []).map((d: { chave: string }) => d.chave);
    },
    enabled: ativo && !!tenantId && !!user?.id,
  });

  const { data: preferencias = [] } = useQuery({
    queryKey: ["cultura-preferencias", tenantId],
    queryFn: async () => {
      const { data, error } = await fromTable("cultura_preferencias")
        .select("colaborador_id, colaborador_nome, tipo_reconhecimento")
        .eq("tenant_id", tenantId);
      if (error) throw error;
      return (data || []) as CulturaPreferencia[];
    },
    enabled: ativo && !!tenantId,
  });

  if (!ativo || idsDoTime.length === 0) return null;

  const chaveDispensa = (c: Celebracao) => `gestor-${c.chave}`;
  const itens = celebracoesDoTime(celebracoes, new Set(idsDoTime)).filter((c) => !dispensados.includes(chaveDispensa(c)));
  if (itens.length === 0) return null;

  const dispensar = async (c: Celebracao) => {
    if (!tenantId || !user?.id) return;
    await fromTable("lembretes_dispensados").insert({ tenant_id: tenantId, usuario_id: user.id, chave: chaveDispensa(c) });
    queryClient.invalidateQueries({ queryKey: ["lembretes-dispensados"] });
  };

  const tom: TomMensagem = config?.tom_mensagem ?? "leve";

  return (
    <Card data-testid="lembrete-gestor">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <Users className="h-4 w-4 text-primary" /> Seu time
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {itens.map((c) => (
          <div key={c.chave} className="flex items-center gap-2 p-2 rounded-lg bg-muted/50">
            <div className="min-w-0 flex-1">
              <p className="text-xs font-medium truncate">{c.nome}</p>
              <div className="flex items-center gap-1.5 flex-wrap mt-0.5">
                <Badge variant="outline" className="text-[9px] h-4">
                  {c.tipo === "aniversario" ? "Aniversário" : `${c.anos} ano${(c.anos ?? 0) > 1 ? "s" : ""} de empresa`}
                </Badge>
                <Badge variant={c.diasRestantes === 0 ? "default" : "secondary"} className="text-[9px] h-4">
                  {rotuloDias(c.diasRestantes)}
                </Badge>
                {pessoaReservada(preferencias, c.pessoaId, c.nome) && (
                  <Badge variant="outline" className="text-[9px] h-4 gap-1" title="Prefere reconhecimento reservado">
                    <Lock className="h-2.5 w-2.5" /> Reservado
                  </Badge>
                )}
              </div>
            </div>
            <Button size="icon" variant="ghost" className="h-7 w-7 shrink-0" aria-label={`Sugerir mensagem para ${c.nome}`} title="Sugerir mensagem" onClick={() => setRedigindo(c)}>
              <MessageSquareText className="h-4 w-4 text-primary" />
            </Button>
            <button className="shrink-0 p-0.5 rounded hover:bg-muted text-muted-foreground" title="Dispensar lembrete" onClick={() => dispensar(c)}>
              <X className="h-3 w-3" />
            </button>
          </div>
        ))}
      </CardContent>
      <MensagemSugerida
        celebracao={redigindo}
        tom={tom}
        reservado={!!redigindo && pessoaReservada(preferencias, redigindo.pessoaId, redigindo.nome)}
        onFechar={() => setRedigindo(null)}
        onPublicar={(conteudo) =>
          publicar({ conteudo, tipo: redigindo?.tipo === "tempo_casa" ? "tempo_casa" : "aniversario" })
        }
      />
    </Card>
  );
};
