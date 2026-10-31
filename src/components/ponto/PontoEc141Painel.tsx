import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Scale, ChevronDown, ChevronUp, Wand2, Undo2, Send, Loader2 } from "lucide-react";
import {
  useImpactoEc141,
  useMigracoesEc141,
  useAditivosEc141,
  useCancelarMigracaoEc141,
  useEnviarAditivoEc141,
  formatarDataBR,
  formatarHoras,
  type AditivoEc141,
} from "@/hooks/usePontoEc141";
import { Ec141ImpactoTabela } from "./Ec141ImpactoTabela";
import { Ec141AssistenteMigracao } from "./Ec141AssistenteMigracao";

/**
 * Aviso + painel de impacto da EC 141/2026 na tela de escalas.
 *
 * Só aparece quando o SuperAdmin YourEyes ATIVA um marco da emenda (42h ou
 * 40h) — enquanto a lei não for ativada, este componente não desenha nada.
 * F2a: o RH aciona aqui o assistente "Migrar para 42h/40h", acompanha os
 * aditivos (pendência até a assinatura) e pode cancelar a migração em lote
 * antes da data (ex.: lei revogada).
 */
const SITUACAO_ADITIVO: Record<AditivoEc141["situacao"], string> = {
  pendente_envio: "Não enviado",
  aguardando_assinatura: "Aguardando assinatura",
  assinado: "Assinado",
  contestado: "Contestado",
  cancelado: "Cancelado",
};

export function PontoEc141Painel() {
  const { data: impacto } = useImpactoEc141();
  const [aberto, setAberto] = useState(false);
  const [assistente, setAssistente] = useState(false);
  const [cancelando, setCancelando] = useState<null | { id: string; motivo: string }>(null);
  const visivel = !!impacto?.visivel && !!impacto.marco;
  const { data: migracoes = [] } = useMigracoesEc141(visivel);
  const { data: aditivos = [] } = useAditivosEc141(false, visivel);
  const cancelar = useCancelarMigracaoEc141();
  const enviar = useEnviarAditivoEc141();

  if (!visivel || !impacto?.marco) return null;
  const m = impacto.marco;
  const t = impacto.totais;
  const pendencias = (t?.escalas_acima_teto || 0) + (t?.escalas_6dias_sem_coletivo || 0);
  const aditivosPendentes = aditivos.filter((a) => a.situacao !== "assinado" && a.situacao !== "cancelado");
  const migracoesAtivas = migracoes.filter((x) => x.status === "aplicada");

  return (
    <Card className="border-blue-300" data-testid="ponto-ec141-painel">
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Scale className="w-4 h-4 text-blue-700" />
          Redução da jornada (EC 141/2026): {formatarHoras(m.teto_semanal_min)} semanais a partir de {formatarDataBR(m.vigencia_inicio)}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 text-sm">
        <p className="text-muted-foreground">
          A partir dessa data o limite passa a ser {formatarHoras(m.teto_semanal_min)} por semana, com {m.repousos_semana} repousos
          semanais (6 dias por semana só com convenção ou acordo coletivo). Sem redução de salário.
          {pendencias > 0
            ? ` Há ${t?.escalas_acima_teto || 0} escala(s) acima do novo teto (${t?.colaboradores_acima_teto || 0} colaborador(es)) e ${t?.escalas_6dias_sem_coletivo || 0} escala(s) de 6 dias sem instrumento coletivo.`
            : " Suas escalas já estão dentro do novo limite."}
          {" "}Use o assistente para migrar a empresa de uma vez, ou edite a escala e escolha "A partir de uma data". Nada é alterado automaticamente.
          {" "}A partir da data, salvar uma escala acima do limite (ou com 6 dias sem instrumento coletivo) é recusado; as batidas nunca são bloqueadas.
        </p>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" onClick={() => setAssistente(true)} data-testid="ec141-abrir-assistente">
            <Wand2 className="w-4 h-4 mr-1" /> Migrar para 42h/40h
          </Button>
          <Button size="sm" variant="outline" onClick={() => setAberto(!aberto)}>
            {aberto ? <ChevronUp className="w-4 h-4 mr-1" /> : <ChevronDown className="w-4 h-4 mr-1" />}
            {aberto ? "Ocultar detalhes" : "Ver escalas afetadas"}
          </Button>
        </div>
        {aberto && <Ec141ImpactoTabela impacto={impacto} />}

        {migracoesAtivas.length > 0 && (
          <div className="space-y-2 rounded-md border p-3" data-testid="ec141-migracoes">
            <div className="font-medium">Migrações gravadas</div>
            {migracoesAtivas.map((x) => (
              <div key={x.id} className="flex flex-wrap items-center justify-between gap-2 text-xs">
                <span>
                  {x.destino_padrao}h a partir de {formatarDataBR(x.vigencia_inicio)} · {x.resumo?.migrados || 0} colaborador(es) ·
                  por {x.acionado_por_email || "sistema"} em {formatarDataBR(x.acionado_em)}
                </span>
                {x.pode_cancelar && (
                  <Button size="sm" variant="outline" className="h-7" onClick={() => setCancelando({ id: x.id, motivo: "" })}>
                    <Undo2 className="w-3 h-3 mr-1" /> Cancelar migração
                  </Button>
                )}
              </div>
            ))}
          </div>
        )}

        {aditivos.length > 0 && (
          <div className="space-y-2 rounded-md border p-3" data-testid="ec141-aditivos">
            <div className="font-medium flex items-center gap-2">
              Aditivos de alteração de horário
              {aditivosPendentes.length > 0 && (
                <Badge className="bg-amber-100 text-amber-900">{aditivosPendentes.length} não assinado(s)</Badge>
              )}
            </div>
            {aditivos.filter((a) => a.situacao !== "cancelado").map((a) => (
              <div key={a.id} className="flex flex-wrap items-center justify-between gap-2 text-xs">
                <span>{a.colaborador_nome || "-"} · a partir de {formatarDataBR(a.vigencia_inicio)}</span>
                <span className="flex items-center gap-2">
                  <Badge variant="outline" className={a.situacao === "assinado" ? "border-emerald-400 text-emerald-700" : a.situacao === "contestado" ? "border-red-400 text-red-700" : ""}>
                    {SITUACAO_ADITIVO[a.situacao]}
                  </Badge>
                  {(a.situacao === "pendente_envio" || a.situacao === "contestado") && (
                    <Button size="sm" variant="outline" className="h-7" disabled={enviar.isPending}
                      onClick={() => enviar.mutate(a.id)}>
                      {enviar.isPending ? <Loader2 className="w-3 h-3 mr-1 animate-spin" /> : <Send className="w-3 h-3 mr-1" />}
                      Enviar para assinatura
                    </Button>
                  )}
                </span>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      {assistente && (
        <Ec141AssistenteMigracao aberto={assistente} onFechar={() => setAssistente(false)} teto={m} />
      )}

      <Dialog open={!!cancelando} onOpenChange={(v) => !v && setCancelando(null)}>
        <DialogContent>
          <DialogHeader><DialogTitle>Cancelar a migração da EC 141?</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">
            Todas as escalas e atribuições desta migração voltam exatamente ao que eram antes, e os aditivos ainda não
            assinados ficam cancelados. Use quando a lei for revogada ou adiada. Só é possível antes da data.
          </p>
          <Textarea placeholder="Motivo (ex.: lei revogada, adiamento)" value={cancelando?.motivo || ""}
            onChange={(e) => setCancelando((c) => (c ? { ...c, motivo: e.target.value } : c))} />
          <DialogFooter>
            <Button variant="outline" onClick={() => setCancelando(null)}>Voltar</Button>
            <Button variant="destructive" disabled={cancelar.isPending || (cancelando?.motivo.trim().length || 0) < 5}
              onClick={async () => {
                if (!cancelando) return;
                await cancelar.mutateAsync({ migracaoId: cancelando.id, motivo: cancelando.motivo.trim() });
                setCancelando(null);
              }}>
              Cancelar migração
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
