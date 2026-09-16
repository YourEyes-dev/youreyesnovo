import { useState, useMemo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Checkbox } from "@/components/ui/checkbox";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { usePontoEscalas, ESCALA_TIPOS, type PontoEscala } from "@/hooks/usePontoEscalas";
import { useEscalaDetalhes, DIAS_SEMANA_LABEL, ORDINAL_MES_LABEL } from "@/hooks/useEscalaDetalhes";
import { useColaboradores } from "@/hooks/useColaboradores";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { PontoEscalaAvisos } from "@/components/ponto/PontoEscalaAvisos";
import { Plus, Calendar, Clock, Users, Settings, Sparkles, Pencil, Power, Trash2, CalendarDays, Repeat, Copy, Search, AlertTriangle } from "lucide-react";
import { toast } from "sonner";
import { confirm } from "@/components/ui/confirm-dialog";
import { CadastroInteligenteEscala } from "./CadastroInteligenteEscala";
import { formatarHoraMinuto } from "@/lib/ponto/formatoHoras";

export function PontoEscalasTab() {
  const { escalas, loadingEscalas, atribuicoes: atribuicoesRaw, criarEscala, criandoEscala, atualizarEscala, atualizandoEscala, excluirEscala, atribuirEscala } = usePontoEscalas();
  const { colaboradores } = useColaboradores();
  // Filtra atribuições pelos colaboradores da empresa ativa (cruzamento por CPF/ID)
  const cpfsEmpresa = new Set(colaboradores.map(c => (c.cpf || "").replace(/\D/g, "")).filter(Boolean));
  const idsEmpresa = new Set(colaboradores.map(c => c.id));
  const atribuicoes = atribuicoesRaw.filter((a: any) => {
    const cpf = (a.colaborador_cpf || "").replace(/\D/g, "");
    return (cpf && cpfsEmpresa.has(cpf)) || (a.colaborador_id && idsEmpresa.has(a.colaborador_id));
  });
  const [showCriar, setShowCriar] = useState(false);
  const [editando, setEditando] = useState<PontoEscala | null>(null);
  const [showInteligente, setShowInteligente] = useState(false);
  const [showAtribuir, setShowAtribuir] = useState(false);
  const DIAS_KEYS = ["segunda","terca","quarta","quinta","sexta","sabado","domingo"] as const;
  const DIAS_LBL: Record<string,string> = { segunda:"Segunda", terca:"Terça", quarta:"Quarta", quinta:"Quinta", sexta:"Sexta", sabado:"Sábado", domingo:"Domingo" };
  type DiaConfig = {
    trabalha: boolean;
    tem_almoco: boolean;
    entrada: string;        // 1ª marcação (início do expediente)
    inicio_almoco: string;  // 2ª marcação (saída p/ almoço)
    fim_almoco: string;     // 3ª marcação (retorno do almoço)
    saida: string;          // 4ª marcação (fim do expediente)
  };
  type Compensacao = {
    ordinal_mes: string;   // "1","2","3","4","ultimo"
    dia_semana: string;
    entrada: string;
    saida: string;
    intervalo: number;
    descricao?: string;
  };
  const ORDINAIS_MES = [
    { value: "1", label: "1º" },
    { value: "2", label: "2º" },
    { value: "3", label: "3º" },
    { value: "4", label: "4º" },
    { value: "ultimo", label: "Último" },
  ];
  const diaPadrao = (trabalha: boolean): DiaConfig => ({
    trabalha,
    tem_almoco: trabalha,
    entrada: "08:00",
    inicio_almoco: "12:00",
    fim_almoco: "13:00",
    saida: "17:00",
  });
  const diasConfigPadrao = (): Record<string, DiaConfig> => ({
    segunda: diaPadrao(true),
    terca:   diaPadrao(true),
    quarta:  diaPadrao(true),
    quinta:  diaPadrao(true),
    sexta:   diaPadrao(true),
    sabado:  diaPadrao(false),
    domingo: diaPadrao(false),
  });
  // Migra formato antigo (entrada/saida/intervalo) para novo (4 marcações)
  const migrarDiaConfig = (raw: any): Record<string, DiaConfig> => {
    if (!raw) return diasConfigPadrao();
    const out: Record<string, DiaConfig> = {} as any;
    DIAS_KEYS.forEach(d => {
      const c = raw[d] || {};
      if (c.entrada && c.saida && !("inicio_almoco" in c)) {
        const intervalo = +(c.intervalo || 0);
        const [h1,m1] = c.entrada.split(":").map(Number);
        const [h2,m2] = c.saida.split(":").map(Number);
        const totalMin = (h2*60+m2) - (h1*60+m1);
        const meio = h1*60+m1 + Math.floor((totalMin - intervalo)/2);
        const ini = `${String(Math.floor(meio/60)).padStart(2,"0")}:${String(meio%60).padStart(2,"0")}`;
        const fimMin = meio + intervalo;
        const fim = `${String(Math.floor(fimMin/60)).padStart(2,"0")}:${String(fimMin%60).padStart(2,"0")}`;
        out[d] = {
          trabalha: !!c.trabalha,
          tem_almoco: intervalo > 0,
          entrada: c.entrada,
          inicio_almoco: intervalo > 0 ? ini : c.entrada,
          fim_almoco: intervalo > 0 ? fim : c.entrada,
          saida: c.saida,
        };
      } else {
        out[d] = {
          trabalha: !!c.trabalha,
          tem_almoco: c.tem_almoco !== false,
          entrada: c.entrada || "08:00",
          inicio_almoco: c.inicio_almoco || "12:00",
          fim_almoco: c.fim_almoco || "13:00",
          saida: c.saida || "17:00",
        };
      }
    });
    return out;
  };
  const minutosDia = (c: DiaConfig): number => {
    if (!c.trabalha) return 0;
    const toMin = (s: string) => { const [h,m]=s.split(":").map(Number); return h*60+m; };
    if (c.tem_almoco) {
      return Math.max(0, (toMin(c.inicio_almoco) - toMin(c.entrada)) + (toMin(c.saida) - toMin(c.fim_almoco)));
    }
    return Math.max(0, toMin(c.saida) - toMin(c.entrada));
  };
  const intervaloDia = (c: DiaConfig): number => {
    if (!c.trabalha || !c.tem_almoco) return 0;
    const toMin = (s: string) => { const [h,m]=s.split(":").map(Number); return h*60+m; };
    return Math.max(0, toMin(c.fim_almoco) - toMin(c.inicio_almoco));
  };
  const [escalaForm, setEscalaForm] = useState<any>({
    nome: "",
    tipo: "5x2",
    modalidade: "fixa",
    dias_config: diasConfigPadrao(),
    compensacoes_mensais: [] as Compensacao[],
    equalizacao_mensal_ativa: false,
    carga_semanal_contratada_min: 2640,
    ciclo_horas_trabalho: 12,
    ciclo_horas_descanso: 36,
    ciclo_inicio_data: new Date().toISOString().split("T")[0],
    ciclo_inicio_hora: "07:00",
    jornada_diaria_minutos: 480,
    jornada_semanal_minutos: 2640,
    intervalo_intrajornada_minutos: 60,
    tolerancia_minutos: 5,
    tolerancia_diaria_minutos: 10,
    hora_entrada_padrao: "08:00",
    hora_saida_padrao: "17:00",
    sabado_util: false,
    domingo_util: false,
    percentual_hora_extra_50: 50,
    percentual_hora_extra_100: 100,
    percentual_adicional_noturno: 20,
    usa_hora_ficta_noturna: true,
    comportamento_feriado: "folga" as "folga" | "trabalha",
  });

  // Cálculo automático de jornadas a partir da configuração
  const calcularJornadasFixa = (dc: Record<string, DiaConfig>) => {
    let semanal = 0;
    let diasTrab = 0;
    DIAS_KEYS.forEach(d => {
      const min = minutosDia(dc[d]);
      if (min > 0) { semanal += min; diasTrab++; }
    });
    return { semanal, diaria: diasTrab > 0 ? Math.round(semanal/diasTrab) : 0, diasTrab };
  };
  // Média semanal de horas extras vindas das compensações mensais (≈ 4.345 semanas/mês)
  const calcularCompensacaoSemanal = (lista: Compensacao[]) => {
    if (!lista?.length) return 0;
    const totalMes = lista.reduce((acc, c) => {
      const toMin = (s: string) => { const [h,m]=s.split(":").map(Number); return h*60+m; };
      const min = Math.max(0, toMin(c.saida) - toMin(c.entrada) - (c.intervalo || 0));
      // "ultimo" e "1..4" ocorrem 1x/mês cada
      return acc + min;
    }, 0);
    return Math.round(totalMes / 4.345);
  };
  const calcularJornadasMovel = (ht: number, hd: number) => {
    // jornada diária = horas trabalho do ciclo; semanal = média (7d / ciclo) * ht
    const ciclo = ht + hd;
    const semanalMin = ciclo > 0 ? Math.round((168 / ciclo) * ht * 60) : 0;
    return { diaria: ht * 60, semanal: semanalMin };
  };
  const queryClient = useQueryClient();

  // Formalização exigida por lei (ESC-001 / ESC-031): a regra vive no banco —
  // aqui só se pergunta o status de cada escala e se mostra o selo.
  const { data: statusFormalizacao = {} } = useQuery({
    queryKey: ["ponto-escala-formalizacao-mapa", escalas.map(e => e.id).join(",")],
    queryFn: async (): Promise<Record<string, string>> => {
      const mapa: Record<string, string> = {};
      await Promise.all(
        escalas.map(async (e) => {
          const { data, error } = await (supabase.rpc as any)("ponto_escala_formalizacao_status", {
            p_escala_id: e.id,
          });
          if (!error && data) mapa[e.id] = data as string;
        }),
      );
      return mapa;
    },
    enabled: escalas.length > 0,
  });

  const selo_formalizacao = (escalaId: string) => {
    const st = statusFormalizacao[escalaId];
    if (st === "pendente") {
      return (
        <Badge
          variant="destructive"
          title="Escala 12x36 sem acordo (CLT art. 59-A) ou revezamento acima de 6h sem instrumento coletivo (CF art. 7º, XIV). Anexe o acordo na escala ou cadastre o coletivo vigente em Compliance › Acordos."
        >
          Falta acordo
        </Badge>
      );
    }
    if (st === "regular") return <Badge variant="outline" className="border-emerald-400 text-emerald-700">Em ordem</Badge>;
    return <span className="text-xs text-muted-foreground">—</span>;
  };
  const [atribuicaoForm, setAtribuicaoForm] = useState<{
    escala_id: string;
    colaborador_ids: string[];
    data_inicio: string;
    substituir: boolean;
  }>({
    escala_id: "",
    colaborador_ids: [],
    data_inicio: new Date().toISOString().split("T")[0],
    substituir: false,
  });
  const [atribBusca, setAtribBusca] = useState("");
  const [atribuindoLote, setAtribuindoLote] = useState(false);

  const formatMinutos = (min: number) => formatarHoraMinuto(min);


  const handleSalvar = async () => {
    if (!escalaForm.nome) { toast.error("Nome obrigatório"); return; }
    let payload: any = { ...escalaForm };
    if (escalaForm.modalidade !== "movel") {
      const { diaria, semanal } = calcularJornadasFixa(escalaForm.dias_config);
      const compMin = calcularCompensacaoSemanal(escalaForm.compensacoes_mensais || []);
      payload.jornada_diaria_minutos = diaria;
      payload.jornada_semanal_minutos = semanal + compMin;
      payload.sabado_util = !!escalaForm.dias_config.sabado?.trabalha || (escalaForm.compensacoes_mensais || []).some((c: Compensacao) => c.dia_semana === "sabado");
      payload.domingo_util = !!escalaForm.dias_config.domingo?.trabalha || (escalaForm.compensacoes_mensais || []).some((c: Compensacao) => c.dia_semana === "domingo");
      payload.compensacoes_mensais = escalaForm.compensacoes_mensais || [];
      // Deriva tipo a partir dos dias trabalhados
      const diasTrab = DIAS_KEYS.filter(k => (escalaForm.dias_config[k] as DiaConfig)?.trabalha);
      const folgas = 7 - diasTrab.length;
      const isSeg = diasTrab.includes("segunda");
      const isSab = diasTrab.includes("sabado");
      const isDom = diasTrab.includes("domingo");
      if (diasTrab.length === 5 && isSeg && !isSab && !isDom) {
        payload.tipo = "5x2";
      } else if (diasTrab.length === 6 && isSeg && isSab && !isDom) {
        payload.tipo = "6x1";
      } else if (diasTrab.length > 0) {
        payload.tipo = "personalizada";
      }
      // Sincroniza resumo (Horário) a partir do primeiro dia trabalhado
      const primeiroDia = DIAS_KEYS.map(k => escalaForm.dias_config[k] as DiaConfig).find(d => d?.trabalha);
      if (primeiroDia) {
        payload.hora_entrada_padrao = primeiroDia.entrada || payload.hora_entrada_padrao;
        payload.hora_saida_padrao = primeiroDia.saida || payload.hora_saida_padrao;
      }

      // limpa campos ciclo
      payload.ciclo_horas_trabalho = null;
      payload.ciclo_horas_descanso = null;
      payload.ciclo_inicio_data = null;
      payload.ciclo_inicio_hora = null;
    } else {
      const { diaria, semanal } = calcularJornadasMovel(escalaForm.ciclo_horas_trabalho, escalaForm.ciclo_horas_descanso);
      payload.jornada_diaria_minutos = diaria;
      payload.jornada_semanal_minutos = semanal;
      payload.dias_config = null;
      payload.compensacoes_mensais = [];
      payload.tipo = "personalizada";
    }
    if (editando) {
      await atualizarEscala({ id: editando.id, ...payload } as any);
    } else {
      await criarEscala(payload as any);
    }
    setShowCriar(false);
    setEditando(null);
  };

  const abrirNova = () => {
    setEditando(null);
    setEscalaForm({
      nome: "", tipo: "5x2", modalidade: "fixa",
      dias_config: diasConfigPadrao(),
      compensacoes_mensais: [],
      ciclo_horas_trabalho: 12, ciclo_horas_descanso: 36,
      ciclo_inicio_data: new Date().toISOString().split("T")[0], ciclo_inicio_hora: "07:00",
      jornada_diaria_minutos: 480, jornada_semanal_minutos: 2640,
      intervalo_intrajornada_minutos: 60, tolerancia_minutos: 5, tolerancia_diaria_minutos: 10,
      hora_entrada_padrao: "08:00", hora_saida_padrao: "17:00", sabado_util: false, domingo_util: false,
      percentual_hora_extra_50: 50, percentual_hora_extra_100: 100, percentual_adicional_noturno: 20,
      usa_hora_ficta_noturna: true,
      comportamento_feriado: "folga",
    });
    setShowCriar(true);
  };

  const abrirEditar = (e: PontoEscala) => {
    setEditando(e);
    const anyE = e as any;
    setEscalaForm({
      nome: e.nome,
      tipo: e.tipo,
      modalidade: anyE.modalidade || "fixa",
      dias_config: migrarDiaConfig(anyE.dias_config),
      compensacoes_mensais: Array.isArray(anyE.compensacoes_mensais) ? anyE.compensacoes_mensais : [],
      equalizacao_mensal_ativa: !!anyE.equalizacao_mensal_ativa,
      carga_semanal_contratada_min: Number(anyE.carga_semanal_contratada_min) || 2640,
      ciclo_horas_trabalho: anyE.ciclo_horas_trabalho ?? 12,
      ciclo_horas_descanso: anyE.ciclo_horas_descanso ?? 36,
      ciclo_inicio_data: anyE.ciclo_inicio_data || new Date().toISOString().split("T")[0],
      ciclo_inicio_hora: (anyE.ciclo_inicio_hora || "07:00").substring(0,5),
      jornada_diaria_minutos: e.jornada_diaria_minutos,
      jornada_semanal_minutos: e.jornada_semanal_minutos,
      intervalo_intrajornada_minutos: e.intervalo_intrajornada_minutos,
      tolerancia_minutos: e.tolerancia_minutos,
      tolerancia_diaria_minutos: e.tolerancia_diaria_minutos,
      hora_entrada_padrao: e.hora_entrada_padrao?.substring(0,5) || "08:00",
      hora_saida_padrao: e.hora_saida_padrao?.substring(0,5) || "17:00",
      sabado_util: e.sabado_util,
      domingo_util: e.domingo_util,
      percentual_hora_extra_50: e.percentual_hora_extra_50,
      percentual_hora_extra_100: e.percentual_hora_extra_100,
      percentual_adicional_noturno: e.percentual_adicional_noturno,
      usa_hora_ficta_noturna: e.usa_hora_ficta_noturna,
      comportamento_feriado: (anyE.comportamento_feriado === "trabalha" ? "trabalha" : "folga"),
    });
    setShowCriar(true);
  };

  const handleToggleAtiva = async (e: PontoEscala) => {
    const ok = await confirm({
      title: e.ativa ? "Inativar escala?" : "Ativar escala?",
      description: e.ativa
        ? "A escala não poderá ser atribuída a novos colaboradores enquanto inativa."
        : "A escala voltará a ficar disponível para atribuição.",
      confirmLabel: e.ativa ? "Inativar" : "Ativar",
      variant: e.ativa ? "destructive" : "default",
    });
    if (!ok) return;
    await atualizarEscala({ id: e.id, ativa: !e.ativa } as any);
  };

  const handleExcluir = async (e: PontoEscala) => {
    const ok = await confirm({
      title: "Excluir escala?",
      description: `A escala "${e.nome}" será removida permanentemente. Esta ação não pode ser desfeita. (Só é possível excluir escalas sem colaboradores atribuídos.)`,
      confirmLabel: "Excluir",
      variant: "destructive",
    });
    if (!ok) return;
    await excluirEscala(e.id);
  };

  // Mapa colaborador_id → atribuição ativa atual (para detectar duplicidade)
  const atribuicoesPorColaborador = useMemo(() => {
    const map = new Map<string, typeof atribuicoes[number]>();
    atribuicoes.forEach(a => { if (a.colaborador_id) map.set(a.colaborador_id, a); });
    return map;
  }, [atribuicoes]);

  // Edição de uma atribuição existente: troca a escala do colaborador.
  // Não sobrescreve o registro atual — encerra ele com data_fim e cria a
  // nova atribuição. Preserva o histórico, que é o que o ponto exige (a
  // escala vigente em cada período precisa continuar auditável).
  const [editAtribuicao, setEditAtribuicao] = useState<null | {
    id: string;
    colaborador_id: string;
    colaborador_nome: string;
    colaborador_cpf: string;
    escala_id: string;
    escala_id_nova: string;
    data_inicio: string;
  }>(null);
  const [salvandoEdicao, setSalvandoEdicao] = useState(false);

  // Formata YYYY-MM-DD como dd/mm/aaaa. Monta a data pelos componentes em vez
  // de new Date(str): a string ISO sem hora é interpretada como UTC, e no
  // fuso do Brasil isso exibiria o dia anterior.
  const formatarData = (iso: string) => {
    if (!iso) return "-";
    const [a, m, d] = iso.split("T")[0].split("-");
    return `${d}/${m}/${a}`;
  };

  // Histórico de escalas do colaborador. Buscado sob demanda (ao abrir), e
  // não junto da lista principal, porque a query de atribuições carrega só as
  // ativas — o histórico inclui as encerradas (ativa=false).
  const [historico, setHistorico] = useState<null | {
    colaborador_nome: string;
    itens: Array<{
      id: string;
      escala_id: string;
      data_inicio: string;
      data_fim: string | null;
      ativa: boolean;
    }>;
  }>(null);
  const [carregandoHistorico, setCarregandoHistorico] = useState(false);

  const abrirHistorico = async (colaboradorId: string, colaboradorNome: string) => {
    setCarregandoHistorico(true);
    setHistorico({ colaborador_nome: colaboradorNome, itens: [] });
    try {
      const { data, error } = await fromTable("ponto_escala_atribuicoes")
        .select("id, escala_id, data_inicio, data_fim, ativa")
        .eq("colaborador_id", colaboradorId)
        .order("data_inicio", { ascending: false });
      if (error) throw error;
      setHistorico({ colaborador_nome: colaboradorNome, itens: (data || []) as any });
    } catch (e: any) {
      toast.error(e?.message || "Erro ao carregar o histórico");
      setHistorico(null);
    } finally {
      setCarregandoHistorico(false);
    }
  };

  const handleSalvarEdicaoAtribuicao = async () => {
    if (!editAtribuicao) return;
    if (!editAtribuicao.escala_id_nova) { toast.error("Selecione a escala"); return; }
    if (editAtribuicao.escala_id_nova === editAtribuicao.escala_id) {
      toast.info("A escala selecionada é a mesma da atribuição atual.");
      return;
    }
    setSalvandoEdicao(true);
    try {
      // Encerra a atribuição vigente na data de início da nova
      await fromTable("ponto_escala_atribuicoes")
        .update({ ativa: false, data_fim: editAtribuicao.data_inicio } as any)
        .eq("id", editAtribuicao.id);

      await atribuirEscala({
        escala_id: editAtribuicao.escala_id_nova,
        colaborador_id: editAtribuicao.colaborador_id,
        colaborador_nome: editAtribuicao.colaborador_nome,
        colaborador_cpf: editAtribuicao.colaborador_cpf,
        data_inicio: editAtribuicao.data_inicio,
      });

      queryClient.invalidateQueries({ queryKey: ["ponto-escala-atribuicoes"] });
      toast.success("Escala do colaborador atualizada!");
      setEditAtribuicao(null);
    } catch (e: any) {
      toast.error(e?.message || "Erro ao atualizar a escala");
    } finally {
      setSalvandoEdicao(false);
    }
  };

  const handleAtribuirLote = async () => {
    if (!atribuicaoForm.escala_id) { toast.error("Selecione uma escala"); return; }
    if (atribuicaoForm.colaborador_ids.length === 0) { toast.error("Selecione ao menos um colaborador"); return; }
    setAtribuindoLote(true);
    let sucesso = 0, pulados = 0, substituidos = 0;
    try {
      for (const colabId of atribuicaoForm.colaborador_ids) {
        const colab = colaboradores.find(c => c.id === colabId);
        if (!colab) continue;
        const atual = atribuicoesPorColaborador.get(colabId);
        if (atual) {
          if (atual.escala_id === atribuicaoForm.escala_id) { pulados++; continue; }
          if (!atribuicaoForm.substituir) { pulados++; continue; }
          // Inativa atribuição anterior
          await fromTable("ponto_escala_atribuicoes")
            .update({ ativa: false, data_fim: atribuicaoForm.data_inicio } as any)
            .eq("id", atual.id);
          substituidos++;
        }
        await atribuirEscala({
          escala_id: atribuicaoForm.escala_id,
          colaborador_id: colab.id,
          colaborador_nome: colab.nome_completo,
          colaborador_cpf: colab.cpf,
          data_inicio: atribuicaoForm.data_inicio,
        });
        sucesso++;
      }
      queryClient.invalidateQueries({ queryKey: ["ponto-escala-atribuicoes"] });
      const partes = [
        sucesso > 0 ? `${sucesso} atribuída(s)` : null,
        substituidos > 0 ? `${substituidos} substituída(s)` : null,
        pulados > 0 ? `${pulados} ignorada(s) (já em outra escala)` : null,
      ].filter(Boolean).join(" · ");
      toast.success(partes || "Nenhuma alteração");
      setShowAtribuir(false);
      setAtribuicaoForm(f => ({ ...f, colaborador_ids: [], substituir: false }));
    } finally {
      setAtribuindoLote(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <Calendar className="w-5 h-5 text-primary" /> Escalas & Turnos
          </h3>
          <p className="text-sm text-muted-foreground">Gerencie escalas de trabalho e atribua a colaboradores</p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button onClick={abrirNova} className="bg-gradient-to-r from-orange-500 to-orange-600 text-white hover:opacity-90">
            <Plus className="w-4 h-4 mr-2" /> Criar Escala
          </Button>
          <Button variant="outline" onClick={() => setShowAtribuir(true)}>
            <Users className="w-4 h-4 mr-2" /> Atribuir Escala
          </Button>
          <Button onClick={() => setShowInteligente(true)} variant="outline" className="border-primary/40 text-primary">
            <Sparkles className="w-4 h-4 mr-2" /> Cadastro Inteligente
          </Button>
        </div>
      </div>

      {/* Avisos: escala sem o acordo exigido e turnos a descoberto */}
      <PontoEscalaAvisos escalas={escalas as any} />

      {/* Escalas Table */}
      <Card>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nome</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Jornada Diária</TableHead>
                <TableHead>Jornada Semanal</TableHead>
                <TableHead>Intervalo</TableHead>
                <TableHead>Tolerância</TableHead>
                <TableHead>Horário</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-center">Formalização</TableHead>
                <TableHead className="text-right">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingEscalas ? (
                <TableRow><TableCell colSpan={10} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : escalas.length === 0 ? (
                <TableRow><TableCell colSpan={10} className="text-center py-8 text-muted-foreground">Nenhuma escala cadastrada.</TableCell></TableRow>
              ) : escalas.map(e => {
                const emUso = atribuicoes.some(a => a.escala_id === e.id);
                return (
                <TableRow key={e.id}>
                  <TableCell className="font-medium">{e.nome}</TableCell>
                  <TableCell><Badge variant="outline">{ESCALA_TIPOS.find(t => t.value === e.tipo)?.label || e.tipo}</Badge></TableCell>
                  <TableCell>{formatMinutos(e.jornada_diaria_minutos)}</TableCell>
                  <TableCell>{formatMinutos(e.jornada_semanal_minutos)}</TableCell>
                  <TableCell>{formatMinutos(e.intervalo_intrajornada_minutos)}</TableCell>
                  <TableCell>{e.tolerancia_minutos}min / {e.tolerancia_diaria_minutos}min</TableCell>
                  <TableCell className="font-mono text-sm">{e.hora_entrada_padrao?.substring(0,5)} - {e.hora_saida_padrao?.substring(0,5)}</TableCell>
                  <TableCell><Badge className={e.ativa ? "bg-green-100 text-green-800" : "bg-gray-100 text-gray-800"}>{e.ativa ? "Ativa" : "Inativa"}</Badge></TableCell>
                  <TableCell className="text-center">{selo_formalizacao(e.id)}</TableCell>
                  <TableCell>
                    <div className="flex items-center justify-end gap-1">
                      <Button size="icon" variant="ghost" title="Editar" onClick={() => abrirEditar(e)}>
                        <Pencil className="w-4 h-4" />
                      </Button>
                      <Button size="icon" variant="ghost" title={e.ativa ? "Inativar" : "Ativar"} onClick={() => handleToggleAtiva(e)}>
                        <Power className={`w-4 h-4 ${e.ativa ? "text-amber-600" : "text-emerald-600"}`} />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        title={emUso ? "Não é possível excluir: escala em uso" : "Excluir"}
                        disabled={emUso}
                        onClick={() => handleExcluir(e)}
                      >
                        <Trash2 className="w-4 h-4 text-destructive" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Atribuições */}
      {atribuicoes.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-base">Atribuições Ativas</CardTitle></CardHeader>
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Colaborador</TableHead>
                  <TableHead>Escala</TableHead>
                  <TableHead>Início</TableHead>
                  <TableHead className="w-[80px] text-right">Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {atribuicoes.map(a => (
                  <TableRow key={a.id}>
                    <TableCell>{a.colaborador_nome}</TableCell>
                    <TableCell>{escalas.find(e => e.id === a.escala_id)?.nome || "-"}</TableCell>
                    <TableCell>{a.data_inicio}</TableCell>
                    <TableCell className="text-right">
                      <Button
                        size="icon"
                        variant="ghost"
                        title="Editar escala do colaborador"
                        onClick={() => setEditAtribuicao({
                          id: a.id,
                          colaborador_id: a.colaborador_id,
                          colaborador_nome: a.colaborador_nome,
                          colaborador_cpf: (a as any).colaborador_cpf || "",
                          escala_id: a.escala_id,
                          escala_id_nova: a.escala_id,
                          data_inicio: new Date().toISOString().split("T")[0],
                        })}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      {/* Dialog Criar Escala */}
      <Dialog open={showCriar} onOpenChange={(o) => { setShowCriar(o); if (!o) setEditando(null); }}>
        <DialogContent className="max-w-4xl max-h-[85vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{editando ? "Editar Escala" : "Nova Escala de Trabalho"}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label>Nome da Escala</Label>
                <Input value={escalaForm.nome} onChange={e => setEscalaForm({ ...escalaForm, nome: e.target.value })} placeholder="Ex: Administrativo" />
              </div>
              <div className="space-y-2">
                <Label>Modalidade</Label>
                <Select
                  value={escalaForm.modalidade}
                  onValueChange={v => setEscalaForm({ ...escalaForm, modalidade: v, tipo: v === "movel" ? "12x36" : "5x2" })}
                >
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="fixa">Fixa (dias da semana definidos)</SelectItem>
                    <SelectItem value="movel">Móvel (12x36, 24x72, etc.)</SelectItem>
                    <SelectItem value="revezamento">Turno ininterrupto de revezamento</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            {/* CF art. 7º, XIV: revezamento tem jornada de 6h; ampliar exige
                instrumento COLETIVO (acordo individual não serve). */}
            {escalaForm.modalidade === "revezamento" && (
              <div className="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
                <p>
                  Turno ininterrupto de revezamento tem jornada de <strong>6 horas</strong> pela
                  Constituição (art. 7º, XIV). Acima disso, só com <strong>acordo coletivo ou
                  convenção</strong> — acordo individual não autoriza. Se passar de 6h sem o
                  instrumento coletivo, a escala aparece como "Falta acordo" na lista.
                </p>
              </div>
            )}

            {escalaForm.modalidade !== "movel" ? (
              <>
              <div className="rounded-lg border p-3 space-y-2 bg-muted/20">
                <div className="flex items-center justify-between flex-wrap gap-2">
                  <Label className="text-sm font-semibold flex items-center gap-2"><CalendarDays className="w-4 h-4 text-primary" /> Dias da semana — 4 marcações</Label>
                  <div className="flex gap-1.5 flex-wrap">
                    <Button type="button" size="sm" variant="outline" className="h-7 text-[11px]"
                      onClick={() => {
                        const seg = escalaForm.dias_config.segunda as DiaConfig;
                        const nova = { ...escalaForm.dias_config };
                        ["terca","quarta","quinta","sexta"].forEach(k => { nova[k] = { ...seg }; });
                        nova.sabado = { ...(nova.sabado as DiaConfig), trabalha: false };
                        nova.domingo = { ...(nova.domingo as DiaConfig), trabalha: false };
                        setEscalaForm({ ...escalaForm, dias_config: nova });
                      }}>
                      <Copy className="w-3 h-3 mr-1" /> Seg→Sex iguais
                    </Button>
                    <Button type="button" size="sm" variant="outline" className="h-7 text-[11px]"
                      onClick={() => {
                        const seg = escalaForm.dias_config.segunda as DiaConfig;
                        const nova = { ...escalaForm.dias_config };
                        ["terca","quarta","quinta","sexta","sabado"].forEach(k => { nova[k] = { ...seg }; });
                        nova.domingo = { ...(nova.domingo as DiaConfig), trabalha: false };
                        setEscalaForm({ ...escalaForm, dias_config: nova });
                      }}>
                      <Copy className="w-3 h-3 mr-1" /> Seg→Sáb iguais
                    </Button>
                  </div>
                </div>
                <div className="grid grid-cols-[80px_50px_55px_1fr_1fr_1fr_1fr_70px_36px] gap-1.5 text-[10px] font-medium text-muted-foreground px-1 uppercase tracking-wide">
                  <span>Dia</span>
                  <span className="text-center">Trab.</span>
                  <span className="text-center">Almoço</span>
                  <span>Entrada</span>
                  <span>Início almoço</span>
                  <span>Fim almoço</span>
                  <span>Saída</span>
                  <span className="text-right">Total</span>
                  <span></span>
                </div>
                {DIAS_KEYS.map(d => {
                  const c = escalaForm.dias_config[d] as DiaConfig;
                  const upd = (patch: Partial<DiaConfig>) => setEscalaForm({
                    ...escalaForm,
                    dias_config: { ...escalaForm.dias_config, [d]: { ...c, ...patch } },
                  });
                  const replicarParaTrab = () => {
                    const nova = { ...escalaForm.dias_config };
                    DIAS_KEYS.forEach(k => {
                      if (k !== d && (nova[k] as DiaConfig).trabalha) {
                        nova[k] = { ...c };
                      }
                    });
                    setEscalaForm({ ...escalaForm, dias_config: nova });
                    toast.success(`Horário de ${DIAS_LBL[d]} replicado nos demais dias trabalhados.`);
                  };
                  const min = minutosDia(c);
                  const intMin = intervaloDia(c);
                  return (
                    <div key={d} className="grid grid-cols-[80px_50px_55px_1fr_1fr_1fr_1fr_70px_36px] gap-1.5 items-center">
                      <span className="text-sm font-medium">{DIAS_LBL[d]}</span>
                      <div className="flex justify-center"><Switch checked={c.trabalha} onCheckedChange={v => upd({ trabalha: v })} /></div>
                      <div className="flex justify-center"><Switch checked={c.tem_almoco} disabled={!c.trabalha} onCheckedChange={v => upd({ tem_almoco: v })} /></div>
                      <Input type="time" disabled={!c.trabalha} value={c.entrada} onChange={e => upd({ entrada: e.target.value })} className="h-8 text-xs px-1.5" />
                      <Input type="time" disabled={!c.trabalha || !c.tem_almoco} value={c.inicio_almoco} onChange={e => upd({ inicio_almoco: e.target.value })} className="h-8 text-xs px-1.5" />
                      <Input type="time" disabled={!c.trabalha || !c.tem_almoco} value={c.fim_almoco} onChange={e => upd({ fim_almoco: e.target.value })} className="h-8 text-xs px-1.5" />
                      <Input type="time" disabled={!c.trabalha} value={c.saida} onChange={e => upd({ saida: e.target.value })} className="h-8 text-xs px-1.5" />
                      <span className="text-right text-xs font-mono text-muted-foreground">
                        {c.trabalha ? `${Math.floor(min/60)}h${min%60?String(min%60).padStart(2,"0"):""}` : "—"}
                        {c.trabalha && c.tem_almoco && <span className="block text-[9px] opacity-70">int {intMin}min</span>}
                      </span>
                      <Button type="button" size="icon" variant="ghost" className="h-7 w-7" disabled={!c.trabalha} title="Replicar este horário para os demais dias trabalhados" onClick={replicarParaTrab}>
                        <Copy className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  );
                })}

                {/* Contador de carga semanal */}
                {(() => {
                  const j = calcularJornadasFixa(escalaForm.dias_config);
                  const compMin = calcularCompensacaoSemanal(escalaForm.compensacoes_mensais || []);
                  const total = j.semanal + compMin;
                  const fmt = (m: number) => `${Math.floor(m/60)}h${m%60?` ${String(m%60).padStart(2,"0")}min`:""}`;
                  const meta44 = 44 * 60;
                  const meta40 = 40 * 60;
                  const pct = Math.min(100, Math.round((total / meta44) * 100));
                  let cor = "bg-emerald-500";
                  let alerta = "";
                  if (total < meta40) { cor = "bg-amber-500"; alerta = `Faltam ${fmt(meta40 - total)} para 40h ou ${fmt(meta44 - total)} para 44h. Considere usar Compensações Mensais.`; }
                  else if (total < meta44) { cor = "bg-blue-500"; alerta = `${fmt(meta44 - total)} abaixo do limite de 44h/sem (CLT). Compensação opcional.`; }
                  else if (total === meta44) { cor = "bg-emerald-500"; alerta = "Carga semanal exatamente no limite CLT (44h)."; }
                  else { cor = "bg-red-500"; alerta = `Excede ${fmt(total - meta44)} sobre o limite CLT de 44h/sem. Revise a escala.`; }
                  // Mensal: semana × 4.345 (média de semanas/mês). Padrão CLT folha = 220h
                  const mensalMin = Math.round(total * 4.345);
                  const mensalCLT = 220 * 60;
                  return (
                    <div className="mt-3 rounded-md border bg-background p-3 space-y-2">
                      <div className="flex items-baseline justify-between gap-2 flex-wrap">
                        <div className="flex items-baseline gap-2 flex-wrap">
                          <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Carga calculada</span>
                          <span className="text-2xl font-bold text-primary tabular-nums">{fmt(total)}</span>
                          <span className="text-xs text-muted-foreground">/ semana</span>
                          <span className="text-muted-foreground">·</span>
                          <span className="text-2xl font-bold text-primary tabular-nums">{fmt(mensalMin)}</span>
                          <span className="text-xs text-muted-foreground">/ mês (≈ × 4,345)</span>
                        </div>
                        <div className="text-[11px] text-muted-foreground text-right">
                          {compMin > 0 ? <>Base {fmt(j.semanal)} + Comp {fmt(compMin)}/sem</> : <>Sem compensações</>}
                          <div>Meta CLT: 44h/sem • 220h/mês</div>
                        </div>
                      </div>
                      <div className="h-2 w-full rounded-full bg-muted overflow-hidden">
                        <div className={`h-full ${cor} transition-all`} style={{ width: `${pct}%` }} />
                      </div>
                      <div className="flex items-center justify-between text-[11px] text-muted-foreground">
                        <span>{alerta}</span>
                        <span className="tabular-nums">
                          {mensalMin < mensalCLT
                            ? `${fmt(mensalCLT - mensalMin)} abaixo de 220h/mês`
                            : mensalMin === mensalCLT
                              ? "Exatamente 220h/mês"
                              : `${fmt(mensalMin - mensalCLT)} acima de 220h/mês`}
                        </span>
                      </div>
                    </div>
                  );
                })()}
              </div>

              {/* Equalização mensal com sábado variável (novo modelo) */}
              <div className="rounded-lg border p-3 space-y-3 bg-amber-50/40 dark:bg-amber-950/10">
                <div className="flex items-center justify-between gap-2">
                  <Label className="text-sm font-semibold flex items-center gap-2">
                    <Repeat className="w-4 h-4 text-amber-600" /> Equalização mensal (sábado variável)
                  </Label>
                  <Switch
                    checked={!!escalaForm.equalizacao_mensal_ativa}
                    onCheckedChange={(v) => {
                      // RN09: só permite ativar quando há déficit real a equalizar.
                      // Se a carga real da escala já cobre (ou excede) a contratada,
                      // ligar geraria débito indevido / crédito duplicado — bloqueia.
                      const real = calcularJornadasFixa(escalaForm.dias_config).semanal;
                      const contratada = Number(escalaForm.carga_semanal_contratada_min) || 2640;
                      if (v && real >= contratada) {
                        toast.error(
                          `Sem déficit a equalizar: a carga real (${Math.floor(real/60)}h${String(real%60).padStart(2,"0")}) já atinge a contratada. Ajuste a carga contratada ou a escala antes de ativar.`
                        );
                        return;
                      }
                      setEscalaForm({ ...escalaForm, equalizacao_mensal_ativa: v });
                    }}
                  />
                </div>
                <p className="text-[11px] text-muted-foreground">
                  Ligue apenas para escalas que fecham a carga contratada trabalhando um sábado por mês.
                  O sistema calcula sozinho quantas horas de equalização o mês exige e reconhece qualquer
                  sábado trabalhado como o dia de compensação.
                </p>
                {escalaForm.equalizacao_mensal_ativa && (() => {
                  const real = calcularJornadasFixa(escalaForm.dias_config).semanal;
                  const contratada = Number(escalaForm.carga_semanal_contratada_min) || 2640;
                  const deficit = Math.max(0, contratada - real);
                  const fmt = (m: number) => `${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}`;
                  return (
                    <div className="space-y-2 border-t pt-2">
                      <div className="flex items-center gap-2 flex-wrap">
                        <Label className="text-xs">Carga semanal contratada</Label>
                        <select
                          className="h-8 rounded-md border bg-background px-2 text-sm"
                          value={contratada}
                          onChange={(e) => setEscalaForm({ ...escalaForm, carga_semanal_contratada_min: Number(e.target.value) })}
                        >
                          <option value={2640}>44h (padrão)</option>
                          <option value={2400}>40h</option>
                          <option value={2160}>36h</option>
                          <option value={1200}>20h</option>
                        </select>
                        <span className="text-[11px] text-muted-foreground">
                          Carga real da escala (seg–sex): <strong>{fmt(real)}</strong>
                        </span>
                      </div>
                      {deficit === 0 ? (
                        <p className="text-[11px] text-green-700">
                          A escala já cumpre a carga contratada — nenhuma equalização será gerada.
                        </p>
                      ) : (
                        <p className="text-[11px] text-amber-700">
                          Déficit de <strong>{fmt(deficit)}/semana</strong> ({fmt(Math.round(deficit / 5))}/dia) será
                          equalizado no sábado trabalhado de cada mês.
                        </p>
                      )}
                    </div>
                  );
                })()}
              </div>

              {/* Compensações Mensais — equalização da carga semanal */}
              <div className="rounded-lg border p-3 space-y-2 bg-amber-50/40 dark:bg-amber-950/10">
                <div className="flex items-center justify-between">
                  <Label className="text-sm font-semibold flex items-center gap-2">
                    <Repeat className="w-4 h-4 text-amber-600" /> Compensações Mensais (equalização)
                  </Label>
                  <Button
                    type="button" size="sm" variant="outline"
                    onClick={() => setEscalaForm({
                      ...escalaForm,
                      compensacoes_mensais: [
                        ...(escalaForm.compensacoes_mensais || []),
                        { ordinal_mes: "1", dia_semana: "sabado", entrada: "08:00", saida: "12:00", intervalo: 0, descricao: "" } as Compensacao,
                      ],
                    })}
                  >
                    <Plus className="w-3.5 h-3.5 mr-1" /> Adicionar
                  </Button>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  Modelo antigo (posição fixa, ex.: "3º sábado"). Prefira a <strong>Equalização mensal</strong> acima,
                  que reconhece qualquer sábado trabalhado. Mantido apenas para escalas já configuradas.
                </p>
                {(escalaForm.compensacoes_mensais || []).length === 0 ? (
                  <p className="text-xs text-muted-foreground italic py-2 text-center">Nenhuma compensação configurada.</p>
                ) : (
                  <div className="space-y-2">
                    {(escalaForm.compensacoes_mensais as Compensacao[]).map((comp, idx) => {
                      const updComp = (patch: Partial<Compensacao>) => {
                        const arr = [...escalaForm.compensacoes_mensais];
                        arr[idx] = { ...arr[idx], ...patch };
                        setEscalaForm({ ...escalaForm, compensacoes_mensais: arr });
                      };
                      const remComp = () => {
                        const arr = escalaForm.compensacoes_mensais.filter((_: any, i: number) => i !== idx);
                        setEscalaForm({ ...escalaForm, compensacoes_mensais: arr });
                      };
                      return (
                        <div key={idx} className="grid grid-cols-[90px_110px_1fr_1fr_70px_1fr_36px] gap-1.5 items-center">
                          <Select value={comp.ordinal_mes} onValueChange={v => updComp({ ordinal_mes: v })}>
                            <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {ORDINAIS_MES.map(o => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                            </SelectContent>
                          </Select>
                          <Select value={comp.dia_semana} onValueChange={v => updComp({ dia_semana: v })}>
                            <SelectTrigger className="h-8 text-xs"><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {DIAS_KEYS.map(d => <SelectItem key={d} value={d}>{DIAS_LBL[d]}</SelectItem>)}
                            </SelectContent>
                          </Select>
                          <Input type="time" value={comp.entrada} onChange={e => updComp({ entrada: e.target.value })} className="h-8 text-xs px-1.5" />
                          <Input type="time" value={comp.saida} onChange={e => updComp({ saida: e.target.value })} className="h-8 text-xs px-1.5" />
                          <Input type="number" value={comp.intervalo} onChange={e => updComp({ intervalo: +e.target.value })} className="h-8 text-xs px-1.5" placeholder="int" />
                          <Input value={comp.descricao || ""} onChange={e => updComp({ descricao: e.target.value })} className="h-8 text-xs px-1.5" placeholder="Descrição" />
                          <Button type="button" size="icon" variant="ghost" onClick={remComp} className="h-8 w-8">
                            <Trash2 className="w-3.5 h-3.5 text-destructive" />
                          </Button>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
              </>
            ) : (
              <div className="rounded-lg border p-4 space-y-3 bg-muted/20">
                <Label className="text-sm font-semibold flex items-center gap-2"><Repeat className="w-4 h-4 text-primary" /> Configuração do ciclo</Label>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Horas trabalhadas</Label>
                    <Input type="number" value={escalaForm.ciclo_horas_trabalho} onChange={e => setEscalaForm({ ...escalaForm, ciclo_horas_trabalho: +e.target.value })} />
                  </div>
                  <div className="space-y-2">
                    <Label>Horas de descanso</Label>
                    <Input type="number" value={escalaForm.ciclo_horas_descanso} onChange={e => setEscalaForm({ ...escalaForm, ciclo_horas_descanso: +e.target.value })} />
                  </div>
                  <div className="space-y-2">
                    <Label>Data de referência (1º turno)</Label>
                    <Input type="date" value={escalaForm.ciclo_inicio_data} onChange={e => setEscalaForm({ ...escalaForm, ciclo_inicio_data: e.target.value })} />
                  </div>
                  <div className="space-y-2">
                    <Label>Hora de início do turno</Label>
                    <Input type="time" value={escalaForm.ciclo_inicio_hora} onChange={e => setEscalaForm({ ...escalaForm, ciclo_inicio_hora: e.target.value })} />
                  </div>
                </div>
                <p className="text-xs text-muted-foreground">
                  Ex: 12x36 = 12h trabalho / 36h descanso. O sistema usa a data e hora de referência para calcular automaticamente os dias de plantão de cada colaborador.
                  {(() => { const j = calcularJornadasMovel(escalaForm.ciclo_horas_trabalho, escalaForm.ciclo_horas_descanso); return ` Jornada equivalente: ${Math.round(j.semanal/60)}h/semana.`; })()}
                </p>
              </div>
            )}

            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>Intervalo (min)</Label>
                <Input type="number" value={escalaForm.intervalo_intrajornada_minutos} onChange={e => setEscalaForm({ ...escalaForm, intervalo_intrajornada_minutos: +e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>Tolerância marcação (min)</Label>
                <Input type="number" value={escalaForm.tolerancia_minutos} onChange={e => setEscalaForm({ ...escalaForm, tolerancia_minutos: +e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>Tolerância diária (min)</Label>
                <Input type="number" value={escalaForm.tolerancia_diaria_minutos} onChange={e => setEscalaForm({ ...escalaForm, tolerancia_diaria_minutos: +e.target.value })} />
              </div>
            </div>

            <div className="grid grid-cols-3 gap-4">
              <div className="space-y-2">
                <Label>% HE 50%</Label>
                <Input type="number" value={escalaForm.percentual_hora_extra_50} onChange={e => setEscalaForm({ ...escalaForm, percentual_hora_extra_50: +e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>% HE 100%</Label>
                <Input type="number" value={escalaForm.percentual_hora_extra_100} onChange={e => setEscalaForm({ ...escalaForm, percentual_hora_extra_100: +e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>% Adic. Noturno</Label>
                <Input type="number" value={escalaForm.percentual_adicional_noturno} onChange={e => setEscalaForm({ ...escalaForm, percentual_adicional_noturno: +e.target.value })} />
              </div>
            </div>

            <div className="flex items-center gap-2 rounded-md border bg-muted/30 px-4 py-3">
              <Switch checked={escalaForm.usa_hora_ficta_noturna} onCheckedChange={v => setEscalaForm({ ...escalaForm, usa_hora_ficta_noturna: v })} />
              <Label className="cursor-pointer">Hora ficta noturna (52m30s)</Label>
            </div>

            <div className="space-y-2 rounded-md border bg-muted/30 px-4 py-3">
              <Label>Comportamento em feriado</Label>
              <Select
                value={escalaForm.comportamento_feriado}
                onValueChange={(v) => setEscalaForm({ ...escalaForm, comportamento_feriado: v as "folga" | "trabalha" })}
              >
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="folga">Folga (não trabalha no feriado)</SelectItem>
                  <SelectItem value="trabalha">Trabalha no feriado</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Define se quem está nesta escala folga ou trabalha nos feriados. Exceções individuais podem ser configuradas na tela de Feriados.
              </p>
            </div>

            {editando && <DetalhesEscalaPanel escalaId={editando.id} />}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setShowCriar(false); setEditando(null); }}>Cancelar</Button>
            <Button onClick={handleSalvar} disabled={criandoEscala || atualizandoEscala}>
              {(criandoEscala || atualizandoEscala) ? "Salvando..." : (editando ? "Salvar Alterações" : "Criar Escala")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog Atribuir (multi-seleção) */}
      <Dialog open={showAtribuir} onOpenChange={(o) => { setShowAtribuir(o); if (!o) setAtribBusca(""); }}>
        <DialogContent className="max-w-2xl max-h-[85vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle>Atribuir Escala a Colaboradores</DialogTitle>
            <p className="text-xs text-muted-foreground">Selecione vários colaboradores. Cada pessoa pode estar ativa em apenas <strong>uma escala</strong> por vez.</p>
          </DialogHeader>
          <div className="space-y-4 overflow-y-auto flex-1 pr-1">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label>Escala</Label>
                <Select value={atribuicaoForm.escala_id} onValueChange={v => setAtribuicaoForm({ ...atribuicaoForm, escala_id: v })}>
                  <SelectTrigger><SelectValue placeholder="Selecione a escala" /></SelectTrigger>
                  <SelectContent>
                    {escalas.filter(e => e.ativa).map(e => <SelectItem key={e.id} value={e.id}>{e.nome}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Data Início</Label>
                <Input type="date" value={atribuicaoForm.data_inicio} onChange={e => setAtribuicaoForm({ ...atribuicaoForm, data_inicio: e.target.value })} />
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label>Colaboradores ({atribuicaoForm.colaborador_ids.length} selecionados)</Label>
                <div className="flex gap-1.5">
                  {(() => {
                    const filtrados = colaboradores.filter(c => c.nome_completo.toLowerCase().includes(atribBusca.toLowerCase()));
                    const elegiveis = filtrados.filter(c => {
                      const at = atribuicoesPorColaborador.get(c.id);
                      return atribuicaoForm.substituir || !at || at.escala_id === atribuicaoForm.escala_id;
                    });
                    const todosSel = elegiveis.length > 0 && elegiveis.every(c => atribuicaoForm.colaborador_ids.includes(c.id));
                    return (
                      <Button type="button" size="sm" variant="outline" className="h-7 text-[11px]"
                        onClick={() => setAtribuicaoForm(f => ({
                          ...f,
                          colaborador_ids: todosSel
                            ? f.colaborador_ids.filter(id => !elegiveis.some(c => c.id === id))
                            : Array.from(new Set([...f.colaborador_ids, ...elegiveis.map(c => c.id)])),
                        }))}>
                        {todosSel ? "Limpar visíveis" : "Selecionar visíveis"}
                      </Button>
                    );
                  })()}
                </div>
              </div>
              <div className="relative">
                <Search className="w-3.5 h-3.5 absolute left-2.5 top-2.5 text-muted-foreground" />
                <Input className="pl-8 h-9" placeholder="Buscar colaborador…" value={atribBusca} onChange={e => setAtribBusca(e.target.value)} />
              </div>

              <div className="rounded-lg border max-h-72 overflow-y-auto divide-y">
                {colaboradores
                  .filter(c => c.nome_completo.toLowerCase().includes(atribBusca.toLowerCase()))
                  .map(c => {
                    const atual = atribuicoesPorColaborador.get(c.id);
                    const escalaAtual = atual ? escalas.find(e => e.id === atual.escala_id) : null;
                    const jaNessa = atual && atual.escala_id === atribuicaoForm.escala_id;
                    const bloqueado = !!atual && !jaNessa && !atribuicaoForm.substituir;
                    const checked = atribuicaoForm.colaborador_ids.includes(c.id);
                    return (
                      <label
                        key={c.id}
                        className={`flex items-center gap-3 px-3 py-2 ${bloqueado ? "opacity-50 cursor-not-allowed" : "cursor-pointer hover:bg-muted/50"}`}
                      >
                        <Checkbox
                          checked={checked}
                          disabled={bloqueado || jaNessa}
                          onCheckedChange={(v) => {
                            setAtribuicaoForm(f => ({
                              ...f,
                              colaborador_ids: v
                                ? [...f.colaborador_ids, c.id]
                                : f.colaborador_ids.filter(id => id !== c.id),
                            }));
                          }}
                        />
                        <div className="flex-1 min-w-0">
                          <div className="text-sm font-medium truncate">{c.nome_completo}</div>
                          {escalaAtual && (
                            <div className="text-[11px] text-muted-foreground flex items-center gap-1">
                              <AlertTriangle className="w-3 h-3 text-amber-500" />
                              {jaNessa ? "Já atribuído a esta escala" : `Já em: ${escalaAtual.nome}`}
                            </div>
                          )}
                        </div>
                        {jaNessa && <Badge variant="outline" className="text-[10px]">Atual</Badge>}
                        {bloqueado && <Badge variant="outline" className="text-[10px] border-amber-500 text-amber-700">Bloqueado</Badge>}
                      </label>
                    );
                  })}
                {colaboradores.length === 0 && (
                  <div className="p-4 text-center text-sm text-muted-foreground">Nenhum colaborador encontrado.</div>
                )}
              </div>

              <label className="flex items-start gap-2 rounded-md border bg-amber-50/40 dark:bg-amber-950/10 px-3 py-2 cursor-pointer">
                <Checkbox checked={atribuicaoForm.substituir} onCheckedChange={(v) => setAtribuicaoForm(f => ({ ...f, substituir: !!v }))} />
                <div className="text-xs">
                  <span className="font-semibold">Substituir escala atual</span> dos selecionados que já estão em outra escala.
                  <div className="text-muted-foreground">Inativa a atribuição anterior na data de início informada.</div>
                </div>
              </label>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAtribuir(false)} disabled={atribuindoLote}>Cancelar</Button>
            <Button onClick={handleAtribuirLote} disabled={atribuindoLote || atribuicaoForm.colaborador_ids.length === 0}>
              {atribuindoLote ? "Atribuindo..." : `Atribuir ${atribuicaoForm.colaborador_ids.length || ""}`.trim()}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Editar escala de um colaborador (atribuição ativa) */}
      <Dialog open={!!editAtribuicao} onOpenChange={(o) => { if (!o) setEditAtribuicao(null); }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Editar escala — {editAtribuicao?.colaborador_nome}</DialogTitle>
          </DialogHeader>
          {editAtribuicao && (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label>Escala atual</Label>
                <Input
                  value={escalas.find(e => e.id === editAtribuicao.escala_id)?.nome || "-"}
                  disabled
                />
              </div>

              <div className="space-y-2">
                <Label>Nova escala</Label>
                <Select
                  value={editAtribuicao.escala_id_nova}
                  onValueChange={v => setEditAtribuicao({ ...editAtribuicao, escala_id_nova: v })}
                >
                  <SelectTrigger><SelectValue placeholder="Selecione a escala" /></SelectTrigger>
                  <SelectContent>
                    {escalas.filter(e => e.ativa !== false).map(e => (
                      <SelectItem key={e.id} value={e.id}>{e.nome}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label>A partir de</Label>
                <Input
                  type="date"
                  value={editAtribuicao.data_inicio}
                  onChange={e => setEditAtribuicao({ ...editAtribuicao, data_inicio: e.target.value })}
                />
                <p className="text-[11px] text-muted-foreground">
                  A escala atual é encerrada nesta data e a nova passa a valer a partir dela.
                  O histórico anterior é preservado.
                </p>
              </div>
            </div>
          )}
          <DialogFooter className="sm:justify-between">
            <Button
              variant="outline"
              onClick={() => editAtribuicao && abrirHistorico(editAtribuicao.colaborador_id, editAtribuicao.colaborador_nome)}
            >
              <Clock className="h-4 w-4 mr-1" />
              Histórico
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setEditAtribuicao(null)}>Cancelar</Button>
              <Button onClick={handleSalvarEdicaoAtribuicao} disabled={salvandoEdicao}>
                {salvandoEdicao ? "Salvando..." : "Salvar"}
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Histórico de escalas do colaborador */}
      <Dialog open={!!historico} onOpenChange={(o) => { if (!o) setHistorico(null); }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Histórico de escalas — {historico?.colaborador_nome}</DialogTitle>
          </DialogHeader>

          {carregandoHistorico ? (
            <p className="text-sm text-muted-foreground py-6 text-center">Carregando…</p>
          ) : !historico?.itens.length ? (
            <p className="text-sm text-muted-foreground py-6 text-center">
              Nenhuma atribuição registrada para este colaborador.
            </p>
          ) : (
            <div className="space-y-2 max-h-[60vh] overflow-y-auto">
              {historico.itens.map(h => {
                const nomeEscala = escalas.find(e => e.id === h.escala_id)?.nome || "Escala removida";
                return (
                  <div
                    key={h.id}
                    className={`rounded-md border p-3 ${h.ativa ? "bg-muted/40" : ""}`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-medium text-sm">{nomeEscala}</span>
                      {h.ativa && <Badge variant="secondary">Vigente</Badge>}
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                      {h.data_fim
                        ? `De ${formatarData(h.data_inicio)} até ${formatarData(h.data_fim)}`
                        : `A partir de ${formatarData(h.data_inicio)}`}
                    </p>
                  </div>
                );
              })}
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setHistorico(null)}>Fechar</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Cadastro Inteligente */}
      <CadastroInteligenteEscala open={showInteligente} onOpenChange={setShowInteligente} />
    </div>
  );
}

function DetalhesEscalaPanel({ escalaId }: { escalaId: string }) {
  const { periodos, recorrencias, loading } = useEscalaDetalhes(escalaId);

  // Agrupa períodos por dia
  const porDia = periodos.reduce<Record<string, { hora_inicio: string; hora_fim: string }[]>>((acc, p) => {
    (acc[p.dia_semana] = acc[p.dia_semana] || []).push({
      hora_inicio: p.hora_inicio.substring(0, 5),
      hora_fim: p.hora_fim.substring(0, 5),
    });
    return acc;
  }, {});

  if (loading) {
    return <div className="text-xs text-muted-foreground py-2">Carregando blocos e recorrências…</div>;
  }

  if (periodos.length === 0 && recorrencias.length === 0) {
    return (
      <div className="text-xs text-muted-foreground border-t pt-3">
        Esta escala não possui blocos diários nem recorrências detalhadas. Use o <strong>Cadastro Inteligente</strong> para criar uma escala com horários completos.
      </div>
    );
  }

  const ORDEM = ["segunda", "terca", "quarta", "quinta", "sexta", "sabado", "domingo"];
  const diasOrdenados = Object.keys(porDia).sort((a, b) => ORDEM.indexOf(a) - ORDEM.indexOf(b));

  return (
    <div className="space-y-5 border-t pt-4">
      {diasOrdenados.length > 0 && (
        <div className="space-y-2">
          <Label className="text-xs uppercase tracking-wide text-muted-foreground flex items-center gap-1.5">
            <CalendarDays className="w-3.5 h-3.5" /> Blocos diários cadastrados
          </Label>
          <div className="rounded-lg border overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-xs uppercase text-muted-foreground">
                <tr>
                  <th className="text-left px-3 py-2 font-medium w-32">Dia</th>
                  <th className="text-left px-3 py-2 font-medium">Horários</th>
                  <th className="text-right px-3 py-2 font-medium w-20">Total</th>
                </tr>
              </thead>
              <tbody>
                {diasOrdenados.map((dia, idx) => {
                  const totalMin = porDia[dia].reduce((acc, b) => {
                    const [h1, m1] = b.hora_inicio.split(":").map(Number);
                    const [h2, m2] = b.hora_fim.split(":").map(Number);
                    return acc + (h2 * 60 + m2) - (h1 * 60 + m1);
                  }, 0);
                  const horas = Math.floor(totalMin / 60);
                  const mins = totalMin % 60;
                  return (
                    <tr
                      key={dia}
                      className={`border-t ${idx % 2 === 0 ? "bg-background" : "bg-muted/20"}`}
                    >
                      <td className="px-3 py-2 font-semibold">{DIAS_SEMANA_LABEL[dia] || dia}</td>
                      <td className="px-3 py-2">
                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-xs">
                          {porDia[dia].map((b, i) => (
                            <span key={i} className="inline-flex items-center gap-1.5">
                              {i > 0 && <span className="text-muted-foreground">·</span>}
                              <Clock className="w-3 h-3 text-primary" />
                              <span>{b.hora_inicio}</span>
                              <span className="text-muted-foreground">→</span>
                              <span>{b.hora_fim}</span>
                            </span>
                          ))}
                        </div>
                      </td>
                      <td className="px-3 py-2 text-right font-mono text-xs text-muted-foreground whitespace-nowrap">
                        {horas}h{mins > 0 ? mins.toString().padStart(2, "0") : ""}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {recorrencias.length > 0 && (
        <div className="space-y-2.5">
          <Label className="text-xs uppercase tracking-wide text-muted-foreground flex items-center gap-1.5">
            <Repeat className="w-3.5 h-3.5" /> Recorrências mensais
          </Label>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {recorrencias.map((r) => (
              <div
                key={r.id}
                className="rounded-lg border border-primary/30 bg-primary/5 p-2.5 flex items-start gap-2"
              >
                <div className="rounded-md bg-primary/15 p-1.5 shrink-0">
                  <Repeat className="w-3.5 h-3.5 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm leading-tight">
                    {ORDINAL_MES_LABEL[r.ordinal_mes] || r.ordinal_mes}{" "}
                    {DIAS_SEMANA_LABEL[r.dia_semana] || r.dia_semana}
                  </div>
                  <div className="flex items-center gap-1.5 mt-1 text-xs font-mono">
                    <Clock className="w-3 h-3 text-primary" />
                    <span>{r.hora_inicio.substring(0, 5)}</span>
                    <span className="text-muted-foreground">→</span>
                    <span>{r.hora_fim.substring(0, 5)}</span>
                  </div>
                  {r.descricao && (
                    <div className="text-xs text-muted-foreground mt-1 italic line-clamp-2">
                      {r.descricao}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <p className="text-[11px] text-muted-foreground italic border-t pt-2">
        ℹ️ Blocos diários e recorrências são gerados pelo Cadastro Inteligente. Para alterá-los, recadastre a escala via IA.
      </p>
    </div>
  );
}
