import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useTenant } from "@/hooks/useTenant";
import { usePontoFechamento } from "@/hooks/usePontoFechamento";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { FileDown, FileSpreadsheet, Send, CheckCircle } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import * as XLSX from "xlsx";
import { formatarHoraRelogio } from "@/lib/ponto/formatoHoras";
import { useFeriadoAdicionalCompetencia } from "@/hooks/usePontoFeriados";
import { IncluirBancoHorasDialog } from "@/components/ponto/IncluirBancoHorasDialog";
import { usePontoBancoHoras } from "@/hooks/usePontoBancoHoras";
import { AcaoProtegida } from "@/components/shared/AcaoProtegida";

type FormatoExport = "csv" | "txt" | "xlsx";

const SISTEMAS_DESTINO = [
  { value: "generico", label: "Genérico (padrão)" },
  { value: "totvs", label: "TOTVS / Protheus" },
  { value: "senior", label: "Senior Sistemas" },
  { value: "adp", label: "ADP" },
  { value: "sap", label: "SAP SuccessFactors" },
  { value: "dominio", label: "Domínio Sistemas" },
  { value: "outro", label: "Outro" },
];

export function PontoFolhaTab() {
  const { profile } = useAuth();
  const { tenantId } = useTenant();
  const queryClient = useQueryClient();
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const [formato, setFormato] = useState<FormatoExport>("xlsx");
  const [sistemaDestino, setSistemaDestino] = useState("generico");
  const [gerando, setGerando] = useState(false);
  const [perguntandoBanco, setPerguntandoBanco] = useState(false);

  const { useBancoHorasPorCompetencia, useBancoHorasOficial } = usePontoBancoHoras();
  const { data: bancosHoras = [] } = useBancoHorasPorCompetencia(competencia);

  /**
   * Quem tem instrumento de compensação vigente NÃO leva hora extra para a
   * folha: o excedente já virou crédito no banco (CLT art. 59, §2º). Emitir a
   * mesma hora nas duas pontas é pagar duas vezes o que já foi creditado —
   * apontado na auditoria de DP de 01/09/2026, que viu os mesmos 1h51
   * aparecerem como "Horas extras" e como "Crédito Banco de Horas".
   * Sem regime vigente, as horas são devidas em dinheiro e seguem para a
   * folha normalmente (art. 59, §1º).
   */
  const { data: bancoOficial = [] } = useBancoHorasOficial(competencia);
  const emBancoDeHoras = (cpf: string) => {
    const d = String(cpf || "").replace(/\D/g, "");
    const o: any = (bancoOficial as any[]).find(
      (x) => String(x.colaborador_cpf || "").replace(/\D/g, "") === d,
    );
    return o?.tem_regime === true;
  };
  const soDigitos = (v: string) => String(v || "").replace(/\D/g, "");
  const bancoDoCpf = (cpf: string) =>
    bancosHoras.find((b: any) => soDigitos(b.colaborador_cpf) === soDigitos(cpf));

  const { useEspelhos } = usePontoFechamento();
  const { data: espelhos = [] } = useEspelhos(competencia);

  const { data: exportacoes = [] } = useQuery({
    queryKey: ["ponto-exportacoes-folha", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("ponto_exportacoes_folha")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false })
        .limit(20) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const formatMinutos = (min: number) => formatarHoraRelogio(min);

  // RN23 — feriado trabalhado sem folga compensatória vai para a folha com
  // adicional de 100% (Lei 605/1949, art. 9º; Súmula 146 TST), sem depender
  // de lançamento manual do RH. Vem da apuração, não do espelho: a coluna
  // legada de HE 100% do espelho não cobre feriado.
  const { data: feriadoAdicional = [] } = useFeriadoAdicionalCompetencia(null, competencia);
  const feriadoPorCpf = new Map<string, number>();
  feriadoAdicional.forEach((f) => {
    feriadoPorCpf.set(String(f.colaborador_cpf).replace(/\D/g, ""), Number(f.minutos_adicional_100) || 0);
  });
  const feriadoMinDoCpf = (cpf: string) => feriadoPorCpf.get(String(cpf || "").replace(/\D/g, "")) || 0;


  const gerarDadosFolha = () => {
    return espelhos.map((e: any) => {
      // Hora que foi para o banco não vai para a folha: já foi creditada.
      const noBanco = emBancoDeHoras(e.colaborador_cpf);
      return ({
      cpf: e.colaborador_cpf,
      nome: e.colaborador_nome,
      competencia: competencia,
      em_banco_de_horas: noBanco,
      dias_trabalhados: e.total_dias_trabalhados || 0,
      horas_normais_min: (e.total_dias_trabalhados || 0) * 480,
      he_50_min: noBanco ? 0 : (e.total_horas_extras_50_minutos || 0),
      he_100_min: noBanco ? 0 : (e.total_horas_extras_100_minutos || 0),
      he_creditada_banco_min: noBanco
        ? (e.total_horas_extras_50_minutos || 0) + (e.total_horas_extras_100_minutos || 0)
        : 0,
      adicional_noturno_min: e.total_adicional_noturno_minutos || 0,
      feriado_100_min: feriadoMinDoCpf(e.colaborador_cpf),
      faltas: e.total_faltas || 0,
      atrasos_min: e.total_atrasos_minutos || 0,
      dsr_descontar: e.total_faltas > 0 ? 1 : 0,
    });
    });
  };

  const gerarExportacao = async (comBanco: boolean) => {
    if (espelhos.length === 0) {
      toast.warning("Nenhum espelho encontrado para esta competência. Faça o fechamento primeiro.");
      return;
    }

    setGerando(true);
    try {
      const dados = gerarDadosFolha();
      let conteudo: string | Blob;
      let nomeArquivo: string;
      let mimeType: string;

      if (formato === "xlsx") {
        const wsData = dados.map(d => {
          const b: any = comBanco ? bancoDoCpf(d.cpf) : null;
          return ({
          "CPF": d.cpf,
          "Nome": d.nome,
          "Competência": d.competencia,
          "Dias Trabalhados": d.dias_trabalhados,
          "Horas Normais": formatMinutos(d.horas_normais_min),
          "HE 50%": formatMinutos(d.he_50_min),
          "HE 100%": formatMinutos(d.he_100_min),
          "Adic. Noturno": formatMinutos(d.adicional_noturno_min),
          "Feriado 100%": formatMinutos(d.feriado_100_min),
          "Faltas": d.faltas,
          "Atrasos": formatMinutos(d.atrasos_min),
          "DSR Descontar": d.dsr_descontar,
          // Onde as horas foram parar. Sem esta coluna, o HE zerado de quem
          // esta em banco parece erro de apuracao em vez de decisao correta.
          "Destino do Excedente": d.em_banco_de_horas
            ? `Banco de horas (${formatMinutos(d.he_creditada_banco_min)} creditados 1:1)`
            : "A pagar na folha",
          ...(comBanco ? {
            "BH Saldo Anterior": formatMinutos(b?.saldo_anterior_minutos || 0),
            "BH Créditos": formatMinutos(b?.creditos_minutos || 0),
            "BH Débitos": formatMinutos(b?.debitos_minutos || 0),
            "BH Compensados": formatMinutos(b?.compensados_minutos || 0),
            "BH Saldo Atual": formatMinutos(b?.saldo_atual_minutos || 0),
          } : {}),
        });
        });
        const ws = XLSX.utils.json_to_sheet(wsData);
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, "Folha");
        XLSX.writeFile(wb, `Folha_${competencia}.xlsx`);
        nomeArquivo = `Folha_${competencia}.xlsx`;
      } else if (formato === "csv") {
        const headers = "CPF;NOME;COMPETENCIA;DIAS_TRAB;HORAS_NORMAIS;HE_50;HE_100;ADIC_NOT;FALTAS;ATRASOS;DSR_DESC;FERIADO_100";
        const linhas = dados.map(d =>
          `${d.cpf};${d.nome};${d.competencia};${d.dias_trabalhados};${d.horas_normais_min};${d.he_50_min};${d.he_100_min};${d.adicional_noturno_min};${d.faltas};${d.atrasos_min};${d.dsr_descontar};${d.feriado_100_min}`
        );
        conteudo = [headers, ...linhas].join("\n");
        nomeArquivo = `Folha_${competencia}.csv`;
        mimeType = "text/csv;charset=utf-8";

        const blob = new Blob([conteudo], { type: mimeType });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = nomeArquivo;
        a.click();
        URL.revokeObjectURL(url);
      } else {
        // TXT (layout posicional)
        const linhas = dados.map(d => {
          const cpf = d.cpf.padEnd(14);
          const nome = d.nome.substring(0, 40).padEnd(40);
          const dias = String(d.dias_trabalhados).padStart(3, "0");
          const he50 = String(d.he_50_min).padStart(5, "0");
          const he100 = String(d.he_100_min).padStart(5, "0");
          const noturno = String(d.adicional_noturno_min).padStart(5, "0");
          const faltas = String(d.faltas).padStart(3, "0");
          const atrasos = String(d.atrasos_min).padStart(5, "0");
          const feriado100 = String(d.feriado_100_min).padStart(5, "0");
          return `${cpf}${nome}${dias}${he50}${he100}${noturno}${faltas}${atrasos}${feriado100}`;
        });
        conteudo = linhas.join("\n");
        nomeArquivo = `Folha_${competencia}.txt`;

        const blob = new Blob([conteudo], { type: "text/plain;charset=utf-8" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = nomeArquivo;
        a.click();
        URL.revokeObjectURL(url);
      }

      // Registrar exportação
      await fromTable("ponto_exportacoes_folha")
        .insert({
          tenant_id: tenantId,
          competencia,
          formato,
          sistema_destino: sistemaDestino,
          total_colaboradores: dados.length,
          arquivo_nome: `Folha_${competencia}.${formato}`,
          status: "gerado",
          gerado_por: profile?.nome_completo,
          gerado_por_id: profile?.id,
          dados_exportados: { total: dados.length, sistema: sistemaDestino },
        } as any);

      queryClient.invalidateQueries({ queryKey: ["ponto-exportacoes-folha"] });
      toast.success(`Exportação gerada: ${dados.length} colaboradores`);
    } catch (err: any) {
      toast.error("Erro: " + (err.message || "erro desconhecido"));
    } finally {
      setGerando(false);
    }
  };

  return (
    <div className="space-y-4">
      <IncluirBancoHorasDialog
        open={perguntandoBanco}
        onOpenChange={setPerguntandoBanco}
        titulo="Incluir banco de horas na exportação?"
        onConfirm={(comBanco) => {
          setPerguntandoBanco(false);
          gerarExportacao(comBanco);
        }}
      />
      <div>
        <h3 className="text-lg font-semibold flex items-center gap-2">
          <FileSpreadsheet className="w-5 h-5 text-primary" /> Integração Folha de Pagamento
        </h3>
        <p className="text-sm text-muted-foreground">Exporte dados estruturados para o sistema de folha de pagamento</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="space-y-2">
          <Label>Competência</Label>
          <CompetenciaInput value={competencia} onChange={setCompetencia} />
        </div>
        <div className="space-y-2">
          <Label>Sistema Destino</Label>
          <Select value={sistemaDestino} onValueChange={setSistemaDestino}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {SISTEMAS_DESTINO.map(s => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Formato</Label>
          <Select value={formato} onValueChange={v => setFormato(v as FormatoExport)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="xlsx">Excel (.xlsx)</SelectItem>
              <SelectItem value="csv">CSV (;)</SelectItem>
              <SelectItem value="txt">TXT (posicional)</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>&nbsp;</Label>
          <AcaoProtegida modulo="colaboradores" acao="exportar" modo="desabilitar"
            motivo="Seu perfil de acesso não permite exportar a folha de ponto.">
            <Button onClick={() => setPerguntandoBanco(true)} disabled={gerando} className="w-full">
              <FileDown className="w-4 h-4 mr-2" />
              {gerando ? "Gerando..." : "Exportar"}
            </Button>
          </AcaoProtegida>
        </div>
      </div>

      {/* Dados que serão exportados */}
      <Card>
        <CardHeader><CardTitle className="text-base">Prévia dos Dados ({espelhos.length} colaboradores)</CardTitle></CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-center">Dias Trab.</TableHead>
                <TableHead className="text-center">HE 50%</TableHead>
                <TableHead className="text-center">HE 100%</TableHead>
                <TableHead className="text-center">Noturno</TableHead>
                <TableHead className="text-center">Feriado 100%</TableHead>
                <TableHead className="text-center">Faltas</TableHead>
                <TableHead className="text-center">Atrasos</TableHead>
                <TableHead>Destino do excedente</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {espelhos.length === 0 ? (
                <TableRow><TableCell colSpan={9} className="text-center py-8 text-muted-foreground">Faça o fechamento da competência para ver os dados.</TableCell></TableRow>
              ) : espelhos.map((e: any) => {
                // A prévia mostra o que SERÁ exportado. Mostrar aqui a hora
                // extra cheia e exportar zero seria pior que o erro original.
                const noBanco = emBancoDeHoras(e.colaborador_cpf);
                const he50 = noBanco ? 0 : (e.total_horas_extras_50_minutos || 0);
                const he100 = noBanco ? 0 : (e.total_horas_extras_100_minutos || 0);
                return (
                <TableRow key={e.id}>
                  <TableCell className="font-medium">{e.colaborador_nome}</TableCell>
                  <TableCell className="text-center">{e.total_dias_trabalhados || 0}</TableCell>
                  <TableCell className="text-center">{formatMinutos(he50)}</TableCell>
                  <TableCell className="text-center">{formatMinutos(he100)}</TableCell>
                  <TableCell className="text-center">{formatMinutos(e.total_adicional_noturno_minutos || 0)}</TableCell>
                  <TableCell className="text-center">{formatMinutos(feriadoMinDoCpf(e.colaborador_cpf))}</TableCell>
                  <TableCell className="text-center">{e.total_faltas || 0}</TableCell>
                  <TableCell className="text-center">{formatMinutos(e.total_atrasos_minutos || 0)}</TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {noBanco
                      ? `Banco de horas — ${formatMinutos(
                          (e.total_horas_extras_50_minutos || 0) + (e.total_horas_extras_100_minutos || 0),
                        )} creditados 1:1, não vão para a folha`
                      : "A pagar na folha"}
                  </TableCell>
                </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Histórico */}
      {exportacoes.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Histórico de Exportações</CardTitle></CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Competência</TableHead>
                  <TableHead>Sistema</TableHead>
                  <TableHead>Formato</TableHead>
                  <TableHead className="text-center">Colaboradores</TableHead>
                  <TableHead>Gerado por</TableHead>
                  <TableHead>Data</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {exportacoes.map((exp: any) => (
                  <TableRow key={exp.id}>
                    <TableCell className="font-medium">{exp.competencia}</TableCell>
                    <TableCell>{SISTEMAS_DESTINO.find(s => s.value === exp.sistema_destino)?.label || exp.sistema_destino}</TableCell>
                    <TableCell><Badge variant="outline">{exp.formato?.toUpperCase()}</Badge></TableCell>
                    <TableCell className="text-center">{exp.total_colaboradores}</TableCell>
                    <TableCell>{exp.gerado_por || "N/I"}</TableCell>
                    <TableCell>{format(new Date(exp.created_at), "dd/MM/yyyy HH:mm")}</TableCell>
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
