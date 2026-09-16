import { useState, useMemo } from "react";
import { useColaboradores } from "@/hooks/useColaboradores";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { CompetenciaInput } from "@/components/ui/competencia-input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { usePonto } from "@/hooks/usePonto";
import { usePontoFechamento } from "@/hooks/usePontoFechamento";
import { usePontoBancoHoras } from "@/hooks/usePontoBancoHoras";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { format } from "date-fns";
import { FileDown, FileText, Download, Archive } from "lucide-react";
import { toast } from "sonner";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import * as XLSX from "xlsx";
import { formatarHoraMinuto } from "@/lib/ponto/formatoHoras";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import {
  MARCA, ALTURA_CABECALHO, carregarLogo, desenharCabecalho, desenharRodape, estiloTabela,
} from "@/lib/ponto/pdfMarca";
import { desenharCartaoPonto } from "@/lib/ponto/cartaoPonto";
import { gerarAFD671 } from "@/lib/ponto/afd671";
import { gerarAEJ671, type AejMarcacao, type AejOcorrencia } from "@/lib/ponto/aej671";
import { IncluirBancoHorasDialog } from "@/components/ponto/IncluirBancoHorasDialog";


type ReportType = "cartao_ponto" | "espelho" | "horas_extras" | "banco_horas" | "absenteismo" | "afd" | "aej";

const REPORT_TYPES: { value: ReportType; label: string; desc: string }[] = [
  { value: "cartao_ponto", label: "Cartão Ponto", desc: "Modelo clássico dia a dia (H.D./H.N./H.E./H.C./H.A./F.N./F.J.)" },
  { value: "espelho", label: "Espelho de Ponto", desc: "Detalhamento dia a dia por colaborador (modelo legal)" },
  { value: "horas_extras", label: "Horas Extras", desc: "Detalhamento de horas extras do período" },
  { value: "banco_horas", label: "Banco de Horas", desc: "Saldo e movimentações do banco de horas" },
  { value: "absenteismo", label: "Absenteísmo", desc: "Relatório de faltas e atrasos" },
  { value: "afd", label: "AFD (Arquivo Fonte de Dados)", desc: "Arquivo legal conforme Portaria 671" },
  { value: "aej", label: "AEJ (Arquivo Eletrônico de Jornada)", desc: "Jornada apurada: marcações + ajustes aprovados (Portaria 671)" },
];


export function PontoRelatoriosTab() {
  const [competencia, setCompetencia] = useState(format(new Date(), "yyyy-MM"));
  const [tipoRelatorio, setTipoRelatorio] = useState<ReportType>("espelho");
  const [formatoExport, setFormatoExport] = useState<"pdf" | "excel">("pdf");
  const [gerando, setGerando] = useState(false);

  const { usePontoDiario } = usePonto();
  const { useEspelhos } = usePontoFechamento();
  const { useBancoHorasPorCompetencia, useBancoHorasOficial } = usePontoBancoHoras();

  const year = parseInt(competencia.split("-")[0]);
  const month = parseInt(competencia.split("-")[1]);
  const startDate = new Date(year, month - 1, 1);
  const endDate = new Date(year, month, 0);

  const { tenantId } = useAuth();
  const qc = useQueryClient();

  /**
   * LGPD arts. 11 e 46 (PONTO-397): exportar ponto tira dado pessoal de dentro
   * do sistema — e era a única operação sensível que não deixava rastro algum.
   * Cada exportação registra quem exportou, o quê e com que escopo. Falha no
   * registro não impede a exportação: o arquivo é o trabalho do RH; o log é
   * garantia, não obstáculo.
   */
  const registrarExportacao = async (
    acao: "exportou_afd" | "exportou_aej" | "exportou_relatorio",
    descricao: string,
  ) => {
    if (!tenantId) return;
    try {
      await (supabase.rpc as any)("ponto_log_exportacao", {
        p_tenant_id: tenantId,
        p_acao: acao,
        p_escopo: {
          competencia,
          empresa_id: empresaAtivaId || null,
          tipo_relatorio: tipoRelatorio,
        },
        p_descricao: descricao,
      });
    } catch {
      // ver comentário acima
    }
  };
  const { empresaAtivaId } = useEmpresaAtiva();

  // Nome das empresas: o relatório de Banco de Horas mistura filiais e o RH
  // pediu para identificar de quem é cada linha.
  const { data: empresas = [] } = useQuery({
    queryKey: ["ponto-relatorio-empresas", tenantId],
    enabled: !!tenantId,
    queryFn: async () => {
      const { data, error } = await fromTable("empresa_cadastro")
        .select("id, razao_social, nome_fantasia, cnpj, endereco, numero, bairro, cidade, estado")
        .eq("tenant_id", tenantId) as { data: any[] | null; error: Error | null };
      if (error) throw error;
      return data || [];
    },
  });
  const empresaPorId = (id?: string | null) =>
    id ? empresas.find((x: any) => x.id === id) : undefined;
  const nomeEmpresa = (id?: string | null) => {
    if (!id) return "Sem empresa vinculada";
    const e = empresaPorId(id);
    return e?.nome_fantasia || e?.razao_social || "Sem empresa vinculada";
  };
  // Razão social é o que vale juridicamente no cabeçalho do relatório.
  const razaoSocialEmpresa = (id?: string | null) => {
    const e = empresaPorId(id);
    return e?.razao_social || e?.nome_fantasia || null;
  };
  const soDigitos = (v?: string | null) => (v || "").replace(/\D/g, "");
  const formatarCnpj = (v?: string | null) => {
    const d = soDigitos(v);
    if (d.length !== 14) return null;
    return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
  };
  const empresaDoRelatorio = empresaAtivaId ? razaoSocialEmpresa(empresaAtivaId) : null;
  const cnpjDoRelatorio = empresaAtivaId
    ? formatarCnpj(empresaPorId(empresaAtivaId)?.cnpj)
    : null;


  const { data: espelhos = [] } = useEspelhos(competencia);
  const { data: bancosHorasTodos = [] } = useBancoHorasPorCompetencia(competencia);
  // Fonte única do banco de horas: é dela que saem os números impressos, para
  // o espelho e o relatório de banco de horas não discordarem entre si.
  const { data: bancoOficial = [] } = useBancoHorasOficial(competencia);
  const { colaboradores } = useColaboradores();

  const oficialPorCpf = useMemo(() => {
    const m = new Map<string, any>();
    (bancoOficial as any[]).forEach((o) => {
      const cpf = soDigitos(o.colaborador_cpf);
      if (cpf) m.set(cpf, o);
    });
    return m;
  }, [bancoOficial]);

  /**
   * A linha de banco de horas de um colaborador com os números oficiais.
   * Quando a fotografia da tabela está atrasada em relação à apuração, é o
   * número oficial que vale — a fotografia é que envelheceu.
   */
  const linhaOficial = (b: any) => {
    const o = oficialPorCpf.get(soDigitos(b.colaborador_cpf));
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

  // Quantos colaboradores têm a fotografia desatualizada. Serve para avisar
  // o RH de que a apuração precisa ser rodada de novo — o documento sai com
  // o número certo de qualquer jeito, mas a tela do banco de horas ainda
  // mostra o antigo até a próxima apuração.
  const desatualizados = useMemo(
    () => (bancoOficial as any[]).filter((o) => (o.divergencia_min ?? 0) !== 0).length,
    [bancoOficial],
  );

  // Demitido não entra no relatório de Banco de Horas: o saldo dele é
  // quitado na rescisão, não na conferência mensal do RH.
  // (useColaboradores já devolve apenas ativos — inativos/desligados ficam fora.)
  const bancosHoras = useMemo(() => {
    const cpfsAtivos = new Set(colaboradores.map((c) => soDigitos(c.cpf)));
    const idsAtivos = new Set(colaboradores.map((c) => c.id));
    return bancosHorasTodos.filter((b: any) => {
      const cpf = soDigitos(b.colaborador_cpf);
      if (cpf && cpfsAtivos.has(cpf)) return true;
      return Boolean(b.colaborador_id && idsAtivos.has(b.colaborador_id));
    });
  }, [bancosHorasTodos, colaboradores]);
  const { data: registrosMes = [], isLoading: carregandoRegistros } = usePontoDiario(startDate, endDate);

  const formatMinutos = (min: number) => formatarHoraMinuto(Math.abs(min || 0));

  // Saldo com sinal (negativo = devendo horas).
  const formatSaldo = (min: number) => formatarHoraMinuto(min || 0);

  // ---------------------------------------------------------------------
  // Espelho de ponto: dia a dia, da MESMA fonte do Banco de Horas
  // (`ponto_saldo_dias_competencia`). Antes o espelho lia os totais gravados
  // em `ponto_espelhos` no fechamento — por isso os dois relatórios não
  // batiam. Espelho é documento de conferência: precisa mostrar cada dia.
  // ---------------------------------------------------------------------
  type MarcacaoDia = {
    hora: string;
    tipo: string | null;
    /** RN26 — origem: O = original do colaborador, A = ajuste do RH. */
    origem: "O" | "A";
  };

  type DiaEspelho = {
    dia: string;
    entrada: string | null;
    saida: string | null;
    trabalhado_min: number;
    jornada_min: number;
    saldo_min: number;
    protegido: boolean;
    equalizacao: boolean;
    excedente_retido_min: number;
    marcacoes: MarcacaoDia[];
    // Súmula 338/TST: intervalo declarado (pré-assinalado) em vez de batido.
    intervalo_origem?: "marcado" | "pre_assinalado" | null;
    intervalo_pre_assinalado_min?: number | null;
    /**
     * Dia com marcação sem par (ou com ajuste em aberto). A apuração não
     * gera débito nesses dias — a falha de registro é do empregador (CLT
     * art. 74, §2º; Súmula 338) —, então o documento precisa dizer que o dia
     * está pendente, em vez de imprimir um zero silencioso.
     */
    pendencia?: boolean;
    /**
     * Dia declarado como folga compensatória. O débito dele vem da
     * compensação registrada no banco, não de uma ausência inferida — e o
     * documento precisa dizer isso: é o que distingue, para quem assina,
     * folga acordada de falta (Súmula 338 do TST).
     */
    folga_compensatoria?: boolean;
  };

  const DIAS_SEMANA = ["DOM", "SEG", "TER", "QUA", "QUI", "SEX", "SAB"];
  const diaDaSemana = (iso: string) => {
    const [a, m, d] = iso.split("-").map(Number);
    return DIAS_SEMANA[new Date(a, m - 1, d).getDay()];
  };
  const ehDomingo = (iso: string) => diaDaSemana(iso) === "DOM";
  const ehSabado = (iso: string) => diaDaSemana(iso) === "SAB";
  const dataBr = (iso: string) => {
    const [a, m, d] = iso.split("-");
    return `${d}/${m}/${a}`;
  };

  /** RN25 — rótulo de ocorrência do dia. */
  const situacaoDia = (d: DiaEspelho) => {
    if (d.folga_compensatoria) return d.trabalhado_min > 0
      ? "Folga compensatória (meio período)"
      : "Folga compensatória";
    if (d.pendencia) return "Pendência — marcação incompleta";
    if (d.equalizacao) return "Equalização";
    if (d.excedente_retido_min > 0) return "Excede limite diário";
    if (d.protegido) return d.trabalhado_min > 0 ? "Justificado (com trabalho)" : "Justificado";
    if (d.trabalhado_min === 0 && d.jornada_min > 0) return "Falta";
    if (d.trabalhado_min === 0) return ehDomingo(d.dia) ? "DSR" : ehSabado(d.dia) ? "Sábado" : "Sem jornada";
    if (d.jornada_min === 0) return ehDomingo(d.dia) ? "DSR trabalhado" : "Trabalho fora da escala";
    if (d.saldo_min < 0) return "Atraso / débito";
    if (d.saldo_min > 0) return "Trabalhando (crédito 1:1)";
    return "Trabalhando";
  };

  /** Percentual aplicável ao excedente do dia (RN17 / art. 59 CLT). */
  const percentualHE = (d: DiaEspelho) =>
    ehDomingo(d.dia) || d.jornada_min === 0 ? "100%" : "50%";

  /** Marcações do dia formatadas com o indicador de origem (RN26). */
  const marcacoesTexto = (d: DiaEspelho) =>
    d.marcacoes.length > 0
      ? d.marcacoes.map((m) => `${m.hora}${m.origem}`).join("  ")
      : "—";

  const carregarEspelhoDetalhado = async () => {
    // Quem entra no espelho: os colaboradores do fechamento quando existe;
    // caso contrário, quem tem marcação na competência.
    const base = espelhos.length > 0
      ? espelhos.map((e: any) => ({ nome: e.colaborador_nome, cpf: soDigitos(e.colaborador_cpf) }))
      : Array.from(new Set(registrosMes.map(r => soDigitos(r.colaborador_cpf)))).map(cpf => ({
          nome: registrosMes.find(r => soDigitos(r.colaborador_cpf) === cpf)?.colaborador_nome || "N/A",
          cpf,
        }));

    const unicos = Array.from(new Map(base.filter(b => b.cpf).map(b => [b.cpf, b])).values())
      .sort((a, b) => (a.nome || "").localeCompare(b.nome || "", "pt-BR"));

    // RN26 — todas as batidas da competência, com origem rastreável.
    // Paginado: o limite padrão do PostgREST (1000 linhas) truncava as últimas batidas do dia.
    const ultimoDia = new Date(year, month, 0).getDate();
    const marcacoesMes: any[] = [];
    const PAGINA = 1000;
    for (let offset = 0; ; offset += PAGINA) {
      const { data: pagina, error: errMarc } = await fromTable("ponto_marcacoes")
        .select("colaborador_cpf, data_marcacao, hora_marcacao, tipo_marcacao, marcacao_original, origem_marcacao")
        .eq("tenant_id", tenantId)
        .gte("data_marcacao", `${competencia}-01`)
        .lte("data_marcacao", `${competencia}-${String(ultimoDia).padStart(2, "0")}`)
        .order("data_marcacao")
        .order("hora_marcacao")
        .range(offset, offset + PAGINA - 1) as { data: any[] | null; error: any };
      if (errMarc) throw errMarc;
      const linhas = pagina || [];
      marcacoesMes.push(...linhas);
      if (linhas.length < PAGINA) break;
    }


    // Súmula 338/TST — origem do intervalo de cada dia (batido x declarado em
    // pré-assinalação). Vive em ponto_diario, não no resumo de saldo; sem isso
    // o cartão não consegue declarar o intervalo previsto.
    const intervaloPorCpfDia = new Map<string, { origem: string | null; minutos: number | null }>();
    // Dias em que a marcação ficou sem par (ou têm ajuste em aberto): a
    // apuração não debita esses dias, e o documento tem de mostrar a
    // pendência em vez de um zero sem explicação.
    const pendenciaPorCpfDia = new Set<string>();
    const folgaPorCpfDia = new Set<string>();
    {
      const { data: diarios, error: errDia } = await fromTable("ponto_diario")
        .select("colaborador_cpf, data, status, tipo_dia, intervalo_origem, intervalo_pre_assinalado_minutos")
        .eq("tenant_id", tenantId)
        .or("intervalo_origem.eq.pre_assinalado,status.in.(incompleto,ajuste_pendente),tipo_dia.eq.folga_compensatoria")
        .gte("data", `${competencia}-01`)
        .lte("data", `${competencia}-${String(ultimoDia).padStart(2, "0")}`) as { data: any[] | null; error: any };
      if (errDia) throw errDia;
      (diarios || []).forEach((d: any) => {
        const chave = `${soDigitos(d.colaborador_cpf)}|${d.data}`;
        if (d.intervalo_origem === "pre_assinalado") {
          intervaloPorCpfDia.set(chave, {
            origem: d.intervalo_origem ?? null,
            minutos: d.intervalo_pre_assinalado_minutos ?? null,
          });
        }
        if (d.status === "incompleto" || d.status === "ajuste_pendente") {
          pendenciaPorCpfDia.add(chave);
        }
        if (d.tipo_dia === "folga_compensatoria") {
          folgaPorCpfDia.add(chave);
        }
      });
    }

    const porCpfDia = new Map<string, MarcacaoDia[]>();
    (marcacoesMes || []).forEach((m: any) => {
      const chave = `${soDigitos(m.colaborador_cpf)}|${m.data_marcacao}`;
      const lista = porCpfDia.get(chave) || [];
      lista.push({
        hora: String(m.hora_marcacao || "").substring(0, 5),
        tipo: m.tipo_marcacao ?? null,
        origem: (m.origem_marcacao ?? (m.marcacao_original === false ? "A" : "O")) === "O" ? "O" : "A",
      });
      porCpfDia.set(chave, lista);
    });

    const resultado: Array<{
      nome: string; cpf: string; dias: DiaEspelho[];
      trabalhado: number; previsto: number; creditos: number; debitos: number;
      saldo: number; faltas: number; protegidos: number;
      he50: number; he100: number;
    }> = [];

    for (const c of unicos) {
      const { data, error } = await (supabase.rpc as any)("ponto_saldo_dias_competencia", {
        p_tenant_id: tenantId,
        p_colaborador_cpf: c.cpf,
        p_competencia: competencia,
      });
      if (error) throw error;

      const dias: DiaEspelho[] = ((data || []) as any[]).map(d => ({
        dia: String(d.dia),
        entrada: d.entrada ? String(d.entrada).substring(0, 5) : null,
        saida: d.saida ? String(d.saida).substring(0, 5) : null,
        trabalhado_min: Number(d.trabalhado_min) || 0,
        jornada_min: Number(d.jornada_min) || 0,
        saldo_min: Number(d.saldo_min) || 0,
        protegido: Boolean(d.protegido),
        equalizacao: Boolean(d.equalizacao),
        excedente_retido_min: Number(d.excedente_retido_min) || 0,
        marcacoes: (porCpfDia.get(`${c.cpf}|${String(d.dia)}`) || [])
          .slice()
          .sort((a, b) => a.hora.localeCompare(b.hora)),
        intervalo_origem: (intervaloPorCpfDia.get(`${c.cpf}|${String(d.dia)}`)?.origem ?? null) as
          | "marcado" | "pre_assinalado" | null,
        intervalo_pre_assinalado_min:
          intervaloPorCpfDia.get(`${c.cpf}|${String(d.dia)}`)?.minutos ?? null,
        pendencia: pendenciaPorCpfDia.has(`${c.cpf}|${String(d.dia)}`),
        folga_compensatoria: folgaPorCpfDia.has(`${c.cpf}|${String(d.dia)}`),
      })).sort((a, b) => a.dia.localeCompare(b.dia));

      resultado.push({
        nome: c.nome,
        cpf: c.cpf,
        dias,
        trabalhado: dias.reduce((s, d) => s + d.trabalhado_min, 0),
        previsto: dias.reduce((s, d) => s + d.jornada_min, 0),
        creditos: dias.reduce((s, d) => s + (d.saldo_min > 0 ? d.saldo_min : 0), 0),
        debitos: dias.reduce((s, d) => s + (d.saldo_min < 0 ? -d.saldo_min : 0), 0),
        saldo: dias.reduce((s, d) => s + d.saldo_min, 0),
        faltas: dias.filter(d => !d.protegido && d.jornada_min > 0 && d.trabalhado_min === 0).length,
        protegidos: dias.filter(d => d.protegido).length,
        // Extras separadas por percentual (RN28): 100% em domingo/dia sem
        // escala, 50% nos demais.
        he50: dias.reduce((s, d) => s + (d.saldo_min > 0 && percentualHE(d) === "50%" ? d.saldo_min : 0), 0),
        he100: dias.reduce((s, d) => s + (d.saldo_min > 0 && percentualHE(d) === "100%" ? d.saldo_min : 0), 0),
      });
    }

    return resultado;
  };





  const [perguntandoBanco, setPerguntandoBanco] = useState(false);

  // Cartão Ponto/Espelho podem sair sem o bloco de banco de horas: há folhas
  // que só apuram horas extras.
  const solicitarRelatorio = () => {
    if (tipoRelatorio === "espelho" || tipoRelatorio === "cartao_ponto") {
      setPerguntandoBanco(true);
      return;
    }
    gerarRelatorio(true);
  };

  const gerarRelatorio = async (comBanco: boolean) => {
    setGerando(true);
    try {
      if (tipoRelatorio === "afd") {
        await gerarAFD();
        return;
      }

      if (tipoRelatorio === "aej") {
        await gerarAEJ();
        return;
      }

      if (formatoExport === "pdf") {
        await gerarPDF(comBanco);
      } else {
        await gerarExcel(comBanco);
      }
    } catch (error) {
      toast.error("Erro ao gerar relatório");
    } finally {
      setGerando(false);
    }
  };

  const gerarAFD = async () => {
    // AFD posicional (Portaria MTP 671/2021, Anexo I — REP-P).
    // Puxa marcações REAIS da tabela ponto_marcacoes da empresa ativa.
    const startDate2 = `${competencia}-01`;
    const endMonth2 = parseInt(competencia.split("-")[1]);
    const endYear2 = parseInt(competencia.split("-")[0]);
    const lastDay2 = new Date(endYear2, endMonth2, 0).getDate();
    const endDate2 = `${competencia}-${String(lastDay2).padStart(2, "0")}`;

    let query = fromTable("ponto_marcacoes")
      .select("colaborador_cpf, colaborador_nome, data_marcacao, hora_marcacao, hash_marcacao")
      .gte("data_marcacao", startDate2)
      .lte("data_marcacao", endDate2)
      .order("data_marcacao")
      .order("hora_marcacao")
      .limit(50000);
    if (empresaAtivaId) query = query.eq("empresa_id", empresaAtivaId);

    const { data: marcacoes, error } = (await query) as { data: any[] | null; error: any };

    if (error) {
      toast.error("Erro ao buscar marcações: " + error.message);
      return;
    }

    const registros = marcacoes || [];
    if (registros.length === 0) {
      toast.warning("Nenhuma marcação encontrada para esta competência.");
      return;
    }

    const empresa = empresaPorId(empresaAtivaId);
    const endereco = [empresa?.endereco, empresa?.numero, empresa?.bairro, empresa?.cidade, empresa?.estado]
      .filter(Boolean)
      .join(", ");

    // Registro tipo 5 exige um empregado por CPF, sem repetição.
    const porCpf = new Map<string, string>();
    registros.forEach((m: any) => {
      const cpf = soDigitos(m.colaborador_cpf);
      if (cpf.length === 11 && !porCpf.has(cpf)) porCpf.set(cpf, m.colaborador_nome || "");
    });

    const { conteudo, totais } = await gerarAFD671({
      empregador: {
        documento: soDigitos(empresa?.cnpj),
        razaoSocial: razaoSocialEmpresa(empresaAtivaId) || "YOUREYES",
        localPrestacao: endereco,
      },
      empregados: Array.from(porCpf, ([cpf, nome]) => ({ cpf, nome })),
      marcacoes: registros.map((m: any) => ({
        data: String(m.data_marcacao || "").slice(0, 10),
        hora: String(m.hora_marcacao || "00:00:00"),
        cpf: soDigitos(m.colaborador_cpf),
        hash: m.hash_marcacao,
      })),
      dataInicial: startDate2,
      dataFinal: endDate2,
      identificadorRep: "YOUREYES REP-P",
    });

    const blob = new Blob([conteudo], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `AFD_${soDigitos(empresa?.cnpj) || "EMPRESA"}_${competencia.replace("-", "")}.txt`;
    a.click();
    URL.revokeObjectURL(url);
    await registrarExportacao("exportou_afd", `AFD da competência ${competencia}: ${totais.marcacoes} marcações, ${totais.empregados} empregados.`);
    toast.success(
      `AFD gerado: ${totais.marcacoes} marcações, ${totais.empregados} empregados (${totais.registros} registros).`,
    );
  };

  // AEJ — jornada APURADA da competência: horários contratuais, marcações
  // originais do REP e ajustes já APROVADOS pelo RH (pendentes/rejeitados
  // ficam de fora, conforme Portaria MTP 671/2021).
  const gerarAEJ = async () => {
    const inicio = `${competencia}-01`;
    const mes = parseInt(competencia.split("-")[1]);
    const ano = parseInt(competencia.split("-")[0]);
    const ultimoDia = new Date(ano, mes, 0).getDate();
    const fim = `${competencia}-${String(ultimoDia).padStart(2, "0")}`;

    const filtrarEmpresa = (q: any) => (empresaAtivaId ? q.eq("empresa_id", empresaAtivaId) : q);

    const [marcRes, ajusteRes, escalaRes, atribRes] = await Promise.all([
      filtrarEmpresa(
        fromTable("ponto_marcacoes")
          .select("colaborador_cpf, colaborador_nome, data_marcacao, hora_marcacao, origem_marcacao")
          .gte("data_marcacao", inicio)
          .lte("data_marcacao", fim)
          .limit(50000),
      ),
      filtrarEmpresa(
        fromTable("ponto_ajustes")
          .select(
            "colaborador_cpf, colaborador_nome, data_referencia, tipo_ajuste, hora_solicitada, motivo, dia_inteiro, horas_abonadas, status",
          )
          .eq("status", "aprovado")
          .gte("data_referencia", inicio)
          .lte("data_referencia", fim)
          .limit(50000),
      ),
      filtrarEmpresa(
        fromTable("ponto_escalas").select(
          "id, nome, hora_entrada_padrao, hora_saida_padrao, intervalo_intrajornada_minutos, jornada_diaria_minutos",
        ),
      ),
      fromTable("ponto_escala_atribuicoes")
        .select("escala_id, colaborador_cpf, data_inicio, data_fim, ativa")
        .lte("data_inicio", fim)
        .limit(50000),
    ]);

    const erro = marcRes.error || ajusteRes.error || escalaRes.error || atribRes.error;
    if (erro) {
      toast.error("Erro ao montar AEJ: " + erro.message);
      return;
    }

    const marcacoesDb: any[] = marcRes.data || [];
    const ajustesDb: any[] = ajusteRes.data || [];
    if (marcacoesDb.length === 0 && ajustesDb.length === 0) {
      toast.warning("Nenhuma jornada apurada nesta competência.");
      return;
    }

    // Empregados: união dos CPFs com movimento no período.
    const nomePorCpf = new Map<string, string>();
    [...marcacoesDb, ...ajustesDb].forEach((r) => {
      const cpf = soDigitos(r.colaborador_cpf);
      if (cpf.length === 11 && !nomePorCpf.has(cpf)) nomePorCpf.set(cpf, r.colaborador_nome || "");
    });

    // Horários contratuais e vínculos vigentes no período.
    const escalas: any[] = escalaRes.data || [];
    const escalaPorId = new Map(escalas.map((e: any) => [e.id, e]));
    const atribuicoes = (atribRes.data || []).filter((a: any) => {
      const cpf = soDigitos(a.colaborador_cpf);
      if (!nomePorCpf.has(cpf)) return false;
      return !a.data_fim || a.data_fim >= inicio;
    });
    const escalasUsadas = new Set(atribuicoes.map((a: any) => a.escala_id));

    const horarios = escalas
      .filter((e: any) => escalasUsadas.has(e.id))
      .map((e: any) => {
        const entrada = (e.hora_entrada_padrao || "").slice(0, 5) || null;
        const saida = (e.hora_saida_padrao || "").slice(0, 5) || null;
        const intervalo = Number(e.intervalo_intrajornada_minutos || 0);
        // O intervalo é derivado do fim da jornada quando a escala não fixa horário de almoço.
        const somarMin = (hora: string | null, min: number) => {
          if (!hora) return null;
          const [h, m] = hora.split(":").map(Number);
          const t = h * 60 + m + min;
          return `${String(Math.floor((t % 1440) / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
        };
        const inicioIntervalo = entrada && intervalo > 0 ? somarMin(entrada, 4 * 60) : null;
        return {
          codigo: String(e.id).slice(0, 8).toUpperCase(),
          descricao: e.nome || "ESCALA",
          entrada,
          saidaIntervalo: inicioIntervalo,
          retornoIntervalo: somarMin(inicioIntervalo, intervalo),
          saida,
          cargaDiariaMinutos: Number(e.jornada_diaria_minutos || 0),
        };
      });

    const vinculos = atribuicoes.map((a: any) => ({
      cpf: soDigitos(a.colaborador_cpf),
      codigoHorario: String(a.escala_id).slice(0, 8).toUpperCase(),
      dataInicio: String(a.data_inicio || inicio).slice(0, 10),
      dataFim: a.data_fim ? String(a.data_fim).slice(0, 10) : null,
    }));
    void escalaPorId;

    const marcacoes: AejMarcacao[] = marcacoesDb
      .filter((m) => soDigitos(m.colaborador_cpf).length === 11)
      .map((m) => ({
        cpf: soDigitos(m.colaborador_cpf),
        data: String(m.data_marcacao).slice(0, 10),
        hora: String(m.hora_marcacao || "00:00:00"),
        origem: (m.origem_marcacao === "A" ? "A" : "O") as "O" | "A",
      }));

    const ocorrencias: AejOcorrencia[] = [];
    ajustesDb.forEach((a) => {
      const cpf = soDigitos(a.colaborador_cpf);
      if (cpf.length !== 11) return;
      const data = String(a.data_referencia).slice(0, 10);
      // Ajuste de horário aprovado vira marcação origem "A"; abono/dia inteiro vira ocorrência.
      if (a.hora_solicitada && !a.dia_inteiro) {
        marcacoes.push({
          cpf,
          data,
          hora: String(a.hora_solicitada),
          origem: "A",
          justificativa: a.motivo || "AJUSTE APROVADO",
        });
      } else {
        ocorrencias.push({
          cpf,
          data,
          codigo: String(a.tipo_ajuste || "ABONO").toUpperCase(),
          minutos: Math.round(Number(a.horas_abonadas || 0) * 60),
          descricao: a.motivo || "",
        });
      }
    });

    const empresa = empresaPorId(empresaAtivaId);
    const endereco = [empresa?.endereco, empresa?.numero, empresa?.bairro, empresa?.cidade, empresa?.estado]
      .filter(Boolean)
      .join(", ");

    const { conteudo, totais } = gerarAEJ671({
      empregador: {
        documento: soDigitos(empresa?.cnpj),
        razaoSocial: razaoSocialEmpresa(empresaAtivaId) || "YOUREYES",
        localPrestacao: endereco,
      },
      empregados: Array.from(nomePorCpf, ([cpf, nome]) => ({ cpf, nome })),
      horarios,
      vinculos,
      marcacoes,
      ocorrencias,
      dataInicial: inicio,
      dataFinal: fim,
    });

    // Portaria MTP 671/2021 — além do arquivo entregue, o AEJ TRATADO é
    // arquivado e assinado (hash) no banco: é a prova de que a jornada
    // apurada não mudou depois da geração. O download abaixo continua sendo
    // o arquivo no leiaute oficial; a cópia arquivada guarda o conteúdo
    // tratado com a assinatura, e aparece no cartão "AEJ arquivado".
    let assinatura: string | null = null;
    try {
      await (supabase.rpc as any)("ponto_gerar_aej", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
      });
      qc.invalidateQueries({ queryKey: ["ponto-aej-arquivado"] });
      const { data: arq } = await (supabase.rpc as any)("ponto_aej_extrair", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
      });
      assinatura = (arq || [])[0]?.hash_arquivo || null;
    } catch (e: any) {
      // O arquivo oficial continua saindo; só o arquivamento falhou.
      toast.warning("AEJ gerado, mas não foi possível arquivar a cópia assinada: " + (e?.message || ""));
    }

    const blob = new Blob([conteudo], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `AEJ_${soDigitos(empresa?.cnpj) || "EMPRESA"}_${competencia.replace("-", "")}.txt`;
    a.click();
    URL.revokeObjectURL(url);
    await registrarExportacao("exportou_aej", `AEJ da competência ${competencia}: ${totais.marcacoes} marcações, ${totais.empregados} empregados.`);
    toast.success(
      `AEJ gerado: ${totais.marcacoes} marcações (${totais.ajustes} ajustes aprovados), ${totais.ocorrencias} ocorrências, ${totais.empregados} empregados.`
      + (assinatura ? ` Cópia arquivada e assinada (${assinatura.slice(0, 12)}...).` : ""),
    );
  };

  // Cópia tratada e assinada da competência (Portaria 671). Só leitura: mostra
  // o que já foi arquivado, sem gerar nada.
  const { data: aejArquivado } = useQuery({
    queryKey: ["ponto-aej-arquivado", tenantId, empresaAtivaId, competencia],
    queryFn: async () => {
      if (!tenantId) return null;
      const { data, error } = await (supabase.rpc as any)("ponto_aej_extrair", {
        p_tenant_id: tenantId,
        p_empresa_id: empresaAtivaId || null,
        p_competencia: competencia,
      });
      if (error) throw error;
      return ((data || []) as any[])[0] || null;
    },
    enabled: !!tenantId && !!competencia && tipoRelatorio === "aej",
  });

  const baixarAejArquivado = () => {
    if (!aejArquivado?.conteudo) return;
    const blob = new Blob([aejArquivado.conteudo], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `AEJ_TRATADO_${competencia.replace("-", "")}.txt`;
    a.click();
    URL.revokeObjectURL(url);
    void registrarExportacao("exportou_aej", `Cópia arquivada e assinada do AEJ da competência ${competencia}.`);
  };


  const gerarPDF = async (comBanco = true) => {
    const doc = new jsPDF();
    const titulo = REPORT_TYPES.find(r => r.value === tipoRelatorio)?.label || "Relatório";
    const subtitulo = REPORT_TYPES.find(r => r.value === tipoRelatorio)?.desc;
    const logo = await carregarLogo();
    const geradoEm = format(new Date(), "dd/MM/yyyy 'às' HH:mm");

    const cabecalho = () => desenharCabecalho(doc, {
      titulo,
      subtitulo,
      empresa: empresaDoRelatorio,
      cnpj: cnpjDoRelatorio,

      competencia,
      geradoEm,
      logoDataUrl: logo,
    });

    if (tipoRelatorio === "cartao_ponto" || tipoRelatorio === "espelho") {
      // Modelo clássico de cartão ponto: uma folha por colaborador, com a
      // mesma apuração do Banco de Horas.
      const detalhado = await carregarEspelhoDetalhado();
      if (detalhado.length === 0) {
        toast.warning("Nenhum colaborador com apuração nesta competência.");
        return;
      }

      const emp: any = empresaPorId(empresaAtivaId) || {};
      const enderecoCompleto = [emp.endereco, emp.numero, emp.bairro]
        .filter(Boolean).join(", ") || null;
      const ultimoDiaMes = new Date(year, month, 0).getDate();
      const periodo = `01/${String(month).padStart(2, "0")}/${year} a ${ultimoDiaMes}/${String(month).padStart(2, "0")}/${year}`;

      detalhado.forEach((c, i) => {
        if (i > 0) doc.addPage();
        const col = colaboradores.find((x: any) => soDigitos(x.cpf) === c.cpf) as any;
        const banco: any = bancosHorasTodos.find(
          (b: any) => soDigitos(b.colaborador_cpf) === c.cpf,
        );

        desenharCartaoPonto(doc, {
          incluirBanco: comBanco,
          empregador: {
            razaoSocial: empresaDoRelatorio || "—",
            cnpj: cnpjDoRelatorio,
            endereco: enderecoCompleto,
            cidade: emp.cidade || null,
            uf: emp.estado || null,
          },
          empregado: {
            nome: c.nome,
            cpf: c.cpf,
            matricula: col?.matricula || null,
            cargo: col?.cargo || null,
            setor: col?.departamento || null,
            admissao: col?.data_admissao
              ? dataBr(String(col.data_admissao).substring(0, 10))
              : null,
            categoria: col?.tipo_contrato || "Mensalista",
            horarios: col?.jornada_trabalho || null,
          },
          periodo,
          emissao: geradoEm,
          dias: c.dias,
          // Crédito/débito/saldo vêm da FONTE ÚNICA do banco de horas, a
          // mesma que o relatório de Banco de Horas imprime: competência
          // fechada devolve a apuração congelada (Súmula 338), competência
          // aberta devolve a apuração de agora somada aos lançamentos
          // manuais e compensações. Antes cada documento fazia a própria
          // conta e os dois podiam discordar no mesmo dia.
          banco: (() => {
            const of = oficialPorCpf.get(c.cpf);
            if (of) {
              return {
                saldoAnterior: of.saldo_anterior_min,
                creditos: of.creditos_min,
                debitos: of.debitos_min,
                compensados: of.compensados_min,
                saldoAtual: of.saldo_atual_min,
                temRegime: of.tem_regime !== false,
              };
            }
            return {
              saldoAnterior: banco?.saldo_anterior_minutos ?? 0,
              creditos: c.creditos,
              debitos: c.debitos,
              compensados: banco?.compensados_minutos ?? 0,
              saldoAtual:
                (banco?.saldo_anterior_minutos ?? 0) +
                c.saldo -
                (banco?.compensados_minutos ?? 0),
            };
          })(),

          logoDataUrl: logo,
        });
      });

      const nomeArq = tipoRelatorio === "espelho" ? "espelho-ponto" : "cartao-ponto";
      doc.save(`${nomeArq}-${competencia}.pdf`);
      void registrarExportacao("exportou_relatorio", `PDF: ${nomeArq} da competência ${competencia}.`);
      toast.success(tipoRelatorio === "espelho" ? "Espelho de ponto gerado!" : "Cartão ponto gerado!");
      return;
    }

    if (tipoRelatorio === "horas_extras") {
      // O modelo atual apura saldo em minutos, não percentuais: imprimir
      // "0h 00min" em HE 50/100 afirmaria que não houve hora extra.
      const head = [["Colaborador", "Trabalhado", "Previsto", "Excedente do período"]];
      const comExcedente = espelhos.filter(e => (e.banco_horas_saldo_minutos ?? 0) > 0);
      const body = comExcedente.length > 0
        ? comExcedente.map(e => [
            e.colaborador_nome,
            formatMinutos(e.total_trabalhado_minutos ?? 0),
            formatMinutos(e.total_jornada_prevista_minutos ?? 0),
            "+" + formatMinutos(e.banco_horas_saldo_minutos ?? 0),
          ])
        : [["Nenhum excedente apurado no período", "", "", ""]];

      autoTable(doc, {
        ...estiloTabela(),
        head,
        body,
        columnStyles: { 1: { halign: "right" }, 2: { halign: "right" }, 3: { halign: "right" } },
        didDrawPage: cabecalho,
      });

      const yFim = (doc as any).lastAutoTable?.finalY || ALTURA_CABECALHO;
      doc.setFont("helvetica", "italic");
      doc.setFontSize(7.5);
      doc.setTextColor(MARCA.cinza[0], MARCA.cinza[1], MARCA.cinza[2]);
      doc.text(
        "A separação entre hora extra 50% e 100% não é apurada neste modelo — a apuração trabalha em saldo de minutos.",
        14, yFim + 6);
      doc.text(
        "O adicional de feriado trabalhado é calculado em campo próprio, na exportação da Folha.",
        14, yFim + 10);
    } else if (tipoRelatorio === "absenteismo") {
      const head = [["Colaborador", "Faltas", "Atrasos"]];
      const faltosos = registrosMes.filter(r => r.status === "falta" || r.status === "atraso");
      const body: any[] = [];
      if (faltosos.length > 0) {
        const colabNames = Array.from(new Set(faltosos.map(f => f.colaborador_nome)));
        colabNames.forEach(nome => {
          const totalFaltas = faltosos.filter(f => f.colaborador_nome === nome && f.status === "falta").length;
          const totalAtrasos = faltosos.filter(f => f.colaborador_nome === nome && f.status === "atraso").length;
          body.push([nome, String(totalFaltas), String(totalAtrasos)]);
        });
      } else {
        body.push(["Nenhuma falta ou atraso registrado no período", "", ""]);
      }

      autoTable(doc, {
        ...estiloTabela(),
        head,
        body,
        columnStyles: { 1: { halign: "center" }, 2: { halign: "center" } },
        didDrawPage: cabecalho,
      });
    } else if (tipoRelatorio === "banco_horas") {
      // Agrupado por empresa: o RH pediu para saber de quem é cada linha, e
      // o subtotal por empresa é o que ele leva para a conferência.
      const head = [["Colaborador", "Saldo Anterior", "Créditos", "Débitos", "Compensados", "Saldo Atual"]];
      const porEmpresa = new Map<string, any[]>();
      bancosHoras.forEach(b => {
        const chave = nomeEmpresa((b as any).empresa_id);
        if (!porEmpresa.has(chave)) porEmpresa.set(chave, []);
        // Números da fonte única: o mesmo que o espelho imprime.
        porEmpresa.get(chave)!.push(linhaOficial(b));
      });

      const body: any[] = [];
      const estilosLinha: Record<number, any> = {};
      let idx = 0;
      let totalGeral = 0;

      Array.from(porEmpresa.keys())
        .sort((a, b) => a.localeCompare(b, "pt-BR"))
        .forEach(emp => {
          const lista = porEmpresa.get(emp)!;
          estilosLinha[idx] = {
            fillColor: [226, 236, 247],
            fontStyle: "bold",
            textColor: MARCA.navy,
          };
          body.push([emp, "", "", "", "", ""]);
          idx += 1;

          let soma = 0;
          lista.forEach((b: any) => {
            soma += b.saldo_atual_minutos || 0;
            body.push([
              "   " + b.colaborador_nome,
              formatSaldo(b.saldo_anterior_minutos),
              "+" + formatMinutos(b.creditos_minutos),
              "-" + formatMinutos(b.debitos_minutos),
              formatMinutos(b.compensados_minutos),
              formatSaldo(b.saldo_atual_minutos),
            ]);
            idx += 1;
          });

          estilosLinha[idx] = { fillColor: MARCA.cinzaClaro, fontStyle: "bold" };
          body.push([`   Subtotal — ${lista.length} colaborador(es)`, "", "", "", "", formatSaldo(soma)]);
          idx += 1;
          totalGeral += soma;
        });

      if (body.length > 0) {
        estilosLinha[idx] = { fillColor: MARCA.navy, textColor: MARCA.branco, fontStyle: "bold" };
        body.push(["TOTAL GERAL", "", "", "", "", formatSaldo(totalGeral)]);
      }

      autoTable(doc, {
        ...estiloTabela(),
        head,
        body: body.length > 0
          ? body
          : [['Nenhum saldo apurado nesta competência. Use "Apurar agora" no Banco de Horas.', "", "", "", "", ""]],
        columnStyles: {
          1: { halign: "right" }, 2: { halign: "right" }, 3: { halign: "right" },
          4: { halign: "right" }, 5: { halign: "right" },
        },
        didParseCell: (data: any) => {
          if (data.section === "body" && estilosLinha[data.row.index]) {
            Object.assign(data.cell.styles, estilosLinha[data.row.index]);
          }
        },
        didDrawPage: cabecalho,
      });
    }

    const pageCount = doc.getNumberOfPages();
    for (let i = 1; i <= pageCount; i++) {
      doc.setPage(i);
      desenharRodape(doc, i, pageCount);
    }

    doc.save(`${titulo.replace(/\s/g, "_")}_${competencia}.pdf`);
    void registrarExportacao("exportou_relatorio", `PDF: ${titulo} da competência ${competencia}.`);
    toast.success("PDF gerado!");
  };

  const gerarExcel = async (comBanco = true) => {
    const titulo = REPORT_TYPES.find(r => r.value === tipoRelatorio)?.label || "Relatório";
    const wb = XLSX.utils.book_new();

    if (tipoRelatorio === "espelho" || tipoRelatorio === "cartao_ponto") {

      // Duas abas: resumo (mesmos números do Banco de Horas) e dia a dia.
      const detalhado = await carregarEspelhoDetalhado();
      const resumo = detalhado.map(c => ({
        Colaborador: c.nome,
        CPF: c.cpf,
        "Trabalhado (min)": c.trabalhado,
        "Previsto (min)": c.previsto,
        "Créditos (min)": c.creditos,
        "Débitos (min)": c.debitos,
        "Saldo (min)": c.saldo,
        Faltas: c.faltas,
        "Dias justificados": c.protegidos,
        Competência: competencia,
      }));
      const diario = detalhado.flatMap(c => c.dias.map(d => ({
        Colaborador: c.nome,
        CPF: c.cpf,
        Data: dataBr(d.dia),
        "Dia da semana": diaDaSemana(d.dia),
        "Marcações (O=original, A=ajuste)": marcacoesTexto(d),
        // Súmula 338/TST: intervalo declarado, não batido.
        "Intervalo pré-assinalado (min)":
          d.intervalo_origem === "pre_assinalado" ? (d.intervalo_pre_assinalado_min ?? "") : "",
        Entrada: d.entrada || "",
        Saída: d.saida || "",
        "Trabalhado (min)": d.trabalhado_min,
        "Previsto (min)": d.jornada_min,
        "Extras (min)": d.saldo_min > 0 ? d.saldo_min : 0,
        "% Extras": d.saldo_min > 0 ? percentualHE(d) : "",
        "Saldo (min)": d.saldo_min,
        Ocorrência: situacaoDia(d),
      })));
      const resumoFinal = comBanco
        ? resumo
        : resumo.map(({ "Créditos (min)": _c, "Débitos (min)": _d, "Saldo (min)": _s, ...r }) => r);
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(resumoFinal), "Resumo");
      XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(diario), "Dia a dia");
      XLSX.writeFile(wb, `Espelho_de_Ponto_${competencia}.xlsx`);
      void registrarExportacao("exportou_relatorio", `Planilha: espelho de ponto da competência ${competencia}.`);
      toast.success("Excel gerado!");
      return;
    }

    let dados: any[] = [];

    if (tipoRelatorio === "banco_horas") {
      dados = bancosHoras.map(linhaOficial).map(b => ({
        Empresa: nomeEmpresa((b as any).empresa_id),
        Colaborador: b.colaborador_nome,
        CPF: b.colaborador_cpf,
        "Saldo Anterior (min)": b.saldo_anterior_minutos,
        "Créditos (min)": b.creditos_minutos,
        "Débitos (min)": b.debitos_minutos,
        "Compensados (min)": b.compensados_minutos,
        "Saldo Atual (min)": b.saldo_atual_minutos,
        Competência: b.competencia,
      }));
    } else {
      dados = registrosMes.map(r => ({
        Data: r.data,
        Colaborador: r.colaborador_nome,
        CPF: r.colaborador_cpf,
        Entrada: r.entrada,
        "Saída Almoço": r.saida_almoco,
        "Retorno Almoço": r.retorno_almoco,
        Saída: r.saida,
        Status: r.status,
        Observação: r.observacao
      }));
    }

    const ws = XLSX.utils.json_to_sheet(dados);
    XLSX.utils.book_append_sheet(wb, ws, titulo);
    XLSX.writeFile(wb, `${titulo.replace(/\s/g, "_")}_${competencia}.xlsx`);
    void registrarExportacao("exportou_relatorio", `Planilha: ${titulo} da competência ${competencia}.`);
    toast.success("Excel gerado!");
  };


  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-lg font-semibold flex items-center gap-2">
          <FileDown className="w-5 h-5 text-primary" /> Relatórios do Ponto
        </h3>
        <p className="text-sm text-muted-foreground">Gere relatórios legais e gerenciais</p>
      </div>

      {desatualizados > 0 && (
        <div className="rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
          <span className="font-medium">
            {desatualizados} colaborador(es) com apuração de banco de horas desatualizada nesta
            competência.
          </span>{" "}
          Algo mudou depois da última apuração — um ajuste aprovado, um atestado ou uma marcação
          que chegou depois. Os relatórios já saem com o número correto; para a tela de Banco de
          Horas mostrar o mesmo, rode a apuração da competência.
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="space-y-2">
          <Label>Competência</Label>
          <CompetenciaInput value={competencia} onChange={setCompetencia} />
        </div>
        <div className="space-y-2">
          <Label>Tipo de Relatório</Label>
          <Select value={tipoRelatorio} onValueChange={v => setTipoRelatorio(v as ReportType)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              {REPORT_TYPES.map(r => <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Formato</Label>
          {tipoRelatorio === "afd" || tipoRelatorio === "aej" ? (
            <Input value="TXT (Portaria 671)" disabled />
          ) : (
            <Select value={formatoExport} onValueChange={v => setFormatoExport(v as "pdf" | "excel")}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="pdf">PDF</SelectItem>
                <SelectItem value="excel">Excel</SelectItem>
              </SelectContent>
            </Select>
          )}
        </div>
      </div>

      {/* Data preview/summary */}
      {!carregandoRegistros && (
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium">Resumo do Período</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div>
                <p className="text-2xl font-bold">{registrosMes.length}</p>
                <p className="text-xs text-muted-foreground">Total de Batidas</p>
              </div>
              <div>
                <p className="text-2xl font-bold">{new Set(registrosMes.map(r => r.colaborador_cpf)).size}</p>
                <p className="text-xs text-muted-foreground">Colaboradores</p>
              </div>
              <div>
                <p className="text-2xl font-bold text-red-500">
                  {registrosMes.filter(r => r.status === "falta").length}
                </p>
                <p className="text-xs text-muted-foreground">Faltas Identificadas</p>
              </div>
              <div>
                <p className="text-2xl font-bold text-orange-500">
                  {espelhos.length > 0 ? "Fechado" : "Aberto"}
                </p>
                <p className="text-xs text-muted-foreground">Status do Mês</p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Report description */}
      <Card>
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <FileText className="w-5 h-5 text-primary mt-0.5" />
            <div>
              <p className="font-medium">{REPORT_TYPES.find(r => r.value === tipoRelatorio)?.label}</p>
              <p className="text-sm text-muted-foreground">{REPORT_TYPES.find(r => r.value === tipoRelatorio)?.desc}</p>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* AEJ tratado e assinado, já arquivado (Portaria MTP 671/2021) */}
      {tipoRelatorio === "aej" && aejArquivado && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <Archive className="w-4 h-4 text-primary" />
              Cópia arquivada e assinada desta competência
            </CardTitle>
          </CardHeader>
          <CardContent className="p-4 pt-0 space-y-3">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <div>
                <p className="text-xs text-muted-foreground">Gerada em</p>
                <p className="font-medium">
                  {aejArquivado.gerado_em
                    ? format(new Date(aejArquivado.gerado_em), "dd/MM/yyyy 'às' HH:mm")
                    : "—"}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Trabalhadores</p>
                <p className="font-medium">{aejArquivado.total_trabalhadores ?? "—"}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Marcações</p>
                <p className="font-medium">{aejArquivado.total_marcacoes ?? "—"}</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Registros</p>
                <p className="font-medium">{aejArquivado.total_registros ?? "—"}</p>
              </div>
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Assinatura (hash) do conteúdo tratado</p>
              <p className="font-mono text-[11px] break-all">{aejArquivado.hash_arquivo || "—"}</p>
            </div>
            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm" onClick={baixarAejArquivado}>
                <Download className="w-4 h-4 mr-2" /> Baixar cópia tratada
              </Button>
              <p className="text-xs text-muted-foreground">
                Guarda a jornada tratada como estava na geração. O arquivo entregue à
                fiscalização é o do botão de gerar, no leiaute oficial.
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      <IncluirBancoHorasDialog
        open={perguntandoBanco}
        onOpenChange={setPerguntandoBanco}
        onConfirm={(comBanco) => {
          setPerguntandoBanco(false);
          gerarRelatorio(comBanco);
        }}
      />

      <Button onClick={solicitarRelatorio} disabled={gerando} className="w-full md:w-auto">
        <Download className="w-4 h-4 mr-2" />
        {gerando ? "Gerando..." : "Gerar Relatório"}
      </Button>

      {/* Info about AFD/AEFP */}
      <Card className="bg-muted/30">
        <CardContent className="p-4">
          <h4 className="font-medium mb-2">📋 Arquivos Legais (Portaria MTP 671/2021)</h4>
          <ul className="text-sm text-muted-foreground space-y-1">
            <li>• <strong>AFD</strong> — Arquivo Fonte de Dados: registro imutável de todas as marcações (.txt)</li>
            <li>• <strong>AEJ</strong> — Arquivo Eletrônico de Jornada: jornada apurada com horários contratuais, marcações originais e ajustes aprovados (.txt)</li>
            <li>• <strong>AEFP</strong> — Espelho de Ponto: gerado automaticamente na aba Fechamento</li>
            <li>• Retenção mínima: 5 anos para fiscalização trabalhista</li>
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}
