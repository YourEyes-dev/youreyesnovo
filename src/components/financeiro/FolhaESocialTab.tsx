import { useState, useMemo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useTenant } from "@/hooks/useTenant";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { FileCode, Send, DollarSign, Building2, RefreshCw, Gift, ShieldCheck, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { useDecimoTerceiroESocial, type ValidacaoESocial13 } from "@/hooks/useDecimoTerceiroESocial";
import {
  gerarEventoS1200,
  gerarEventoS1210,
  gerarResumoDCTFWeb,
  gerarResumoFGTSDigital,
} from "@/lib/folha/integracoes-fiscais";

export function FolhaESocialTab() {
  const { tenantId } = useTenant();
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const [gerando, setGerando] = useState(false);

  // ── 13º salário: apuração ANUAL própria, separada da folha mensal ──
  const [ano13, setAno13] = useState(new Date().getFullYear());
  const [validacao13, setValidacao13] = useState<ValidacaoESocial13 | null>(null);
  const esocial13 = useDecimoTerceiroESocial();

  const { data: eventos13 = [], refetch: recarregarEventos13 } = useQuery({
    queryKey: ["esocial-13", tenantId, ano13],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await supabase
        .from("esocial_transmissoes" as any)
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("origem_modulo", "decimo_terceiro")
        .eq("ano", ano13)
        .order("created_at", { ascending: false }) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const validar13 = async () => {
    try {
      const r = await esocial13.validar(ano13);
      setValidacao13(r);
      if (!r) return;
      if (r.pode_transmitir) {
        toast.success(`13º de ${ano13}: ${r.aptos} cálculo(s) aptos para o eSocial.`);
      } else if (r.aptos === 0 && r.com_problema === 0) {
        toast.warning(`Nenhum cálculo de 13º encontrado para ${ano13}.`);
      } else {
        toast.warning(`${r.com_problema} pendência(s) a corrigir antes de montar os eventos.`);
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Falha na validação do 13º.");
    }
  };

  const gerar13 = async (tipo: "S-1200" | "S-1210") => {
    try {
      const r = await esocial13.gerar(ano13, tipo);
      toast.success(
        `${tipo}: ${r.eventos_gerados} evento(s) montado(s)` +
        (r.ja_existiam ? `, ${r.ja_existiam} já existia(m).` : ".") +
        " Os eventos ficam PENDENTES — a transmissão é um passo à parte."
      );
      recarregarEventos13();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Falha ao montar os eventos do 13º.");
    }
  };

  // Buscar folha items da competência
  const { data: folhaItens = [] } = useQuery({
    queryKey: ["folha-itens-esocial", tenantId, competencia],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await supabase
        .from("folha_itens" as any)
        .select("*")
        .eq("tenant_id", tenantId)
        .eq("competencia", competencia) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  // Gerar resumos em memória
  const resumos = useMemo(() => {
    if (folhaItens.length === 0) return null;

    const totalRemuneracao = folhaItens.reduce((s: number, i: any) => s + (i.total_proventos || i.salario_base || 0), 0);
    const totalINSS = folhaItens.reduce((s: number, i: any) => s + (i.valor_inss || 0), 0);

    const dctfweb = gerarResumoDCTFWeb({
      competencia,
      totalColaboradores: folhaItens.length,
      totalRemuneracao,
      totalINSSEmpregados: totalINSS,
    });

    const fgtsDigital = gerarResumoFGTSDigital({
      competencia,
      colaboradores: folhaItens.map((i: any) => ({
        cpf: i.colaborador_cpf || "000.000.000-00",
        nome: i.colaborador_nome || "N/I",
        remuneracao: i.total_proventos || i.salario_base || 0,
        aliquotaFGTS: 8,
      })),
    });

    // Gerar S-1200 para cada colaborador
    const eventosS1200 = folhaItens.map((i: any) =>
      gerarEventoS1200({
        competencia,
        cpf: i.colaborador_cpf || "",
        proventos: [{ descricao: "Salário Base", tipo: "salario_base", valor: i.salario_base || 0 }],
        descontos: [
          { descricao: "INSS", tipo: "desc_inss", valor: i.valor_inss || 0 },
          { descricao: "IRRF", tipo: "desc_irrf", valor: i.valor_irrf || 0 },
        ],
      })
    );

    return { dctfweb, fgtsDigital, eventosS1200 };
  }, [folhaItens, competencia]);

  const gerarEventos = () => {
    if (!resumos || folhaItens.length === 0) {
      toast.warning("Sem dados de folha para gerar eventos.");
      return;
    }
    toast.success(`Eventos eSocial gerados: ${resumos.eventosS1200.length} S-1200 preparados para ${competencia}.`);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <FileCode className="w-5 h-5 text-primary" /> eSocial & Integrações Fiscais
          </h3>
          <p className="text-sm text-muted-foreground">Geração de eventos S-1200/S-1210, DCTFWeb e FGTS Digital</p>
        </div>
        <div className="flex items-center gap-3">
          <CompetenciaInput value={competencia} onChange={setCompetencia} />
          <Button onClick={gerarEventos} size="sm">
            <Send className="w-4 h-4 mr-1" /> Gerar Eventos
          </Button>
        </div>
      </div>

      {/* Cards resumo */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* DCTFWeb */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <Building2 className="w-4 h-4" /> DCTFWeb
            </CardTitle>
          </CardHeader>
          <CardContent>
            {resumos ? (
              <div className="space-y-2 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">INSS Empregados</span><span className="font-medium">R$ {resumos.dctfweb.inss_empregados.toFixed(2)}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">INSS Patronal (20%)</span><span className="font-medium">R$ {resumos.dctfweb.inss_patronal.toFixed(2)}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">RAT</span><span className="font-medium">R$ {resumos.dctfweb.rat.toFixed(2)}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">Terceiros</span><span className="font-medium">R$ {resumos.dctfweb.terceiros.toFixed(2)}</span></div>
                <div className="flex justify-between border-t pt-2"><span className="font-semibold">Total</span><span className="font-bold text-primary">R$ {resumos.dctfweb.totalContribuicoes.toFixed(2)}</span></div>
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">Sem dados para esta competência.</p>
            )}
          </CardContent>
        </Card>

        {/* FGTS Digital */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <DollarSign className="w-4 h-4" /> FGTS Digital
            </CardTitle>
          </CardHeader>
          <CardContent>
            {resumos ? (
              <div className="space-y-2 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">Colaboradores</span><span className="font-medium">{resumos.fgtsDigital.totalColaboradores}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">Base de Cálculo</span><span className="font-medium">R$ {resumos.fgtsDigital.baseCalculo.toFixed(2)}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">Alíquota Média</span><span className="font-medium">{resumos.fgtsDigital.aliquotaMedia}%</span></div>
                <div className="flex justify-between border-t pt-2"><span className="font-semibold">Total FGTS</span><span className="font-bold text-primary">R$ {resumos.fgtsDigital.valorTotal.toFixed(2)}</span></div>
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">Sem dados para esta competência.</p>
            )}
          </CardContent>
        </Card>

        {/* Eventos eSocial */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <FileCode className="w-4 h-4" /> Eventos eSocial
            </CardTitle>
          </CardHeader>
          <CardContent>
            {resumos ? (
              <div className="space-y-2 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">S-1200 (Remuneração)</span><Badge variant="outline">{resumos.eventosS1200.length}</Badge></div>
                <div className="flex justify-between"><span className="text-muted-foreground">S-1210 (Pagamentos)</span><Badge variant="secondary">Pendente</Badge></div>
                <div className="flex justify-between"><span className="text-muted-foreground">Ambiente</span><Badge className="bg-yellow-500/10 text-yellow-700 border-yellow-200">Homologação</Badge></div>
                <div className="flex justify-between border-t pt-2"><span className="text-muted-foreground">Status</span><Badge>Apurado</Badge></div>
              </div>
            ) : (
              <p className="text-sm text-muted-foreground">Sem dados para esta competência.</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ── 13º salário: apuração anual (indApuracao = 2) ── */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between flex-wrap gap-3">
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                <Gift className="w-4 h-4 text-primary" /> 13º salário — apuração anual
              </CardTitle>
              <p className="text-sm text-muted-foreground mt-1">
                O 13º não entra na folha do mês: vai no S-1200 com apuração <strong>anual</strong> e nos
                pagamentos do S-1210. Valide antes — é onde se evita a rejeição.
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Label htmlFor="ano13" className="text-sm">Ano</Label>
              <input
                id="ano13"
                type="number"
                className="h-9 w-24 rounded-md border border-input bg-background px-2 text-sm"
                value={ano13}
                onChange={(e) => { setAno13(Number(e.target.value)); setValidacao13(null); }}
              />
              <Button size="sm" variant="outline" onClick={validar13} disabled={esocial13.ocupado}>
                <ShieldCheck className="w-4 h-4 mr-1" /> Validar 13º
              </Button>
              <Button size="sm" onClick={() => gerar13("S-1200")} disabled={esocial13.ocupado}>
                <Send className="w-4 h-4 mr-1" /> Gerar S-1200
              </Button>
              <Button size="sm" variant="secondary" onClick={() => gerar13("S-1210")} disabled={esocial13.ocupado}>
                <Send className="w-4 h-4 mr-1" /> Gerar S-1210
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {validacao13 && (
            <div className="rounded-md border p-3 text-sm">
              <div className="flex items-center gap-2 font-medium">
                {validacao13.pode_transmitir ? (
                  <><ShieldCheck className="w-4 h-4 text-green-600" /> {validacao13.aptos} cálculo(s) aptos — pode montar os eventos.</>
                ) : (
                  <><AlertTriangle className="w-4 h-4 text-amber-600" /> {validacao13.com_problema} pendência(s) a corrigir.</>
                )}
              </div>
              {validacao13.problemas.length > 0 && (
                <ul className="mt-2 space-y-1 text-muted-foreground">
                  {validacao13.problemas.map((p) => (
                    <li key={`${p.calculo_id}-${p.parcela}`}>
                      • <strong>{p.colaborador}</strong> (parcela {p.parcela}): {p.problema}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}

          {eventos13.length > 0 ? (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Evento</TableHead>
                  <TableHead>CPF</TableHead>
                  <TableHead className="text-center">Apuração</TableHead>
                  <TableHead className="text-center">Período</TableHead>
                  <TableHead className="text-center">Parcela</TableHead>
                  <TableHead className="text-center">Leiaute</TableHead>
                  <TableHead className="text-center">Situação</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {eventos13.map((ev: any) => (
                  <TableRow key={ev.id}>
                    <TableCell className="font-mono text-xs">{ev.tipo_evento}</TableCell>
                    <TableCell>{String(ev.colaborador_cpf || "").replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4")}</TableCell>
                    <TableCell className="text-center">{ev.ind_apuracao === 2 ? "Anual" : "Mensal"}</TableCell>
                    <TableCell className="text-center">{ev.periodo_apuracao}</TableCell>
                    <TableCell className="text-center">{ev.parcela ?? "—"}</TableCell>
                    <TableCell className="text-center">{ev.leiaute_versao}</TableCell>
                    <TableCell className="text-center"><Badge variant="secondary">{ev.status}</Badge></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <p className="text-sm text-muted-foreground">
              Nenhum evento de 13º montado para {ano13}.
            </p>
          )}

          <p className="text-xs text-muted-foreground border-t pt-3">
            Os eventos são <strong>montados e conferidos</strong>, não enviados: a transmissão depende de
            certificado digital, procuração eletrônica e do ambiente do eSocial. Confira também a versão do
            leiaute vigente na data do envio — leiaute desatualizado é a causa mais comum de rejeição.
          </p>
        </CardContent>
      </Card>

      {/* Detalhamento S-1200 */}
      {resumos && resumos.eventosS1200.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Eventos S-1200 — Remuneração ({competencia})</CardTitle></CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>ID Evento</TableHead>
                  <TableHead>CPF</TableHead>
                  <TableHead className="text-center">Rubricas</TableHead>
                  <TableHead className="text-center">Ambiente</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {resumos.eventosS1200.map((ev) => (
                  <TableRow key={ev.id}>
                    <TableCell className="font-mono text-xs">{ev.id}</TableCell>
                    <TableCell>{ev.cpfTrab.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4")}</TableCell>
                    <TableCell className="text-center">{ev.dmDev[0]?.itensRemun.length || 0}</TableCell>
                    <TableCell className="text-center">
                      <Badge variant={ev.tpAmb === 1 ? "default" : "secondary"}>
                        {ev.tpAmb === 1 ? "Produção" : "Homologação"}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
