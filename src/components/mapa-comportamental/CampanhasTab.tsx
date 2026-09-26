import { useState } from "react";
import { Send, Plus, Users, Play, Square, UserPlus, Info } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Skeleton } from "@/components/ui/skeleton";
import {
  useMapaComportamentalCampanhas,
  useCoberturaCampanha,
  useMapaComportamentalPolitica,
  type MapaCampanha,
} from "@/hooks/useMapaComportamentalCampanhas";

const STATUS_BADGE: Record<MapaCampanha["status"], { label: string; variant: "secondary" | "outline" | "default" }> = {
  rascunho: { label: "Rascunho", variant: "outline" },
  ativa: { label: "Ativa", variant: "default" },
  encerrada: { label: "Encerrada", variant: "secondary" },
};

export function CampanhasTab() {
  const { campanhas, isLoading, criar, mudarStatus, gerarConvites } = useMapaComportamentalCampanhas();
  const { politicaPublicada } = useMapaComportamentalPolitica();
  const [criando, setCriando] = useState(false);
  const [nome, setNome] = useState("");
  const [descricao, setDescricao] = useState("");
  const [dataFim, setDataFim] = useState("");

  async function submitNova() {
    if (!nome.trim()) return;
    await criar.mutateAsync({
      nome: nome.trim(),
      descricao: descricao.trim() || undefined,
      publico: { tipo: "empresa_inteira" },
      data_fim: dataFim || null,
    });
    setNome("");
    setDescricao("");
    setDataFim("");
    setCriando(false);
  }

  return (
    <div className="space-y-4">
      {!politicaPublicada && (
        <Alert>
          <Info className="h-4 w-4" />
          <AlertDescription>
            Publique a política de uso na aba <strong>Governança</strong> para poder ativar campanhas (RF-001).
          </AlertDescription>
        </Alert>
      )}

      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold flex items-center gap-2">
          <Send className="w-5 h-5" /> Campanhas
        </h2>
        <Button size="sm" onClick={() => setCriando((v) => !v)} className="gap-1">
          <Plus className="w-4 h-4" /> Nova campanha
        </Button>
      </div>

      {criando && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Nova campanha</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="space-y-1">
              <label className="text-sm font-medium">Nome</label>
              <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Ex.: Mapa Comportamental 2026" />
            </div>
            <div className="space-y-1">
              <label className="text-sm font-medium">Descrição (opcional)</label>
              <Textarea rows={2} value={descricao} onChange={(e) => setDescricao(e.target.value)} />
            </div>
            <div className="space-y-1">
              <label className="text-sm font-medium">Prazo (opcional)</label>
              <Input type="date" value={dataFim} onChange={(e) => setDataFim(e.target.value)} />
            </div>
            <p className="text-xs text-muted-foreground">
              Público desta versão: <strong>todos os colaboradores ativos</strong> da empresa. A resposta é
              sempre voluntária.
            </p>
            <div className="flex gap-2">
              <Button onClick={submitNova} disabled={!nome.trim() || criar.isPending}>Criar rascunho</Button>
              <Button variant="ghost" onClick={() => setCriando(false)}>Cancelar</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-24" />
          <Skeleton className="h-24" />
        </div>
      ) : campanhas.length === 0 ? (
        <p className="text-sm text-muted-foreground">Nenhuma campanha ainda. Crie a primeira acima.</p>
      ) : (
        <div className="space-y-3">
          {campanhas.map((c) => (
            <CampanhaCard
              key={c.id}
              campanha={c}
              politicaPublicada={politicaPublicada}
              onGerarConvites={() => gerarConvites.mutate(c.id)}
              gerando={gerarConvites.isPending}
              onAtivar={() => mudarStatus.mutate({ id: c.id, status: "ativa" })}
              onEncerrar={() => mudarStatus.mutate({ id: c.id, status: "encerrada" })}
              mudando={mudarStatus.isPending}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function CampanhaCard({
  campanha,
  politicaPublicada,
  onGerarConvites,
  gerando,
  onAtivar,
  onEncerrar,
  mudando,
}: {
  campanha: MapaCampanha;
  politicaPublicada: boolean;
  onGerarConvites: () => void;
  gerando: boolean;
  onAtivar: () => void;
  onEncerrar: () => void;
  mudando: boolean;
}) {
  const badge = STATUS_BADGE[campanha.status];
  const { data: cob } = useCoberturaCampanha(campanha.id, campanha.status !== "rascunho");

  return (
    <Card>
      <CardContent className="pt-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-medium truncate">{campanha.nome}</h3>
              <Badge variant={badge.variant}>{badge.label}</Badge>
            </div>
            {campanha.descricao && <p className="text-sm text-muted-foreground mt-1">{campanha.descricao}</p>}
            <p className="text-xs text-muted-foreground mt-1">
              Público: todos os colaboradores ativos
              {campanha.data_fim ? ` · prazo ${new Date(campanha.data_fim).toLocaleDateString("pt-BR")}` : ""}
            </p>
            {campanha.status !== "rascunho" && cob && (
              <div className="mt-2">
                <div className="flex items-center gap-2 text-sm">
                  <Users className="w-4 h-4 text-muted-foreground" />
                  <span>
                    Cobertura: <strong>{cob.respondidos}/{cob.convidados}</strong> ({cob.pct}%)
                  </span>
                </div>
                <div className="h-2 w-full max-w-xs rounded-full bg-muted overflow-hidden mt-1">
                  <div className="h-full bg-emerald-500/70" style={{ width: `${cob.pct}%` }} />
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="flex flex-wrap gap-2 mt-4">
          <Button size="sm" variant="outline" className="gap-1" onClick={onGerarConvites} disabled={gerando}>
            <UserPlus className="w-4 h-4" /> Gerar convites
          </Button>
          {campanha.status === "rascunho" && (
            <Button size="sm" className="gap-1" onClick={onAtivar} disabled={mudando || !politicaPublicada}>
              <Play className="w-4 h-4" /> Ativar
            </Button>
          )}
          {campanha.status === "ativa" && (
            <Button size="sm" variant="secondary" className="gap-1" onClick={onEncerrar} disabled={mudando}>
              <Square className="w-4 h-4" /> Encerrar
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
