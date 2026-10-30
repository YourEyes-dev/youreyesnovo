import { useState } from "react";
import { format } from "date-fns";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Copy, FileSignature, Link2, Mail, Send, XCircle, FileCheck2, Loader2 } from "lucide-react";
import { toast } from "sonner";
import type { PontoEspelho } from "@/hooks/usePontoFechamento";
import { useAssinaturaSolicitacoes, type AssinaturaSolicitacao } from "@/hooks/useAssinaturaSolicitacoes";

/**
 * Painel "Assinaturas do espelho": um selo por colaborador da competência e as
 * ações do RH (enviar, reenviar, link novo, cancelar, ver o assinado).
 * Selos: Assinado ✓ (verde), Ressalva (âmbar), Contestado (vermelho),
 * Pendente (com "visto em"), Expirado, Papel, Não enviado.
 */
type Selo = { rotulo: string; classe: string };

const SELOS: Record<string, Selo> = {
  assinado: { rotulo: "Assinado ✓", classe: "bg-green-100 text-green-800 border-green-300" },
  ressalva: { rotulo: "Ressalva", classe: "bg-amber-100 text-amber-800 border-amber-300" },
  contestado: { rotulo: "Contestado", classe: "bg-red-100 text-red-800 border-red-300" },
  pendente: { rotulo: "Pendente", classe: "bg-blue-100 text-blue-800 border-blue-300" },
  expirado: { rotulo: "Expirado", classe: "bg-gray-200 text-gray-800 border-gray-300" },
  papel: { rotulo: "Papel ✓", classe: "bg-green-50 text-green-800 border-green-200" },
  legado: { rotulo: "Ciência antiga (RH)", classe: "bg-gray-100 text-gray-700 border-gray-200" },
  nao_enviado: { rotulo: "Não enviado", classe: "bg-white text-gray-600 border-gray-300" },
};

function seloDoEspelho(e: PontoEspelho, s?: AssinaturaSolicitacao): Selo {
  if (e.ciencia_origem === "papel_digitalizado") return SELOS.papel;
  if (e.ciencia_origem === "rh_legado") return SELOS.legado;
  const st = s?.status;
  if (st === "assinado") return SELOS.assinado;
  if (st === "assinado_com_ressalva") return SELOS.ressalva;
  if (st === "contestado" || e.status === "contestado") return SELOS.contestado;
  if (st && ["na_fila", "enviado", "visualizado"].includes(st)) return SELOS.pendente;
  if (st === "expirado") return SELOS.expirado;
  return SELOS.nao_enviado;
}

const dataHora = (iso?: string | null) => (iso ? format(new Date(iso), "dd/MM/yyyy HH:mm") : null);

export interface EspelhoAssinaturaStatusProps {
  competencia: string;
  espelhos: PontoEspelho[];
  competenciaFechada: boolean;
  /** Gera o PDF de UM colaborador pelo gerador único (o mesmo que será assinado). */
  gerarPdf: (espelho: PontoEspelho) => Promise<Blob | null>;
}

export function EspelhoAssinaturaStatus({ competencia, espelhos, competenciaFechada, gerarPdf }: EspelhoAssinaturaStatusProps) {
  const { porEspelho, isLoading, enviar, reenviar, novoLink, cancelar, urlAssinado } = useAssinaturaSolicitacoes(competencia);
  const [link, setLink] = useState<{ url: string; nome: string; aviso?: string } | null>(null);
  const [enviandoId, setEnviandoId] = useState<string | null>(null);

  const ativa = (s?: AssinaturaSolicitacao) => !!s && ["na_fila", "enviado", "visualizado"].includes(s.status);
  const podeEnviar = (e: PontoEspelho, s?: AssinaturaSolicitacao) =>
    competenciaFechada && !ativa(s) && (!e.ciencia_origem || e.status === "contestado");

  const handleEnviar = async (e: PontoEspelho) => {
    setEnviandoId(e.id);
    try {
      const pdf = await gerarPdf(e);
      if (!pdf) {
        toast.warning("Nenhuma apuração encontrada para este colaborador na competência.");
        return;
      }
      const r = await enviar.mutateAsync({ espelhoId: e.id, pdf });
      setLink({
        url: r.link || "",
        nome: e.colaborador_nome,
        aviso: r.email_enviado
          ? `E-mail enviado para ${r.destino}.`
          : "O e-mail não saiu. Copie o link abaixo e envie ao colaborador.",
      });
    } catch {
      // aviso já exibido pelo hook
    } finally {
      setEnviandoId(null);
    }
  };

  const handleNovoLink = async (e: PontoEspelho, s: AssinaturaSolicitacao) => {
    const url = await novoLink.mutateAsync(s.id).catch(() => null);
    if (url) setLink({ url, nome: e.colaborador_nome, aviso: "Link novo: o anterior deixou de valer." });
  };

  const verAssinado = async (s: AssinaturaSolicitacao) => {
    const url = await urlAssinado(s.assinado_path);
    if (url) window.open(url, "_blank", "noopener,noreferrer");
    else toast.error("Não foi possível abrir o documento assinado.");
  };

  const copiar = async () => {
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link.url);
      toast.success("Link copiado.");
    } catch {
      toast.error("Não foi possível copiar; selecione o link e copie.");
    }
  };

  return (
    <Card data-testid="painel-assinaturas-espelho">
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <FileSignature className="w-4 h-4" /> Assinaturas do espelho — {competencia}
        </CardTitle>
        <div className="flex flex-wrap gap-1.5 pt-1" data-testid="legenda-selos">
          {["assinado", "ressalva", "contestado", "pendente", "expirado", "papel"].map((k) => (
            <Badge key={k} variant="outline" className={SELOS[k].classe}>{SELOS[k].rotulo}</Badge>
          ))}
        </div>
        {!competenciaFechada && (
          <p className="text-xs text-muted-foreground pt-1" data-testid="aviso-competencia-aberta">
            O envio para assinatura só é liberado com a competência fechada (Ponto › Apuração › Fechamento).
          </p>
        )}
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Colaborador</TableHead>
              <TableHead>Situação</TableHead>
              <TableHead>Detalhes</TableHead>
              <TableHead className="text-right">Ações</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading && espelhos.length > 0 ? (
              <TableRow><TableCell colSpan={4} className="text-center py-6">Carregando...</TableCell></TableRow>
            ) : espelhos.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} className="text-center py-6 text-muted-foreground">
                  Nenhum espelho gerado nesta competência (feche a competência para gerar).
                </TableCell>
              </TableRow>
            ) : espelhos.map((e) => {
              const s = porEspelho.get(e.id);
              const selo = seloDoEspelho(e, s);
              const detalhes: string[] = [];
              if (s?.enviado_em) detalhes.push(`enviado em ${dataHora(s.enviado_em)}`);
              if (s?.visualizado_em && ativa(s)) detalhes.push(`visto em ${dataHora(s.visualizado_em)}`);
              if (s?.respondido_em) detalhes.push(`respondido em ${dataHora(s.respondido_em)}`);
              if (s && ativa(s) && s.expira_em) detalhes.push(`prazo ${format(new Date(s.expira_em), "dd/MM")}`);
              if (s && s.lembretes_enviados > 0 && ativa(s)) detalhes.push(`${s.lembretes_enviados} lembrete(s)`);
              if (s?.envio_erro && ativa(s)) detalhes.push("e-mail não saiu: copie o link");
              if ((s?.autenticacao as { sem_prova_vida?: boolean } | null)?.sem_prova_vida && !ativa(s)) detalhes.push("sem prova de vida (recusou câmera)");
              if (s?.decisao_texto) detalhes.push(`"${s.decisao_texto}"`);
              return (
                <TableRow key={e.id}>
                  <TableCell className="font-medium">{e.colaborador_nome}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className={selo.classe}>{selo.rotulo}</Badge>
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground max-w-[360px]">{detalhes.join(" · ") || "—"}</TableCell>
                  <TableCell>
                    <div className="flex justify-end gap-1">
                      {podeEnviar(e, s) && (
                        <Button size="sm" variant="outline" onClick={() => handleEnviar(e)} disabled={enviandoId !== null}>
                          {enviandoId === e.id ? <Loader2 className="w-4 h-4 mr-1 animate-spin" /> : <Send className="w-4 h-4 mr-1" />}
                          {s?.status === "contestado" || e.status === "contestado" ? "Reenviar corrigido" : "Enviar"}
                        </Button>
                      )}
                      {s && ativa(s) && (
                        <>
                          <Button size="sm" variant="ghost" title="Copiar link novo" onClick={() => handleNovoLink(e, s)}>
                            <Link2 className="w-4 h-4" />
                          </Button>
                          <Button size="sm" variant="ghost" title="Reenviar e-mail" onClick={() => reenviar.mutate(s.id)}>
                            <Mail className="w-4 h-4" />
                          </Button>
                          <Button size="sm" variant="ghost" title="Cancelar envio" className="text-destructive"
                            onClick={() => cancelar.mutate({ solicitacaoId: s.id })}>
                            <XCircle className="w-4 h-4" />
                          </Button>
                        </>
                      )}
                      {s?.assinado_path && (
                        <Button size="sm" variant="ghost" title="Ver PDF assinado (com o manifesto)" onClick={() => verAssinado(s)}>
                          <FileCheck2 className="w-4 h-4" />
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </CardContent>

      <Dialog open={!!link} onOpenChange={(v) => { if (!v) setLink(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Link de assinatura — {link?.nome}</DialogTitle>
            <DialogDescription>
              {link?.aviso} Este link aparece só agora: se precisar de novo, use "Copiar link novo" (o anterior deixa de valer).
            </DialogDescription>
          </DialogHeader>
          <Input readOnly value={link?.url || ""} onFocus={(ev) => ev.currentTarget.select()} data-testid="link-assinatura" />
          <DialogFooter className="gap-2">
            <Button variant="outline" asChild>
              <a href={`https://wa.me/?text=${encodeURIComponent(`Seu espelho de ponto está disponível para conferência: ${link?.url || ""}`)}`}
                 target="_blank" rel="noopener noreferrer">WhatsApp</a>
            </Button>
            <Button onClick={copiar}><Copy className="w-4 h-4 mr-1" /> Copiar link</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
