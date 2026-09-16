import { Star, MapPin, BadgeCheck, Video, Building2, Clock, Sparkles, Tag, Ticket, Megaphone, Activity, Users } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { formatarPreco, NIVEL_LABEL, SAUDE_LABEL, type MarketYEAnuncio } from "@/hooks/useMarketYE";

interface AnuncioCardProps {
  anuncio: MarketYEAnuncio;
  onContatar?: (anuncio: MarketYEAnuncio) => void;
  onDenunciar?: (profissionalId: string, nome: string) => void;
}

const modalidadeCfg: Record<string, { icon: React.ElementType; label: string; class: string }> = {
  presencial: { icon: Building2, label: "Presencial", class: "text-blue-700 bg-blue-50" },
  online: { icon: Video, label: "Remoto", class: "text-green-700 bg-green-50" },
  hibrido: { icon: MapPin, label: "Híbrido", class: "text-purple-700 bg-purple-50" },
};
const saudeCor: Record<string, string> = { verde: "bg-emerald-500", amarelo: "bg-amber-400", vermelho: "bg-red-500", cinza: "bg-slate-300" };
const nivelCor: Record<string, string> = {
  novo: "bg-slate-100 text-slate-700", bronze: "bg-orange-100 text-orange-800", prata: "bg-slate-200 text-slate-800",
  ouro: "bg-amber-100 text-amber-800", top: "bg-gradient-to-r from-indigo-500 to-violet-600 text-white",
};

export function AnuncioCard({ anuncio, onContatar, onDenunciar }: AnuncioCardProps) {
  const mod = modalidadeCfg[anuncio.modalidade] ?? modalidadeCfg.presencial;
  const ModIcon = mod.icon;
  const p = anuncio.profissional;
  const tempoResposta = p.tempo_resposta_mediano_min != null
    ? p.tempo_resposta_mediano_min < 60 ? `responde em ~${p.tempo_resposta_mediano_min} min` : `responde em ~${Math.round(p.tempo_resposta_mediano_min / 60)} h`
    : null;

  return (
    <div className="group bg-card border border-border rounded-2xl overflow-hidden hover:shadow-xl hover:shadow-indigo-500/5 transition-all duration-300 hover:border-indigo-200 flex flex-col" data-testid="marketye-anuncio">
      <div className={`h-1.5 ${anuncio.patrocinado ? "bg-gradient-to-r from-amber-400 to-orange-500" : "bg-gradient-to-r from-indigo-500 via-violet-500 to-purple-500"}`} />
      <div className="p-5 space-y-3 flex-1 flex flex-col">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            {anuncio.patrocinado && (
              <span className="inline-flex items-center gap-1 text-[10px] uppercase tracking-wide font-semibold text-amber-700 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5 mb-1" title="Este especialista pagou por uma posição extra. Isso não muda a nota dele nem passa por cima da nota mínima.">
                <Megaphone className="h-3 w-3" /> Patrocinado
              </span>
            )}
            <h3 className="font-semibold text-foreground leading-snug">{anuncio.nome}</h3>
            {anuncio.categoria_nome && <p className="text-xs text-muted-foreground mt-0.5">{anuncio.categoria_nome}</p>}
          </div>
          <Badge className={`${mod.class} shrink-0`} variant="secondary"><ModIcon className="h-3 w-3 mr-1" />{mod.label}</Badge>
        </div>

        <p className="text-sm text-muted-foreground line-clamp-3">{anuncio.descricao}</p>

        {(anuncio.obrigacao_legal?.length > 0 || anuncio.base_legal) && (
          <div className="flex flex-wrap gap-1">
            {anuncio.obrigacao_legal?.map((o) => <Badge key={o} variant="outline" className="text-[10px]">{o}</Badge>)}
            {anuncio.base_legal && !anuncio.obrigacao_legal?.includes(anuncio.base_legal) && <Badge variant="outline" className="text-[10px]">{anuncio.base_legal}</Badge>}
          </div>
        )}

        <div className="flex items-center gap-3 text-sm flex-wrap">
          <span className="font-semibold text-foreground">{formatarPreco(anuncio)}</span>
          {anuncio.promocao_ativa && anuncio.promocao_percentual != null && (
            <span className="inline-flex items-center gap-1 text-xs text-emerald-700 bg-emerald-50 rounded px-1.5 py-0.5"><Tag className="h-3 w-3" />-{anuncio.promocao_percentual}% em promoção</span>
          )}
          {anuncio.tem_cupom && <span className="inline-flex items-center gap-1 text-xs text-indigo-700 bg-indigo-50 rounded px-1.5 py-0.5"><Ticket className="h-3 w-3" />cupom disponível</span>}
          {anuncio.duracao_estimada_minutos && <span className="inline-flex items-center gap-1 text-xs text-muted-foreground"><Clock className="h-3 w-3" />{anuncio.duracao_estimada_minutos} min</span>}
        </div>

        <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-xl mt-auto">
          {p.foto_url ? (
            <img src={p.foto_url} alt={p.nome_completo} className="w-10 h-10 rounded-xl object-cover shrink-0" />
          ) : (
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center text-white text-sm font-bold shrink-0">{p.nome_completo.charAt(0)}</div>
          )}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 flex-wrap">
              <span className="text-sm font-medium truncate">{p.nome_completo}</span>
              {p.selo_verificado && (
                <Tooltip>
                  <TooltipTrigger asChild><BadgeCheck className="h-3.5 w-3.5 text-emerald-500 shrink-0" /></TooltipTrigger>
                  <TooltipContent>A equipe do YourEyes conferiu os dados e o registro deste especialista. Não é uma garantia sobre o serviço.</TooltipContent>
                </Tooltip>
              )}
              <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-medium ${nivelCor[p.nivel] ?? nivelCor.novo}`}>{NIVEL_LABEL[p.nivel] ?? p.nivel}</span>
              {p.novato && <span className="inline-flex items-center gap-0.5 text-[10px] text-indigo-700"><Sparkles className="h-3 w-3" />novo aqui</span>}
            </div>
            <div className="flex items-center gap-2 text-xs text-muted-foreground flex-wrap">
              {p.conselho && <span>{p.conselho}{p.registro_profissional ? ` ${p.registro_profissional}` : ""}</span>}
              <span className="inline-flex items-center gap-0.5"><Star className="h-3 w-3 text-amber-400 fill-amber-400" />{p.total_avaliacoes > 0 ? `${Number(p.nota_media).toFixed(1)} (${p.total_avaliacoes})` : "sem avaliações"}</span>
              <Tooltip>
                <TooltipTrigger asChild><span className="inline-flex items-center gap-1"><span className={`inline-block w-2 h-2 rounded-full ${saudeCor[p.saude_cor] ?? saudeCor.cinza}`} /><Activity className="h-3 w-3" /></span></TooltipTrigger>
                <TooltipContent>{SAUDE_LABEL[p.saude_cor] ?? "Atendimento"} (últimos 90 dias: responde rápido, não cancela)</TooltipContent>
              </Tooltip>
              {p.clientes_unicos > 0 && <span className="inline-flex items-center gap-0.5"><Users className="h-3 w-3" />{p.clientes_unicos} empresas</span>}
            </div>
            <div className="flex items-center gap-2 text-[11px] text-muted-foreground mt-0.5 flex-wrap">
              {(p.cidade || p.estado) && <span className="inline-flex items-center gap-0.5"><MapPin className="h-3 w-3" />{[p.cidade, p.estado].filter(Boolean).join(", ")}{anuncio.distancia_km != null && !anuncio.remoto && ` · ${anuncio.distancia_km < 1 ? "< 1" : Math.round(anuncio.distancia_km)} km`}</span>}
              {anuncio.remoto && <span>atende remoto</span>}
              {tempoResposta && <span>· {tempoResposta}</span>}
            </div>
          </div>
        </div>

        <div className="flex gap-2">
          <Button className="flex-1 bg-gradient-to-r from-indigo-500 to-violet-600 text-white border-0 shadow-lg shadow-indigo-500/20 hover:from-indigo-600 hover:to-violet-700" onClick={() => onContatar?.(anuncio)} data-testid="marketye-contatar">
            Falar com o especialista
          </Button>
          {onDenunciar && <Button variant="ghost" size="sm" className="text-muted-foreground" onClick={() => onDenunciar(p.id, p.nome_completo)} title="Denunciar">Denunciar</Button>}
        </div>
      </div>
    </div>
  );
}
