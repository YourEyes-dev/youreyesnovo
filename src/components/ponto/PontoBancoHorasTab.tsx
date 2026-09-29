import { useState, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog";
import { usePontoBancoHoras, type BancoHoras } from "@/hooks/usePontoBancoHoras";
import { useColaboradores } from "@/hooks/useColaboradores";
import { ColaboradorSelect } from "@/components/shared/ColaboradorSelect";
import { useAuth } from "@/hooks/useAuth";
import { usePontoEqualizacao, usePontoEqualizacaoGerenciador } from "@/hooks/usePontoEqualizacao";
import { format } from "date-fns";
import { Wallet, Plus, ArrowUpRight, ArrowDownRight, RefreshCw, TrendingUp, TrendingDown, Upload, Download, FileSpreadsheet, Pencil, Trash2, CalendarDays, Search, Info, Minus } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { confirm } from "@/components/ui/confirm-dialog";
import { toast } from "sonner";
import * as XLSX from "xlsx";
import { formatarHoraMinuto, abreviacaoDiaSemana, rotuloTipoDia } from "@/lib/ponto/diaSemana";
import { ExcedenteRetidoPanel } from "./ExcedenteRetidoPanel";
import { useFeriadosCompetencia, useFolgaCompensatoria } from "@/hooks/usePontoFeriados";
import { FolgaCompensatoriaDialog } from "./FolgaCompensatoriaDialog";

export function PontoBancoHorasTab() {
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const [busca, setBusca] = useState("");
  const [memoriaEq, setMemoriaEq] = useState<Record<string, any> | null>(null);
  const { data: equalizacoes = [] } = usePontoEqualizacao(competencia);
  const [gerenciarEq, setGerenciarEq] = useState(false);
  const [art61, setArt61] = useState<{ cpf: string; nome: string; justificativa: string } | null>(null);
  const {
    colaboradores: eqColaboradores,
    definir: definirEq,
    remover: removerEq,
    liberarArt61,
  } = usePontoEqualizacaoGerenciador(competencia);
  const eqComDeficit = equalizacoes.filter((e) => (e.total_equalizacao_min || 0) > 0);
  const [colaboradorFiltroId, setColaboradorFiltroId] = useState<string>("");
  const [reapuracaoResumo, setReapuracaoResumo] = useState<null | {
    registros_processados?: number;
    registros_ajustados?: number;
    detalhes?: Array<{
      colaborador_nome: string | null;
      competencia: string;
      saldo_antes_minutos: number;
      saldo_depois_minutos: number;
      diferenca_minutos: number;
    }>;
  }>(null);

  const {
    useBancoHorasPorCompetencia,
    useBancoHorasOficial,
    useMovimentacoes,
    adicionarMovimentacao,
    adicionandoMovimentacao,
    editarMovimentacao,
    editandoMovimentacao,
    excluirMovimentacao,
    criarBancoHoras,
    criandoBancoHoras,
    editarBancoHoras,
    editandoBancoHoras,
    excluirBancoHoras,
    apurarBancoHoras,
    apurandoBancoHoras,
    reapurarCompetencias,
    reapurandoCompetencias,
  } = usePontoBancoHoras();

  const { colaboradores } = useColaboradores();
  const { tenantId } = useAuth();

  const { data: bancos = [], isLoading } = useBancoHorasPorCompetencia(competencia);
  // Fonte única ao vivo: mesma do detalhamento e do relatório. A tabela abaixo
  // sobrepõe estes números na fotografia (que pode estar defasada).
  const { data: bancoOficial = [] } = useBancoHorasOficial(competencia);
  const [selectedBanco, setSelectedBanco] = useState<BancoHoras | null>(null);
  const { data: movimentacoes = [] } = useMovimentacoes(selectedBanco?.id || null);

  const [showCriar, setShowCriar] = useState(false);
  const [showMovimentacao, setShowMovimentacao] = useState(false);
  const [showImport, setShowImport] = useState(false);
  const [importando, setImportando] = useState(false);
  const [importResumo, setImportResumo] = useState<{ ok: number; erros: string[] } | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [criarForm, setCriarForm] = useState({ colaborador_id: "", tipo: "mensal" });
  const [movForm, setMovForm] = useState({ tipo: "credito", minutos: 0, data_referencia: format(new Date(), "yyyy-MM-dd"), descricao: "" });
  const [editMov, setEditMov] = useState<null | { id: string; tipo: string; minutos: number; data_referencia: string; descricao: string }>(null);
  const [editBanco, setEditBanco] = useState<null | {
    id: string;
    colaborador_id: string;
    colaborador_cpf: string;
    colaborador_nome: string;
    tipo: string;
    competencia: string;
    saldo_anterior_minutos: number;
    saldo_anterior_horas: number;
    saldo_anterior_mins: number;
    saldo_anterior_negativo: boolean;
    creditos_minutos: number;
    debitos_minutos: number;
    compensados_minutos: number;
    prazo_compensacao: string;
    observacoes: string;
  }>(null);

  // RN19: minutos sempre com dois dígitos ("8h 08min").
  const formatMinutos = (min: number) => formatarHoraMinuto(min);

  const handleCriar = async () => {
    const colab = colaboradores.find(c => c.id === criarForm.colaborador_id);
    if (!colab) { toast.error("Selecione um colaborador"); return; }
    await criarBancoHoras({
      colaborador_id: colab.id,
      colaborador_nome: colab.nome_completo,
      colaborador_cpf: colab.cpf,
      tipo: criarForm.tipo,
      competencia,
    });
    setShowCriar(false);
  };

  const handleApurar = async () => {
    const ok = await confirm({
      title: `Apurar banco de horas — ${competencia}`,
      description:
        "O sistema vai calcular créditos (horas além da jornada) e débitos (atrasos, faltas e saídas antecipadas) a partir do ponto de cada colaborador, comparando com a jornada da escala. Lançamentos manuais são preservados; apenas os valores apurados anteriores são substituídos.",
      confirmLabel: "Apurar agora",
    });
    if (!ok) return;
    await apurarBancoHoras(competencia);
  };

  const handleReapurarFechadas = async () => {
    const ok = await confirm({
      title: "Reapurar competências já fechadas",
      description:
        "O sistema vai recalcular todas as competências já registradas no banco de horas, aplicando as regras vigentes de tolerância e jornada. Lançamentos manuais são preservados; apenas os valores apurados são atualizados.",
      confirmLabel: "Reapurar agora",
    });
    if (!ok) return;
    const res = await reapurarCompetencias({});
    setReapuracaoResumo(res?.detalhes?.length ? res : null);
  };



  const handleMovimentacao = async () => {
    if (!selectedBanco || movForm.minutos <= 0) { toast.error("Preencha os dados"); return; }
    await adicionarMovimentacao({
      bancoHorasId: selectedBanco.id,
      colaboradorCpf: selectedBanco.colaborador_cpf || "",
      dataReferencia: movForm.data_referencia,
      tipo: movForm.tipo,
      minutos: movForm.minutos,
      descricao: movForm.descricao,
    });
    setShowMovimentacao(false);
    setMovForm({ tipo: "credito", minutos: 0, data_referencia: format(new Date(), "yyyy-MM-dd"), descricao: "" });
  };

  // Dias do colaborador em edição (ponto_diario da competência)
  const editComp = editBanco?.competencia || "";
  const editIniFim = (() => {
    if (!editComp || !/^\d{4}-\d{2}$/.test(editComp)) return null;
    const [y, m] = editComp.split("-").map(Number);
    const lastDay = new Date(y, m, 0).getDate(); // dia 0 do mês seguinte = último dia do mês atual
    const mm = String(m).padStart(2, "0");
    const dd = String(lastDay).padStart(2, "0");
    return { ini: `${editComp}-01`, fim: `${editComp}-${dd}` };
  })();
  // Movimentações MANUAIS do banco em edição. A listagem soma todas as
  // movimentações (apuradas + manuais); o resumo da edição só considerava os
  // dias com ponto, e por isso divergia sempre que havia lançamento manual.
  // Aqui buscamos só as manuais — as apuradas já estão representadas pelos
  // dias com ponto, somá-las seria contar duas vezes.
  const { data: movsManuaisEdit = [] } = useQuery({
    queryKey: [
      "banco-horas-movs-manuais",
      editBanco?.colaborador_cpf,
      editComp,
      tenantId,
    ],
    enabled: !!editBanco?.colaborador_cpf && !!editComp && !!tenantId,
    queryFn: async () => {
      // Buscamos manuais por (tenant + cpf + competência), não só por
      // banco_horas_id. Um mesmo colaborador pode ter mais de um banco no
      // mesmo mês (ex.: mensal e semestral), e o lançamento manual pode ter
      // ficado vinculado ao banco antigo depois de uma re-apuração — se
      // filtrássemos só pelo id, o rodapé ficaria vazio.
      const cpfDigits = (editBanco?.colaborador_cpf || "").replace(/\D/g, "");
      const ini = editIniFim?.ini;
      const fim = editIniFim?.fim;
      if (!ini || !fim) return [];
      const { data, error } = await fromTable("ponto_banco_horas_movimentacoes")
        .select("tipo, minutos, origem, data_referencia, descricao, created_at, created_by")
        .eq("tenant_id", tenantId)
        .eq("colaborador_cpf", cpfDigits)
        .gte("data_referencia", ini)
        .lte("data_referencia", fim)

        .order("data_referencia", { ascending: true });
      if (error) throw error;
      return (data || []).filter((m: any) =>
        !["apuracao", "apuracao_auto"].includes(String(m.origem || ""))
      ) as Array<{ tipo: string; minutos: number; origem: string; data_referencia: string | null; descricao: string | null; created_at: string; created_by: string | null }>;
    },
  });



  // Dias com ponto na competência — lidos da FONTE ÚNICA no banco
  // (ponto_saldo_dias_competencia). Antes esta regra era recalculada aqui em
  // TypeScript e também em SQL na apuração; manter as duas em sincronia se
  // mostrou inviável — a cada ajuste sobrava uma diferença e as telas
  // divergiam. Agora a tela apenas EXIBE o que o banco calcula, e a apuração
  // soma exatamente os mesmos números.
  const { data: diasBanco = [], isLoading: carregandoDias } = useQuery({
    queryKey: ["banco-horas-dias", editBanco?.colaborador_cpf, editComp, tenantId],
    enabled: !!editBanco && !!editComp && !!tenantId,
    queryFn: async () => {
      const cpfDigits = (editBanco?.colaborador_cpf || "").replace(/\D/g, "");
      const { data, error } = await (supabase.rpc as any)("ponto_saldo_dias_competencia", {
        p_tenant_id: tenantId,
        p_colaborador_cpf: cpfDigits,
        p_competencia: editComp,
      });
      if (error) throw error;
      const mapear = (d: any) => ({
        id: String(d.dia),
        data: String(d.dia),
        horas_trabalhadas_minutos: Number(d.trabalhado_min) || 0,
        jornada_esperada_minutos: Number(d.jornada_min) || 0,
        saldo_minutos: Number(d.saldo_min) || 0,
        entrada: d.entrada ? String(d.entrada).substring(0, 5) : null,
        saida: d.saida ? String(d.saida).substring(0, 5) : null,
        equalizacao: Boolean(d.equalizacao),
        excedente_retido_min: Number(d.excedente_retido_min) || 0,
        status: null as string | null,
        observacao: null as string | null,
        tipo_dia: "",
        detalhe: {
          entradaEscala: null as string | null,
          saidaEscala: null as string | null,
          intervaloMin: 0,
          toleranciaBatidaMin: 10,
          trabalhadoBrutoMin: Number(d.trabalhado_min) || 0,
          trabalhadoAjustadoMin: Number(d.trabalhado_min) || 0,
          jornadaEsperadaMin: Number(d.jornada_min) || 0,
          usouAjuste: true,
          diaProtegido: Boolean(d.protegido),
        },
      });

      const lista = ((data || []) as any[]).map(mapear);

      // RN14/RN15 — sábados e domingos SEMPRE constam na listagem, mesmo sem
      // marcação. O banco só devolve dias com registro em `ponto_diario`, o que
      // fazia o fim de semana sumir para uns colaboradores e aparecer para
      // outros (comportamento inconsistente). Aqui completamos as lacunas de
      // fim de semana da competência com linhas neutras (0 min), preservando o
      // que o banco calculou para os dias existentes.
      const existentes = new Set(lista.map((d) => d.data));
      const [ano, mes] = editComp.split("-").map(Number);
      const ultimoDia = new Date(ano, mes, 0).getDate();
      for (let dia = 1; dia <= ultimoDia; dia++) {
        const iso = `${ano}-${String(mes).padStart(2, "0")}-${String(dia).padStart(2, "0")}`;
        if (existentes.has(iso)) continue;
        const dow = new Date(ano, mes - 1, dia).getDay();
        if (dow !== 0 && dow !== 6) continue;
        lista.push(mapear({ dia: iso }));
      }
      lista.sort((a, b) => a.data.localeCompare(b.data));
      return lista;

    },
  });


  // RN23 — feriados da competência do colaborador em edição: rótulo
  // "FERIADO" na lista de dias e adicional de 100% quando trabalhado sem
  // folga compensatória (Lei 605/1949, art. 9º; Súmula 146 TST).
  const { porData: feriadosPorData } = useFeriadosCompetencia(editBanco?.colaborador_cpf, editComp);
  const { remover: removerFolga } = useFolgaCompensatoria();
  const [folgaDialog, setFolgaDialog] = useState<{
    dataFeriado: string;
    feriadoNome: string;
    trabalhadoMin: number;
  } | null>(null);

  const onlyDigits = (s: string) => (s || "").toString().replace(/\D/g, "");

  // Sobrepõe os números OFICIAIS ao vivo (ponto_banco_horas_oficial) na
  // fotografia, para a tabela principal bater com o detalhamento do colaborador
  // e com o relatório. Sem correspondência oficial, mantém a fotografia.
  const oficialPorCpf = new Map<string, any>();
  (bancoOficial as any[]).forEach((o) => {
    const cpf = onlyDigits(o.colaborador_cpf || "");
    if (cpf) oficialPorCpf.set(cpf, o);
  });
  const linhaOficial = (b: any) => {
    const o = oficialPorCpf.get(onlyDigits((b as any).colaborador_cpf || ""));
    if (!o) return b;
    return {
      ...b,
      saldo_anterior_minutos: o.saldo_anterior_min,
      creditos_minutos: o.creditos_min,
      debitos_minutos: o.debitos_min,
      compensados_minutos: o.compensados_min,
      saldo_atual_minutos: o.saldo_atual_min,
    };
  };
  const bancosOfic = (bancos as any[]).map(linhaOficial);

  // Filtra bancos de colaboradores ativos (useColaboradores já exclui inativos/desligados)
  const cpfsAtivos = new Set(colaboradores.map(c => onlyDigits(c.cpf || "")));
  const idsAtivos = new Set(colaboradores.map(c => c.id));
  const bancosAtivos = bancosOfic.filter(b => {
    const cpf = onlyDigits((b as any).colaborador_cpf || "");
    if (cpf && cpfsAtivos.has(cpf)) return true;
    if (b.colaborador_id && idsAtivos.has(b.colaborador_id)) return true;
    return false;
  });

  // Busca por nome ou CPF do colaborador + filtro por colaborador selecionado.
  const buscaNorm = busca.trim().toLowerCase();
  const buscaDigits = onlyDigits(busca);
  const colabSelecionado = colaboradores.find(c => c.id === colaboradorFiltroId);
  const cpfSelecionado = onlyDigits(colabSelecionado?.cpf || "");
  let bancosVisiveis = bancosAtivos;
  if (colaboradorFiltroId) {
    bancosVisiveis = bancosVisiveis.filter(b => {
      const cpf = onlyDigits((b as any).colaborador_cpf || "");
      if (cpfSelecionado && cpf === cpfSelecionado) return true;
      return b.colaborador_id === colaboradorFiltroId;
    });
  }
  if (buscaNorm) {
    bancosVisiveis = bancosVisiveis.filter(b => {
      const nome = String(b.colaborador_nome || "").toLowerCase();
      const cpf = onlyDigits((b as any).colaborador_cpf || "");
      return nome.includes(buscaNorm) || (buscaDigits.length > 0 && cpf.includes(buscaDigits));
    });
  }

  const totalCreditos = bancosAtivos.reduce((s, b) => s + b.creditos_minutos, 0);
  const totalDebitos = bancosAtivos.reduce((s, b) => s + b.debitos_minutos, 0);
  const totalSaldo = bancosAtivos.reduce((s, b) => s + b.saldo_atual_minutos, 0);

  const baixarModeloImport = () => {
    const ws = XLSX.utils.aoa_to_sheet([
      ["CPF", "Tipo Banco", "Tipo Movimentacao", "Data Referencia", "Minutos", "Descricao"],
      ["00000000000", "mensal", "credito", format(new Date(), "yyyy-MM-dd"), 60, "Hora extra exemplo"],
      ["00000000000", "mensal", "debito", format(new Date(), "yyyy-MM-dd"), 30, "Atraso exemplo"],
      ["00000000000", "mensal", "compensacao", format(new Date(), "yyyy-MM-dd"), 60, "Folga compensada"],
    ]);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "BancoHoras");
    XLSX.writeFile(wb, `modelo-import-banco-horas-${competencia}.xlsx`);
  };

  const handleImportFile = async (file: File) => {
    setImportando(true);
    setImportResumo(null);
    const erros: string[] = [];
    let ok = 0;
    try {
      const buf = await file.arrayBuffer();
      const wb = XLSX.read(buf, { type: "array" });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const rows: any[] = XLSX.utils.sheet_to_json(ws, { defval: "" });
      if (rows.length === 0) { toast.error("Planilha vazia"); setImportando(false); return; }

      // Mapa CPF → colaborador (apenas dígitos)
      const colabPorCpf = new Map<string, typeof colaboradores[number]>();
      for (const c of colaboradores) colabPorCpf.set(onlyDigits(c.cpf || ""), c);

      // Mapa CPF → banco já existente nesta competência
      const bancoPorCpf = new Map<string, BancoHoras>();
      for (const b of bancos) bancoPorCpf.set(onlyDigits(b.colaborador_cpf || ""), b);

      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const linha = i + 2;
        try {
          const cpf = onlyDigits(String(r["CPF"] ?? r["cpf"] ?? ""));
          const tipoBanco = String(r["Tipo Banco"] ?? r["tipo_banco"] ?? "mensal").toLowerCase().trim();
          const tipoMov = String(r["Tipo Movimentacao"] ?? r["Tipo Movimentação"] ?? r["tipo_movimentacao"] ?? "credito").toLowerCase().trim();
          const dataRef = String(r["Data Referencia"] ?? r["Data Referência"] ?? r["data_referencia"] ?? "").trim();
          const minutos = Number(r["Minutos"] ?? r["minutos"] ?? 0);
          const descricao = String(r["Descricao"] ?? r["Descrição"] ?? r["descricao"] ?? "").trim();

          if (!cpf) { erros.push(`Linha ${linha}: CPF vazio`); continue; }
          const colab = colabPorCpf.get(cpf);
          if (!colab) { erros.push(`Linha ${linha}: colaborador (CPF ${cpf}) não encontrado`); continue; }
          if (!["credito", "debito", "compensacao"].includes(tipoMov)) { erros.push(`Linha ${linha}: tipo movimentação inválido (${tipoMov})`); continue; }
          if (!dataRef || isNaN(new Date(dataRef).getTime())) { erros.push(`Linha ${linha}: data inválida`); continue; }
          if (!minutos || minutos <= 0) { erros.push(`Linha ${linha}: minutos inválidos`); continue; }

          let banco = bancoPorCpf.get(cpf);
          if (!banco) {
            banco = await criarBancoHoras({
              colaborador_id: colab.id,
              colaborador_nome: colab.nome_completo,
              colaborador_cpf: colab.cpf,
              tipo: ["mensal", "semestral", "anual"].includes(tipoBanco) ? tipoBanco : "mensal",
              competencia,
            }) as BancoHoras;
            bancoPorCpf.set(cpf, banco);
          }

          await adicionarMovimentacao({
            bancoHorasId: banco.id,
            colaboradorCpf: colab.cpf,
            dataReferencia: dataRef,
            tipo: tipoMov,
            minutos,
            descricao,
          });
          ok++;
        } catch (e: any) {
          erros.push(`Linha ${linha}: ${e?.message || "erro desconhecido"}`);
        }
      }
      setImportResumo({ ok, erros });
      if (ok > 0) toast.success(`${ok} movimentação(ões) importada(s)`);
      if (erros.length > 0) toast.warning(`${erros.length} linha(s) com erro`);
    } catch (e: any) {
      toast.error("Erro ao ler planilha: " + (e?.message || ""));
    } finally {
      setImportando(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Wallet className="w-5 h-5 text-primary" /> Banco de Horas
          </h3>
          <p className="text-sm text-muted-foreground">Saldos, movimentações e compensações</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <CompetenciaInput value={competencia} onChange={setCompetencia} className="w-[180px]" />
          <Button onClick={handleApurar} disabled={apurandoBancoHoras}>
            <RefreshCw className={`w-4 h-4 mr-2 ${apurandoBancoHoras ? "animate-spin" : ""}`} />
            {apurandoBancoHoras ? "Apurando..." : "Apurar agora"}
          </Button>
          <Button variant="outline" onClick={handleReapurarFechadas} disabled={reapurandoCompetencias}>
            <RefreshCw className={`w-4 h-4 mr-2 ${reapurandoCompetencias ? "animate-spin" : ""}`} />
            {reapurandoCompetencias ? "Reapurando..." : "Reapurar fechadas"}
          </Button>

          <Button variant="outline" onClick={() => setShowImport(true)}>
            <Upload className="w-4 h-4 mr-2" /> Importar
          </Button>
          <Button variant="outline" onClick={() => setShowCriar(true)}>
            <Plus className="w-4 h-4 mr-2" /> Novo Banco
          </Button>
        </div>
      </div>

      {reapuracaoResumo && (
        <Card className="border-primary/40">
          <CardHeader className="pb-2 flex-row items-center justify-between space-y-0">
            <CardTitle className="text-sm">
              Reapuração concluída — {reapuracaoResumo.registros_ajustados ?? 0} de{" "}
              {reapuracaoResumo.registros_processados ?? 0} competência(s) tiveram o saldo ajustado
            </CardTitle>
            <Button variant="ghost" size="sm" onClick={() => setReapuracaoResumo(null)}>
              Fechar
            </Button>
          </CardHeader>
          <CardContent className="pt-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Colaborador</TableHead>
                  <TableHead>Competência</TableHead>
                  <TableHead className="text-right">Antes</TableHead>
                  <TableHead className="text-right">Depois</TableHead>
                  <TableHead className="text-right">Diferença</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(reapuracaoResumo.detalhes || []).map((d, i) => (
                  <TableRow key={`${d.competencia}-${i}`}>
                    <TableCell>{d.colaborador_nome || "—"}</TableCell>
                    <TableCell>{d.competencia}</TableCell>
                    <TableCell className="text-right">{formatMinutos(d.saldo_antes_minutos)}</TableCell>
                    <TableCell className="text-right">{formatMinutos(d.saldo_depois_minutos)}</TableCell>
                    <TableCell
                      className={`text-right font-medium ${d.diferenca_minutos >= 0 ? "text-green-600" : "text-destructive"}`}
                    >
                      {d.diferenca_minutos >= 0 ? "+" : "-"}
                      {formatMinutos(Math.abs(d.diferenca_minutos))}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}


      {/* Stats */}
      <div className="grid grid-cols-3 gap-4">
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <TrendingUp className="w-8 h-8 text-green-500" />
            <div>
              <p className="text-xl font-bold text-green-600">{formatMinutos(totalCreditos)}</p>
              <p className="text-xs text-muted-foreground">Total Créditos</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <TrendingDown className="w-8 h-8 text-red-500" />
            <div>
              <p className="text-xl font-bold text-red-600">{formatMinutos(totalDebitos)}</p>
              <p className="text-xs text-muted-foreground">Total Débitos</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4 flex items-center gap-3">
            <Wallet className="w-8 h-8 text-primary" />
            <div>
              <p className={`text-xl font-bold ${totalSaldo >= 0 ? "text-green-600" : "text-red-600"}`}>{formatMinutos(totalSaldo)}</p>
              <p className="text-xs text-muted-foreground">Saldo Total</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* RN17: excedente diário acima do teto legal aguardando decisão do RH.
          Só aparece quando há pendência. */}
      <ExcedenteRetidoPanel competencia={competencia} />

      {folgaDialog && editBanco && (
        <FolgaCompensatoriaDialog
          open={!!folgaDialog}
          onOpenChange={(v) => { if (!v) setFolgaDialog(null); }}
          colaboradorId={editBanco.colaborador_id}
          colaboradorCpf={editBanco.colaborador_cpf}
          dataFeriado={folgaDialog.dataFeriado}
          feriadoNome={folgaDialog.feriadoNome}
          trabalhadoMin={folgaDialog.trabalhadoMin}
        />
      )}

      {/* Equalização mensal (RN04): valor necessário no mês para fechar 44h,
          visível desde o dia 1 — memória de cálculo (RN10) no ícone ⓘ. */}
      {eqComDeficit.length > 0 && (
        <Card className="border-amber-200 bg-amber-50/40 dark:bg-amber-950/10">
          <CardContent className="p-4">
            <div className="flex items-center justify-between gap-2 mb-2 flex-wrap">
              <div className="flex items-center gap-2">
                <CalendarDays className="w-4 h-4 text-amber-600" />
                <p className="text-sm font-semibold">Equalização mensal (fechar 44h) — {competencia}</p>
              </div>
              <Button variant="outline" size="sm" className="h-7 text-xs"
                onClick={() => setGerenciarEq(true)}>
                Definir sábados
              </Button>
            </div>
            <div className="space-y-1.5">
              {eqComDeficit.map((e) => (
                <div key={e.escala_id} className="flex items-center justify-between gap-2 text-sm flex-wrap">
                  <span className="font-medium">{e.escala_nome}</span>
                  <span className="flex items-center gap-2">
                    <span className="font-mono font-semibold text-amber-700">{formatMinutos(e.total_equalizacao_min)}</span>
                    <span className="text-xs text-muted-foreground">
                      {e.dias_uteis_efetivos} dias úteis · {e.qtd_feriados} feriado(s) deduzido(s)
                    </span>
                    <Button variant="ghost" size="sm" className="h-6 w-6 p-0" title="Memória de cálculo"
                      onClick={() => setMemoriaEq(e.memoria)}>
                      <Info className="w-3.5 h-3.5" />
                    </Button>
                  </span>
                </div>
              ))}
            </div>
            <p className="text-[11px] text-muted-foreground mt-2">
              Horas do sábado de equalização que apenas completam a jornada contratual do mês (não geram crédito).
            </p>
          </CardContent>
        </Card>
      )}

      {/* Table */}
      <Card>
        <CardContent className="p-0">
          <div className="p-3 border-b space-y-2">
            <div className="flex flex-col md:flex-row gap-2">
              <div className="md:w-[320px]">
                <ColaboradorSelect
                  value={colaboradorFiltroId}
                  onChange={setColaboradorFiltroId}
                  colaboradores={colaboradores as any}
                  placeholder="Filtrar por colaborador..."
                />
              </div>
              <div className="relative flex-1 max-w-sm">
                <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  placeholder="Ou buscar por nome / CPF..."
                  value={busca}
                  onChange={(e) => setBusca(e.target.value)}
                  className="pl-8"
                />
              </div>
              {(colaboradorFiltroId || busca.trim()) && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => { setColaboradorFiltroId(""); setBusca(""); }}
                >
                  Limpar
                </Button>
              )}
            </div>
            {(colaboradorFiltroId || busca.trim()) && (
              <p className="text-xs text-muted-foreground">
                {bancosVisiveis.length} colaborador(es) encontrado(s)
              </p>
            )}
          </div>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead className="text-right">Saldo Anterior</TableHead>
                <TableHead className="text-right">Créditos</TableHead>
                <TableHead className="text-right">Débitos</TableHead>
                <TableHead className="text-right">Compensados</TableHead>
                <TableHead className="text-right">Saldo Atual</TableHead>
                <TableHead>Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : bancosVisiveis.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">{busca.trim() ? "Nenhum colaborador encontrado para esta busca." : "Nenhum banco de horas para esta competência."}</TableCell></TableRow>
              ) : bancosVisiveis.map(b => (
                <TableRow key={b.id} className="cursor-pointer hover:bg-muted/50" onClick={() => setSelectedBanco(b)}>
                  <TableCell className="font-medium">{b.colaborador_nome}</TableCell>
                  <TableCell><Badge variant="outline">{b.tipo}</Badge></TableCell>
                  <TableCell className="text-right font-mono">{formatMinutos(b.saldo_anterior_minutos)}</TableCell>
                  <TableCell className="text-right font-mono text-green-600">+{formatMinutos(b.creditos_minutos)}</TableCell>
                  <TableCell className="text-right font-mono text-red-600">-{formatMinutos(b.debitos_minutos)}</TableCell>
                  <TableCell className="text-right font-mono">{formatMinutos(b.compensados_minutos)}</TableCell>
                  <TableCell className={`text-right font-mono font-bold ${b.saldo_atual_minutos >= 0 ? "text-green-600" : "text-red-600"}`}>
                    {formatMinutos(b.saldo_atual_minutos)}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-1">
                      <Button size="sm" variant="outline" onClick={e => { e.stopPropagation(); setSelectedBanco(b); setShowMovimentacao(true); }}>
                        <RefreshCw className="w-3 h-3 mr-1" /> Movimentar
                      </Button>
                      <Button size="icon" variant="ghost" title="Editar banco" onClick={e => {
                        e.stopPropagation();
                        const sa = b.saldo_anterior_minutos || 0;
                        const abs = Math.abs(sa);
                        setEditBanco({
                          id: b.id,
                          colaborador_id: b.colaborador_id,
                          colaborador_cpf: (b as any).colaborador_cpf || "",
                          colaborador_nome: b.colaborador_nome,
                          tipo: b.tipo,
                          competencia: b.competencia || competencia,
                          saldo_anterior_minutos: sa,
                          saldo_anterior_horas: Math.floor(abs / 60),
                          saldo_anterior_mins: abs % 60,
                          saldo_anterior_negativo: sa < 0,
                          creditos_minutos: b.creditos_minutos || 0,
                          debitos_minutos: b.debitos_minutos || 0,
                          compensados_minutos: b.compensados_minutos || 0,
                          prazo_compensacao: (b as any).prazo_compensacao || "",
                          observacoes: (b as any).observacoes || "",
                        });
                      }}>
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button size="icon" variant="ghost" title="Excluir banco" onClick={async e => {
                        e.stopPropagation();
                        const ok = await confirm({
                          title: "Excluir banco de horas?",
                          description: `Todas as movimentações de ${b.colaborador_nome} nesta competência serão removidas. Esta ação não pode ser desfeita.`,
                          confirmLabel: "Excluir",
                          variant: "destructive",
                        });
                        if (ok) {
                          await excluirBancoHoras(b.id);
                          if (selectedBanco?.id === b.id) setSelectedBanco(null);
                        }
                      }}>
                        <Trash2 className="w-4 h-4 text-red-600" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Legenda de apuração */}
      <Card className="bg-muted/30">
        <CardContent className="p-3">
          <div className="flex items-center gap-2 text-sm font-medium mb-3">
            <Info className="w-4 h-4 text-primary" />
            <span>Legenda da apuração</span>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs">
            <div className="flex items-start gap-2">
              <span className="inline-flex items-center shrink-0 font-mono font-semibold text-green-600">
                <ArrowUpRight className="w-3 h-3 mr-0.5" />+0h 00min
              </span>
              <span className="text-muted-foreground leading-relaxed">Saldo positivo: crédito (hora extra além da jornada).</span>
            </div>
            <div className="flex items-start gap-2">
              <span className="inline-flex items-center shrink-0 font-mono font-semibold text-red-600">
                <ArrowDownRight className="w-3 h-3 mr-0.5" />-0h 00min
              </span>
              <span className="text-muted-foreground leading-relaxed">Saldo negativo: débito (atraso ou saída antecipada).</span>
            </div>
            <div className="flex items-start gap-2">
              <span className="inline-flex items-center shrink-0 font-mono font-semibold text-muted-foreground">
                <Minus className="w-3 h-3 mr-0.5" />0h 0min
              </span>
              <span className="text-muted-foreground leading-relaxed">Saldo zerado: batidas e jornada coincidem.</span>
            </div>
            <div className="flex items-start gap-2">
              <span className="inline-flex items-center gap-1 shrink-0 text-muted-foreground">
                <span className="w-2 h-2 rounded-full bg-muted-foreground/60" />
                ±10 min
              </span>
              <span className="text-muted-foreground leading-relaxed">Atraso ou extra de até 10 minutos no saldo do dia é neutralizado — não gera crédito nem débito.</span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Movimentações do banco selecionado */}
      {selectedBanco && !showMovimentacao && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Movimentações — {selectedBanco.colaborador_nome}</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Data</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Minutos</TableHead>
                  <TableHead>Descrição</TableHead>
                  <TableHead className="text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {movimentacoes.length === 0 ? (
                  <TableRow><TableCell colSpan={5} className="text-center py-4 text-muted-foreground">Sem movimentações</TableCell></TableRow>
                ) : movimentacoes.map(m => (
                  <TableRow key={m.id}>
                    {/* RN16: data legível + abreviação do dia da semana. */}
                    <TableCell className="whitespace-nowrap">
                      {m.data_referencia
                        ? <>
                            {String(m.data_referencia).slice(0, 10).split("-").reverse().join("/")}{" "}
                            <span className="text-muted-foreground font-medium text-xs">
                              {abreviacaoDiaSemana(String(m.data_referencia))}
                            </span>
                          </>
                        : "-"}
                    </TableCell>
                    <TableCell>
                      <Badge className={m.tipo === "credito" ? "bg-green-100 text-green-800" : m.tipo === "debito" ? "bg-red-100 text-red-800" : "bg-blue-100 text-blue-800"}>
                        {m.tipo === "credito" && <ArrowUpRight className="w-3 h-3 mr-1" />}
                        {m.tipo === "debito" && <ArrowDownRight className="w-3 h-3 mr-1" />}
                        {m.tipo}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono">{formatMinutos(m.minutos)}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        {m.origem === "apuracao"
                          ? <Badge variant="secondary" className="text-[10px]">Apurado</Badge>
                          : <Badge variant="outline" className="text-[10px]">Manual</Badge>}
                        <span>{m.descricao || "-"}</span>
                      </div>
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex items-center justify-end gap-1">
                        <Button size="icon" variant="ghost" title="Editar" onClick={() => setEditMov({ id: m.id, tipo: m.tipo, minutos: m.minutos, data_referencia: m.data_referencia, descricao: m.descricao || "" })}>
                          <Pencil className="w-4 h-4" />
                        </Button>
                        <Button size="icon" variant="ghost" title="Excluir" onClick={async () => {
                          const ok = await confirm({ title: "Excluir movimentação?", description: "Esta ação recalculará o saldo do banco de horas.", confirmLabel: "Excluir", variant: "destructive" });
                          if (ok && selectedBanco) await excluirMovimentacao({ id: m.id, bancoHorasId: selectedBanco.id });
                        }}>
                          <Trash2 className="w-4 h-4 text-red-600" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Dialog Criar */}
      <Dialog open={showCriar} onOpenChange={setShowCriar}>
        <DialogContent>
          <DialogHeader><DialogTitle>Novo Banco de Horas</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Colaborador</Label>
              <Select value={criarForm.colaborador_id} onValueChange={v => setCriarForm({ ...criarForm, colaborador_id: v })}>
                <SelectTrigger><SelectValue placeholder="Selecione" /></SelectTrigger>
                <SelectContent>{colaboradores.map(c => <SelectItem key={c.id} value={c.id}>{c.nome_completo}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Tipo</Label>
              <Select value={criarForm.tipo} onValueChange={v => setCriarForm({ ...criarForm, tipo: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="mensal">Mensal</SelectItem>
                  <SelectItem value="semestral">Semestral</SelectItem>
                  <SelectItem value="anual">Anual</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowCriar(false)}>Cancelar</Button>
            <Button onClick={handleCriar} disabled={criandoBancoHoras}>{criandoBancoHoras ? "Criando..." : "Criar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog Movimentação */}
      <Dialog open={showMovimentacao} onOpenChange={setShowMovimentacao}>
        <DialogContent>
          <DialogHeader><DialogTitle>Nova Movimentação — {selectedBanco?.colaborador_nome}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label>Tipo</Label>
              <Select value={movForm.tipo} onValueChange={v => setMovForm({ ...movForm, tipo: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="credito">Crédito (HE)</SelectItem>
                  <SelectItem value="debito">Débito (Falta/Atraso)</SelectItem>
                  <SelectItem value="compensacao">Compensação</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Data Referência</Label>
                <Input type="date" value={movForm.data_referencia} onChange={e => setMovForm({ ...movForm, data_referencia: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>Minutos</Label>
                <Input type="number" value={movForm.minutos} onChange={e => setMovForm({ ...movForm, minutos: +e.target.value })} />
              </div>
            </div>
            <div className="space-y-2">
              <Label>Descrição</Label>
              <Input value={movForm.descricao} onChange={e => setMovForm({ ...movForm, descricao: e.target.value })} placeholder="Opcional" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowMovimentacao(false)}>Cancelar</Button>
            <Button onClick={handleMovimentacao} disabled={adicionandoMovimentacao}>{adicionandoMovimentacao ? "Registrando..." : "Registrar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog Editar Movimentação */}
      <Dialog open={!!editMov} onOpenChange={(o) => { if (!o) setEditMov(null); }}>
        <DialogContent>
          <DialogHeader><DialogTitle>Editar Movimentação</DialogTitle></DialogHeader>
          {editMov && (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label>Tipo</Label>
                <Select value={editMov.tipo} onValueChange={v => setEditMov({ ...editMov, tipo: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="credito">Crédito (HE)</SelectItem>
                    <SelectItem value="debito">Débito (Falta/Atraso)</SelectItem>
                    <SelectItem value="compensacao">Compensação</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Data Referência</Label>
                  <Input type="date" value={editMov.data_referencia} onChange={e => setEditMov({ ...editMov, data_referencia: e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Minutos</Label>
                  <Input type="number" value={editMov.minutos} onChange={e => setEditMov({ ...editMov, minutos: +e.target.value })} />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Descrição</Label>
                <Input value={editMov.descricao} onChange={e => setEditMov({ ...editMov, descricao: e.target.value })} placeholder="Opcional" />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditMov(null)}>Cancelar</Button>
            <Button
              disabled={editandoMovimentacao || !editMov || editMov.minutos <= 0}
              onClick={async () => {
                if (!editMov || !selectedBanco) return;
                await editarMovimentacao({
                  id: editMov.id,
                  bancoHorasId: selectedBanco.id,
                  tipo: editMov.tipo,
                  minutos: editMov.minutos,
                  data_referencia: editMov.data_referencia,
                  descricao: editMov.descricao,
                });
                setEditMov(null);
              }}
            >{editandoMovimentacao ? "Salvando..." : "Salvar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog Importar */}
      <Dialog open={showImport} onOpenChange={(o) => { setShowImport(o); if (!o) setImportResumo(null); }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><FileSpreadsheet className="w-5 h-5" /> Importar Banco de Horas</DialogTitle>
            <DialogDescription>
              Envie uma planilha .xlsx com as colunas: <strong>CPF</strong>, <strong>Tipo Banco</strong> (mensal/semestral/anual),
              <strong> Tipo Movimentacao</strong> (credito/debito/compensacao), <strong>Data Referencia</strong> (AAAA-MM-DD),
              <strong> Minutos</strong>, <strong>Descricao</strong>. Cada linha cria uma movimentação na competência <strong>{competencia}</strong>.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <Button variant="outline" size="sm" onClick={baixarModeloImport} className="w-full">
              <Download className="w-4 h-4 mr-2" /> Baixar modelo de planilha
            </Button>
            <Input
              ref={fileInputRef}
              type="file"
              accept=".xlsx,.xls,.csv"
              disabled={importando}
              onChange={(e) => { const f = e.target.files?.[0]; if (f) handleImportFile(f); }}
            />
            {importando && <p className="text-sm text-muted-foreground">Processando planilha…</p>}
            {importResumo && (
              <div className="rounded-md border p-3 text-sm space-y-2 max-h-60 overflow-auto">
                <p className="font-medium text-green-700">{importResumo.ok} movimentação(ões) importada(s) com sucesso.</p>
                {importResumo.erros.length > 0 && (
                  <div className="text-red-700">
                    <p className="font-medium">{importResumo.erros.length} erro(s):</p>
                    <ul className="list-disc list-inside text-xs space-y-0.5">
                      {importResumo.erros.slice(0, 30).map((e, i) => <li key={i}>{e}</li>)}
                      {importResumo.erros.length > 30 && <li>… e mais {importResumo.erros.length - 30}</li>}
                    </ul>
                  </div>
                )}
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowImport(false)}>Fechar</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {/* Dialog Editar Banco de Horas */}
      <Dialog open={!!editBanco} onOpenChange={(o) => { if (!o) setEditBanco(null); }}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              Editar Banco de Horas — {editBanco?.colaborador_nome}
            </DialogTitle>
            <DialogDescription>
              Ajuste tipo, competência, saldo anterior e prazo de compensação.
              O saldo atual é calculado na listagem do banco.
            </DialogDescription>
          </DialogHeader>
          {editBanco && (() => {
            const sinal = editBanco.saldo_anterior_negativo ? -1 : 1;
            const saldoAnteriorMin = sinal * (editBanco.saldo_anterior_horas * 60 + editBanco.saldo_anterior_mins);
            return (
              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Colaborador</Label>
                    <Input value={editBanco.colaborador_nome} disabled />
                  </div>
                  <div className="space-y-2">
                    <Label>Competência (mês/ano)</Label>
                    <CompetenciaInput
                      value={editBanco.competencia}
                      onChange={v => setEditBanco({ ...editBanco, competencia: v })}
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label>Tipo de banco</Label>
                  <Select value={editBanco.tipo} onValueChange={v => setEditBanco({ ...editBanco, tipo: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="mensal">Mensal</SelectItem>
                      <SelectItem value="semestral">Semestral</SelectItem>
                      <SelectItem value="anual">Anual</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-2">
                  <Label>Saldo Anterior</Label>
                  <div className="grid grid-cols-[110px_1fr_1fr] gap-2">
                    <Select
                      value={editBanco.saldo_anterior_negativo ? "neg" : "pos"}
                      onValueChange={v => setEditBanco({ ...editBanco, saldo_anterior_negativo: v === "neg" })}
                    >
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="pos">+ Crédito</SelectItem>
                        <SelectItem value="neg">− Débito</SelectItem>
                      </SelectContent>
                    </Select>
                    <div>
                      <Input
                        type="number"
                        min={0}
                        value={editBanco.saldo_anterior_horas}
                        onChange={e => setEditBanco({ ...editBanco, saldo_anterior_horas: Math.max(0, parseInt(e.target.value || "0", 10)) })}
                        placeholder="Horas"
                      />
                      <p className="text-[11px] text-muted-foreground mt-1">Horas</p>
                    </div>
                    <div>
                      <Input
                        type="number"
                        min={0}
                        max={59}
                        value={editBanco.saldo_anterior_mins}
                        onChange={e => setEditBanco({ ...editBanco, saldo_anterior_mins: Math.min(59, Math.max(0, parseInt(e.target.value || "0", 10))) })}
                        placeholder="Minutos"
                      />
                      <p className="text-[11px] text-muted-foreground mt-1">Minutos</p>
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Equivalente a <span className="font-mono">{formatMinutos(saldoAnteriorMin)}</span>.
                  </p>
                </div>

                <div className="space-y-2">
                  <Label>Prazo de Compensação (dia / mês / ano)</Label>
                  <Input
                    type="date"
                    value={editBanco.prazo_compensacao}
                    onChange={e => setEditBanco({ ...editBanco, prazo_compensacao: e.target.value })}
                  />
                  <p className="text-xs text-muted-foreground">Data limite para compensar o saldo (opcional).</p>
                </div>

                <div className="space-y-2">
                  <Label>Observações</Label>
                  <Input
                    value={editBanco.observacoes}
                    onChange={e => setEditBanco({ ...editBanco, observacoes: e.target.value })}
                    placeholder="Ex.: ajuste manual referente a acordo XYZ"
                  />
                </div>

                {/* Lista de dias com ponto na competência */}
                <div className="space-y-2">
                  <Label className="flex items-center gap-2">
                    <CalendarDays className="w-4 h-4" /> Dias com ponto na competência
                  </Label>
                  <div className="rounded-md border max-h-64 overflow-y-auto">
                    <Table>
                      <TableHeader className="sticky top-0 bg-background">
                        <TableRow>
                          <TableHead className="h-8">Data</TableHead>
                          <TableHead className="h-8">Entrada</TableHead>
                          <TableHead className="h-8">Saída</TableHead>
                          <TableHead className="h-8 text-right">Trabalhado</TableHead>
                          <TableHead className="h-8 text-right">Valor</TableHead>
                          <TableHead className="h-8 text-right">Ação</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {carregandoDias ? (
                          <TableRow><TableCell colSpan={6} className="text-center py-3 text-xs text-muted-foreground">Carregando dias…</TableCell></TableRow>
                        ) : diasBanco.length === 0 ? (
                          <TableRow><TableCell colSpan={6} className="text-center py-3 text-xs text-muted-foreground">Nenhum ponto registrado nesta competência.</TableCell></TableRow>
                        ) : diasBanco.map(d => {
                          const [y, m, dd] = d.data.split("-");
                          const saldoDia = d.saldo_minutos || 0;
                          const isCredito = saldoDia > 0;
                          const isDebito = saldoDia < 0;
                          const isNeutro = saldoDia === 0;
                          const feriado = feriadosPorData.get(d.data);
                          return (
                            <TableRow key={d.id}>
                              <TableCell className="py-1.5 text-xs">
                                <div className="flex flex-col gap-0.5">
                                  {/* RN16: abreviação do dia da semana ao lado da data */}
                                  <span>
                                    {dd}/{m}/{y}{" "}
                                    <span className="text-muted-foreground font-medium">{abreviacaoDiaSemana(d.data)}</span>
                                  </span>
                                  {/* RN14/RN15: DSR no domingo; sábado comum fica só com
                                      a abreviação (sem "Compensado"); o sábado de
                                      equalização mantém o rótulo próprio. */}
                                  {d.equalizacao ? (
                                    <Badge variant="outline" className="text-[9px] h-4 px-1 w-fit border-amber-500 text-amber-700">
                                      Equalização
                                    </Badge>
                                  ) : rotuloTipoDia(d.data) === "DSR" ? (
                                    <Badge variant="outline" className="text-[9px] h-4 px-1 w-fit border-sky-500 text-sky-700">
                                      DSR
                                    </Badge>
                                  ) : null}
                                  {/* RN23: o rótulo vale para todo feriado do mês.
                                      Trabalhado sem folga compensatória, mostra
                                      também o adicional de 100% devido. */}
                                  {feriado && (
                                    <Badge
                                      variant="outline"
                                      className="text-[9px] h-4 px-1 w-fit border-violet-500 text-violet-700"
                                      title={`${feriado.feriado_nome} (${feriado.origem})`}
                                    >
                                      FERIADO
                                    </Badge>
                                  )}
                                  {feriado && feriado.trabalhado_min > 0 && (
                                    feriado.folga_compensatoria_em ? (
                                      <button
                                        type="button"
                                        className="text-[9px] text-muted-foreground underline underline-offset-2 w-fit"
                                        onClick={() =>
                                          removerFolga.mutate({
                                            colaboradorCpf: editBanco?.colaborador_cpf || "",
                                            dataFeriado: d.data,
                                          })
                                        }
                                        title="Remover a folga compensatória — o feriado volta a gerar adicional de 100%"
                                      >
                                        Compensado em {feriado.folga_compensatoria_em.split("-").reverse().join("/")}
                                      </button>
                                    ) : (
                                      <button
                                        type="button"
                                        className="w-fit"
                                        onClick={() =>
                                          setFolgaDialog({
                                            dataFeriado: d.data,
                                            feriadoNome: feriado.feriado_nome,
                                            trabalhadoMin: feriado.trabalhado_min,
                                          })
                                        }
                                        title="Trabalhou no feriado sem folga compensatória — clique para registrar a folga"
                                      >
                                        <Badge
                                          variant="outline"
                                          className="text-[9px] h-4 px-1 border-violet-500 bg-violet-50 text-violet-700"
                                        >
                                          +100% {formatMinutos(feriado.adicional_100_min)}
                                        </Badge>
                                      </button>
                                    )
                                  )}
                                  {d.excedente_retido_min > 0 && (
                                    <Badge variant="outline" className="text-[9px] h-4 px-1 w-fit border-red-400 text-red-600">
                                      Retido {formatMinutos(d.excedente_retido_min)} (art. 61)
                                    </Badge>
                                  )}
                                </div>
                              </TableCell>
                              <TableCell className="py-1.5 text-xs font-mono">{d.entrada?.slice(0, 5) || "-"}</TableCell>
                              <TableCell className="py-1.5 text-xs font-mono">{d.saida?.slice(0, 5) || "-"}</TableCell>
                              <TableCell className="py-1.5 text-xs font-mono text-right">{formatMinutos(d.horas_trabalhadas_minutos || 0)}</TableCell>
                              <TableCell className={`py-1.5 text-xs font-mono text-right font-semibold ${isCredito ? "text-green-600" : isDebito ? "text-red-600" : "text-muted-foreground"}`}>
                                <Popover>
                                  <PopoverTrigger asChild>
                                    <button type="button" className="inline-flex items-center gap-1 hover:underline focus:outline-none">
                                      {isNeutro ? "—" : `${isCredito ? "+" : "-"}${formatMinutos(Math.abs(saldoDia))}`}
                                      <Info className="w-3 h-3 opacity-60" />
                                    </button>
                                  </PopoverTrigger>
                                  <PopoverContent align="end" className="w-80 text-xs">
                                    {(() => {
                                      const det = d.detalhe;
                                      const entradaReal = d.entrada?.slice(0, 5) || "-";
                                      const saidaReal = d.saida?.slice(0, 5) || "-";
                                      const tol = det.toleranciaBatidaMin || 0;
                                      const toMin = (h?: string | null) => {
                                        if (!h) return null;
                                        const [hh, mm] = h.split(":").map(Number);
                                        return hh * 60 + mm;
                                      };
                                      const eR = toMin(d.entrada?.slice(0, 5));
                                      const sR = toMin(d.saida?.slice(0, 5));
                                      const eE = toMin(det.entradaEscala);
                                      const sE = toMin(det.saidaEscala);
                                      const atrasoEntrada = (eR != null && eE != null) ? eR - eE : null;
                                      const antecipSaida = (sR != null && sE != null) ? sE - sR : null;
                                      const dentroEntrada = atrasoEntrada != null && atrasoEntrada <= tol;
                                      const dentroSaida = antecipSaida != null && antecipSaida <= tol;
                                      return (
                                        <div className="space-y-2">
                                          <div className="font-semibold text-sm">Detalhamento do saldo</div>
                                          <div className="grid grid-cols-2 gap-x-2 gap-y-1">
                                            <span className="text-muted-foreground">Escala oficial</span>
                                            <span className="font-mono text-right">{det.entradaEscala || "-"} → {det.saidaEscala || "-"}</span>

                                            <span className="text-muted-foreground">Batida real</span>
                                            <span className="font-mono text-right">{entradaReal} → {saidaReal}</span>

                                            <span className="text-muted-foreground">Janela tolerância</span>
                                            <span className="font-mono text-right">± {tol} min</span>

                                            <span className="text-muted-foreground">Intervalo</span>
                                            <span className="font-mono text-right">{formatMinutos(det.intervaloMin)}</span>

                                            <span className="text-muted-foreground">Entrada</span>
                                            <span className={`font-mono text-right ${atrasoEntrada != null && atrasoEntrada > 0 ? (dentroEntrada ? "text-muted-foreground" : "text-red-600") : "text-green-600"}`}>
                                              {atrasoEntrada == null ? "-" : atrasoEntrada === 0 ? "no horário" : atrasoEntrada > 0 ? `atraso ${atrasoEntrada} min${dentroEntrada ? " (na tolerância)" : ""}` : `adiant. ${Math.abs(atrasoEntrada)} min`}
                                            </span>

                                            <span className="text-muted-foreground">Saída</span>
                                            <span className={`font-mono text-right ${antecipSaida != null && antecipSaida > 0 ? (dentroSaida ? "text-muted-foreground" : "text-red-600") : "text-green-600"}`}>
                                              {antecipSaida == null ? "-" : antecipSaida === 0 ? "no horário" : antecipSaida > 0 ? `antec. ${antecipSaida} min${dentroSaida ? " (na tolerância)" : ""}` : `extra ${Math.abs(antecipSaida)} min`}
                                            </span>

                                            <span className="text-muted-foreground">Trabalhado bruto</span>
                                            <span className="font-mono text-right">{formatMinutos(det.trabalhadoBrutoMin)}</span>

                                            {det.usouAjuste && (
                                              <>
                                                <span className="text-muted-foreground">Trabalhado ajustado</span>
                                                <span className="font-mono text-right">{formatMinutos(det.trabalhadoAjustadoMin)}</span>
                                              </>
                                            )}

                                            <span className="text-muted-foreground">Jornada esperada</span>
                                            <span className="font-mono text-right">{formatMinutos(det.jornadaEsperadaMin)}</span>
                                          </div>
                                          <div className="border-t pt-2 flex items-center justify-between">
                                            <span className="text-muted-foreground">Saldo do dia</span>
                                            <span className={`font-mono font-semibold ${isCredito ? "text-green-600" : isDebito ? "text-red-600" : "text-muted-foreground"}`}>
                                              {isNeutro ? "0h 0min" : `${isCredito ? "+" : "-"}${formatMinutos(Math.abs(saldoDia))}`}
                                            </span>
                                          </div>
                                          {isNeutro && !det.diaProtegido && (
                                            <p className="text-[11px] text-muted-foreground italic">
                                              Diferenças de até 10 minutos no saldo do dia são neutralizadas.
                                            </p>
                                          )}
                                          {det.diaProtegido && (
                                            <p className="text-[11px] text-muted-foreground italic">Dia protegido (atestado/férias/afastamento/feriado): saldo neutralizado.</p>
                                          )}
                                          {!det.usouAjuste && !det.diaProtegido && (
                                            <p className="text-[11px] text-muted-foreground italic">Sem horário de escala definido — cálculo usa trabalhado bruto × jornada.</p>
                                          )}
                                        </div>
                                      );
                                    })()}
                                  </PopoverContent>
                                </Popover>
                              </TableCell>

                              <TableCell className="py-1.5 text-right">
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  className="h-6 px-2 text-xs"
                                  onClick={() => {
                                    const saldo = d.saldo_minutos || 0;
                                    setSelectedBanco(bancos.find(b => b.id === editBanco.id) || null);
                                    setMovForm({
                                      tipo: saldo >= 0 ? "credito" : "debito",
                                      minutos: Math.abs(saldo) || 0,
                                      data_referencia: d.data,
                                      descricao: `Ajuste referente a ${dd}/${m}/${y}`,
                                    });
                                    setEditBanco(null);
                                    setShowMovimentacao(true);
                                  }}
                                >
                                  <Pencil className="w-3 h-3 mr-1" /> Ajustar dia
                                </Button>
                              </TableCell>
                            </TableRow>
                          );
                        })}

                      </TableBody>
                    </Table>
                  </div>
                  <p className="text-[11px] text-muted-foreground">
                    Clique em "Ajustar dia" para lançar uma movimentação (crédito, débito ou compensação) referente àquele dia específico.
                  </p>
                </div>

                {(() => {
                  // Créditos/Débitos da edição = dias com ponto + lançamentos
                  // MANUAIS do banco. Antes só somava os dias, e por isso
                  // divergia da listagem sempre que havia ajuste manual.
                  const credDias = diasBanco.reduce((s, d) => s + (d.saldo_minutos > 0 ? d.saldo_minutos : 0), 0);
                  const debDias = diasBanco.reduce((s, d) => s + (d.saldo_minutos < 0 ? -d.saldo_minutos : 0), 0);
                  const credManual = movsManuaisEdit
                    .filter(m => m.tipo === "credito")
                    .reduce((s, m) => s + (Number(m.minutos) || 0), 0);
                  const debManual = movsManuaisEdit
                    .filter(m => m.tipo === "debito")
                    .reduce((s, m) => s + (Number(m.minutos) || 0), 0);
                  const cred = credDias + credManual;
                  const deb = debDias + debManual;
                  const temManual = credManual > 0 || debManual > 0;
                  return (
                    <div className="rounded-md border bg-muted/40 p-3 space-y-2">
                      <div className="grid grid-cols-2 gap-3 text-center">
                        <div>
                          <p className="text-[11px] text-muted-foreground">Créditos</p>
                          <p className="font-mono text-sm text-green-600">+{formatMinutos(cred)}</p>
                        </div>
                        <div>
                          <p className="text-[11px] text-muted-foreground">Débitos</p>
                          <p className="font-mono text-sm text-red-600">-{formatMinutos(deb)}</p>
                        </div>
                      </div>
                      {temManual && (
                        <div className="border-t pt-2 space-y-1">
                          <p className="text-[11px] font-medium text-muted-foreground">
                            Lançamentos manuais ({movsManuaisEdit.length}):
                          </p>
                          <ul className="text-[11px] space-y-1">
                            {movsManuaisEdit.map((m, i) => {
                              const data = m.data_referencia
                                ? new Date(m.data_referencia + "T12:00:00").toLocaleDateString("pt-BR")
                                : new Date(m.created_at).toLocaleDateString("pt-BR");
                              const isCred = m.tipo === "credito";
                              return (
                                <li key={i} className="flex items-start justify-between gap-2 border-b border-dashed last:border-0 pb-1">
                                  <div className="flex-1 text-left">
                                    <span className="font-mono">{data}</span>
                                    {m.descricao && (
                                      <span className="text-muted-foreground"> — {m.descricao}</span>
                                    )}
                                    {m.origem && m.origem !== "manual" && (
                                      <span className="text-muted-foreground"> ({m.origem})</span>
                                    )}
                                  </div>
                                  <span className={`font-mono font-medium ${isCred ? "text-green-600" : "text-red-600"}`}>
                                    {isCred ? "+" : "-"}{formatMinutos(Number(m.minutos) || 0)}
                                  </span>
                                </li>
                              );
                            })}
                          </ul>
                          <p className="text-[11px] text-muted-foreground text-center pt-1">
                            Subtotal manual:
                            {credManual > 0 && <> <span className="text-green-600">+{formatMinutos(credManual)}</span></>}
                            {credManual > 0 && debManual > 0 && " ·"}
                            {debManual > 0 && <> <span className="text-red-600">-{formatMinutos(debManual)}</span></>}
                          </p>
                        </div>
                      )}

                    </div>
                  );
                })()}

              </div>
            );
          })()}
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditBanco(null)}>Cancelar</Button>
            <Button
              disabled={editandoBancoHoras || !editBanco}
              onClick={async () => {
                if (!editBanco) return;
                const sinal = editBanco.saldo_anterior_negativo ? -1 : 1;
                const saldoAnteriorMin = sinal * (editBanco.saldo_anterior_horas * 60 + editBanco.saldo_anterior_mins);
                await editarBancoHoras({
                  id: editBanco.id,
                  tipo: editBanco.tipo,
                  competencia: editBanco.competencia,
                  saldo_anterior_minutos: saldoAnteriorMin,
                  prazo_compensacao: editBanco.prazo_compensacao || null,
                  observacoes: editBanco.observacoes || null,
                });
                setEditBanco(null);
              }}
            >{editandoBancoHoras ? "Salvando..." : "Salvar"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Memória de cálculo da equalização (RN10 — rastreabilidade Portaria 671) */}
      <Dialog open={!!memoriaEq} onOpenChange={(o) => !o && setMemoriaEq(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Memória de cálculo — Equalização mensal</DialogTitle>
            <DialogDescription>
              {memoriaEq?.escala_nome} · {memoriaEq?.competencia}
            </DialogDescription>
          </DialogHeader>
          {memoriaEq && (
            <div className="space-y-2 text-sm">
              <div className="grid grid-cols-2 gap-x-3 gap-y-1.5">
                <span className="text-muted-foreground">Dias úteis brutos (seg–sex)</span>
                <span className="font-mono text-right">{memoriaEq.dias_uteis_brutos}</span>
                <span className="text-muted-foreground">Feriados deduzidos</span>
                <span className="font-mono text-right">{memoriaEq.qtd_feriados_deduzidos}</span>
                <span className="text-muted-foreground">Dias úteis efetivos</span>
                <span className="font-mono text-right font-semibold">{memoriaEq.dias_uteis_efetivos}</span>
                <span className="text-muted-foreground">Carga semanal real da escala</span>
                <span className="font-mono text-right">{formatMinutos(memoriaEq.carga_semanal_real_min || 0)}</span>
                <span className="text-muted-foreground">Déficit semanal (44h − carga)</span>
                <span className="font-mono text-right">{formatMinutos(memoriaEq.deficit_semanal_min || 0)}</span>
                <span className="text-muted-foreground">Déficit diário (÷ 5)</span>
                <span className="font-mono text-right">{memoriaEq.deficit_diario_min} min/dia</span>
                <span className="text-muted-foreground font-medium">Total de equalização do mês</span>
                <span className="font-mono text-right font-bold text-amber-700">{formatMinutos(memoriaEq.total_equalizacao_min || 0)}</span>
              </div>
              {Array.isArray(memoriaEq.feriados_deduzidos) && memoriaEq.feriados_deduzidos.length > 0 && (
                <div className="border-t pt-2">
                  <p className="text-xs font-medium mb-1">Feriados deduzidos:</p>
                  {memoriaEq.feriados_deduzidos.map((f: any, i: number) => (
                    <p key={i} className="text-xs text-muted-foreground">
                      {String(f.data).split("-").reverse().join("/")} — {f.nome}
                    </p>
                  ))}
                </div>
              )}
              {Array.isArray(memoriaEq.observacoes) && memoriaEq.observacoes.length > 0 && (
                <div className="border-t pt-2">
                  {memoriaEq.observacoes.map((o: string, i: number) => (
                    <p key={i} className="text-[11px] text-amber-700">⚠ {o}</p>
                  ))}
                </div>
              )}
              <p className="text-[10px] text-muted-foreground border-t pt-2">
                Gerado em {memoriaEq.gerado_em ? new Date(memoriaEq.gerado_em).toLocaleString("pt-BR") : "—"} · Contagem direta do calendário (RN01) · Base legal: art. 59 CLT
              </p>
            </div>
          )}
        </DialogContent>
      </Dialog>
      {/* Gerenciador do sábado de equalização (RN05 — marcação INDIVIDUAL por
          colaborador) e liberação de excedente retido pelo teto (art. 61 CLT). */}
      <Dialog open={gerenciarEq} onOpenChange={setGerenciarEq}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Sábado de equalização — {competencia}</DialogTitle>
            <DialogDescription>
              Marque, para cada colaborador, qual sábado trabalhado fecha as 44h do mês.
              A escolha é individual: colaboradores da mesma escala podem ter sábados diferentes.
            </DialogDescription>
          </DialogHeader>

          {eqColaboradores.length === 0 ? (
            <p className="text-sm text-muted-foreground py-6 text-center">
              Nenhum colaborador com equalização a definir nesta competência.
            </p>
          ) : (
            <div className="space-y-3">
              {eqColaboradores.map((c) => (
                <div key={c.colaborador_cpf} className="border rounded-md p-3">
                  <div className="flex items-center justify-between gap-2 flex-wrap mb-2">
                    <div>
                      <p className="text-sm font-medium">{c.colaborador_nome}</p>
                      <p className="text-xs text-muted-foreground">
                        {c.escala_nome} · precisa de{" "}
                        <span className="font-mono font-semibold text-amber-700">
                          {formatMinutos(c.total_equalizacao_min)}
                        </span>
                      </p>
                    </div>
                    {c.art61_liberado && (
                      <Badge variant="outline" className="text-[10px] border-amber-500 text-amber-700">
                        Excedente liberado (art. 61)
                      </Badge>
                    )}
                  </div>

                  {c.sabados.length === 0 ? (
                    <p className="text-xs text-muted-foreground">
                      Nenhum sábado com ponto registrado neste mês — a equalização ficará como débito no fechamento.
                    </p>
                  ) : (
                    <div className="flex flex-wrap gap-1.5">
                      {c.sabados.map((s) => {
                        const marcado = c.data_marcada === s.data;
                        return (
                          <Button
                            key={s.data}
                            size="sm"
                            variant={marcado ? "default" : "outline"}
                            className="h-7 text-xs"
                            disabled={definirEq.isPending || removerEq.isPending}
                            onClick={() =>
                              marcado
                                ? removerEq.mutate(c.colaborador_cpf)
                                : definirEq.mutate({ cpf: c.colaborador_cpf, data: s.data })
                            }
                          >
                            {String(s.data).split("-").reverse().slice(0, 2).join("/")}
                            <span className="ml-1 opacity-70">({formatMinutos(s.trabalhado_min)})</span>
                          </Button>
                        );
                      })}
                      {c.data_marcada && (
                        <Button size="sm" variant="ghost" className="h-7 text-xs text-muted-foreground"
                          disabled={removerEq.isPending}
                          onClick={() => removerEq.mutate(c.colaborador_cpf)}>
                          Nenhum
                        </Button>
                      )}
                    </div>
                  )}

                  {c.data_marcada && (() => {
                    // RN08: intervalo intrajornada mínimo pelo total do dia marcado.
                    const sab = c.sabados.find((s) => s.data === c.data_marcada);
                    const trab = sab?.trabalhado_min || 0;
                    const minInt = trab <= 240 ? 0 : trab <= 360 ? 15 : 60;
                    return (
                      <p className="text-[11px] text-muted-foreground mt-1">
                        Intervalo mínimo neste dia ({formatMinutos(trab)} trabalhados):{" "}
                        <strong>{minInt === 0 ? "não obrigatório" : `${minInt} min`}</strong> (art. 71 CLT).
                      </p>
                    );
                  })()}

                  {c.data_marcada && !c.art61_liberado && (
                    <Button variant="ghost" size="sm" className="h-6 text-[11px] mt-2 text-amber-700 px-1"
                      onClick={() => setArt61({ cpf: c.colaborador_cpf, nome: c.colaborador_nome, justificativa: "" })}>
                      Liberar excedente acima do teto (art. 61 CLT)
                    </Button>
                  )}
                </div>
              ))}
              <p className="text-[11px] text-muted-foreground border-t pt-2">
                Intervalo mínimo do dia (art. 71 CLT): até 4h sem intervalo; de 4h a 6h, 15 minutos; acima de 6h, 1 hora.
              </p>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Justificativa do art. 61 para liberar excedente retido */}
      <Dialog open={!!art61} onOpenChange={(o) => !o && setArt61(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Liberar excedente — art. 61 CLT</DialogTitle>
            <DialogDescription>
              O excedente acima do teto legal fica retido até validação do RH. Registre a
              justificativa de necessidade imperiosa ou força maior para {art61?.nome}.
            </DialogDescription>
          </DialogHeader>
          <div>
            <Label className="text-xs">Justificativa (obrigatória)</Label>
            <Input
              value={art61?.justificativa || ""}
              onChange={(e) => setArt61((p) => (p ? { ...p, justificativa: e.target.value } : p))}
              placeholder="Ex.: atendimento emergencial de cliente em parada de produção"
            />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setArt61(null)}>Cancelar</Button>
            <Button
              disabled={!art61?.justificativa.trim() || liberarArt61.isPending}
              onClick={() => {
                if (!art61) return;
                liberarArt61.mutate(
                  { cpf: art61.cpf, justificativa: art61.justificativa.trim() },
                  { onSuccess: () => setArt61(null) }
                );
              }}
            >
              {liberarArt61.isPending ? "Liberando..." : "Liberar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
