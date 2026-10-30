import { useEffect, useMemo, useRef, useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { supabasePublic } from "@/lib/supabasePublic";
import { Loader2, Paperclip, X, CheckCircle2, ChevronLeft, ChevronRight, AlertCircle, Clock, FileText, PencilLine } from "lucide-react";
import { toast } from "sonner";
import { useIsMobile } from "@/hooks/use-mobile";
import { PontoSelfieCapture } from "@/components/ponto/PontoSelfieCapture";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  token: string;
  /** CPF (apenas dígitos) quando o acesso é via link compartilhado. */
  cpf?: string;
  colaboradorNome: string;
  /** Exigência de selfie da empresa (a lista do app confirma o valor vigente). */
  exigirSelfie?: boolean;
}

type TipoMarc = "entrada" | "saida_almoco" | "retorno_almoco" | "saida";
type Natureza = "correcao_batida" | "ausencia";

interface Marcacao { id: string; data: string; hora: string; tipo: TipoMarc; }
interface AjustePend { id: string; data: string; hora: string; tipo: TipoMarc; status: string; }
interface JustificativaApp {
  id: string;
  nome: string;
  descricao?: string | null;
  natureza: Natureza;
  requer_anexo?: boolean;
}

const MAX_FILE_MB = 5;
const MAX_FILES = 3;
const MAX_ITENS = 40;
const MAX_OBS = 300;

function fmtHora(h: string) { return (h || "").slice(0, 5); }
function pad(n: number) { return n < 10 ? `0${n}` : `${n}`; }
function isoToBR(iso: string) { const [y,m,d] = iso.split("-"); return `${d}/${m}/${y}`; }
function toMin(s?: string): number | null {
  if (!s || !/^\d{2}:\d{2}/.test(s)) return null;
  return Number(s.slice(0, 2)) * 60 + Number(s.slice(3, 5));
}
function diaSemana(iso: string) {
  const ds = ["Dom","Seg","Ter","Qua","Qui","Sex","Sáb"];
  return ds[new Date(iso + "T12:00:00").getDay()];
}
function nomeSeguro(nome: string) { return nome.replace(/[^a-zA-Z0-9._-]/g, "_"); }

// Tipo de uma marcação pela POSIÇÃO na sequência do dia:
// par (0,2,4...) = entrada; ímpar (1,3,5...) = saída.
// Modelo de alternância livre — comporta múltiplos ciclos por dia.
function tipoPorIndice(i: number): "entrada" | "saida" {
  return i % 2 === 0 ? "entrada" : "saida";
}
function tipoLabelIndice(i: number): string {
  return tipoPorIndice(i) === "entrada" ? "Entrada" : "Saída";
}

interface AusenciaEdit {
  diaInteiro: boolean;
  inicio: string;
  fim: string;
  files: File[];
}

// Por dia: o colaborador escolhe a NATUREZA do pedido.
//  * Correção de batida: edita os horários (marcacoes) e escolhe uma
//    justificativa de correção. Vira marcação na aprovação.
//  * Ausência: dia inteiro ou início/fim, justificativa de ausência e o
//    documento (declaração/atestado) obrigatório. Vira lançamento em
//    Atestados na aprovação — nunca batida.
interface DiaEdit {
  natureza?: Natureza;
  marcacoes?: string[];          // novos horários propostos (sequência)
  justificativaId: string;
  observacao: string;
  ausencia: AusenciaEdit;
}

const AUSENCIA_VAZIA: AusenciaEdit = { diaInteiro: true, inicio: "", fim: "", files: [] };
const EDIT_VAZIO: DiaEdit = { justificativaId: "", observacao: "", ausencia: AUSENCIA_VAZIA };

export function SolicitarAjusteModal({ open, onOpenChange, token, cpf, exigirSelfie: exigirSelfieProp }: Props) {
  const today = new Date().toISOString().slice(0, 10);
  const hojeDate = new Date();
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const isMobile = useIsMobile();

  const [loading, setLoading] = useState(false);
  const [marcacoes, setMarcacoes] = useState<Marcacao[]>([]);
  const [ajustesPend, setAjustesPend] = useState<AjustePend[]>([]);
  // Escala pré-assinalada (intervalo declarado, não batido): a folha mostra só
  // 1 par Entrada/Saída. A flag vem da RPC pública (sem auth p/ ler config).
  const [preAssinalado, setPreAssinalado] = useState(false);
  const [mesAtivo, setMesAtivo] = useState(() => `${hojeDate.getFullYear()}-${pad(hojeDate.getMonth()+1)}`);
  const [edits, setEdits] = useState<Record<string, DiaEdit>>({}); // por data
  const [files, setFiles] = useState<File[]>([]); // anexos opcionais das correções
  const [enviando, setEnviando] = useState(false);
  const [done, setDone] = useState(false);
  const [totalEnviado, setTotalEnviado] = useState(0);

  // Justificativas liberadas pelo RH para o app (com natureza).
  const [justApp, setJustApp] = useState<JustificativaApp[]>([]);
  const [justStatus, setJustStatus] = useState<"carregando" | "ok" | "vazio" | "desatualizado" | "erro">("carregando");
  const [exigirSelfie, setExigirSelfie] = useState<boolean>(exigirSelfieProp ?? true);
  const [selfieFile, setSelfieFile] = useState<File | null>(null);
  const [selfiePreview, setSelfiePreview] = useState<string | null>(null);

  const justCorrecao = useMemo(() => justApp.filter((j) => j.natureza === "correcao_batida"), [justApp]);
  const justAusencia = useMemo(() => justApp.filter((j) => j.natureza === "ausencia"), [justApp]);
  const justPorId = useMemo(() => {
    const m: Record<string, JustificativaApp> = {};
    justApp.forEach((j) => { m[j.id] = j; });
    return m;
  }, [justApp]);

  const reset = () => {
    setEdits({}); setFiles([]); setDone(false); setTotalEnviado(0);
    setSelfieFile(null); setSelfiePreview(null);
  };

  // Justificativas do app novo (só as liberadas pelo RH, com natureza).
  useEffect(() => {
    if (!open || !token) return;
    let cancel = false;
    setJustStatus("carregando");
    (async () => {
      try {
        const { data, error } = await supabasePublic.rpc("listar_justificativas_app" as any, { p_token: token });
        if (cancel) return;
        if (error) {
          // Função ainda não publicada no banco (app novo antes do banco).
          const semFuncao = (error as any)?.code === "PGRST202" || /could not find the function/i.test(error.message || "");
          setJustApp([]);
          setJustStatus(semFuncao ? "desatualizado" : "erro");
          return;
        }
        const r = data as any;
        if (r?.error) { setJustApp([]); setJustStatus("erro"); toast.error(r.error); return; }
        if (typeof r?.exigir_selfie === "boolean") setExigirSelfie(r.exigir_selfie);
        const arr = (Array.isArray(r?.justificativas) ? r.justificativas : []) as JustificativaApp[];
        const validas = arr.filter((j) => j && j.id && (j.natureza === "correcao_batida" || j.natureza === "ausencia"));
        setJustApp(validas);
        setJustStatus(validas.length > 0 ? "ok" : "vazio");
      } catch {
        if (!cancel) { setJustApp([]); setJustStatus("erro"); }
      }
    })();
    return () => { cancel = true; };
  }, [open, token]);

  useEffect(() => {
    if (!open) return;
    (async () => {
      setLoading(true);
      // Pede 45 dias para cobrir mês atual + anterior
      const { data, error } = cpf
        ? await supabasePublic.rpc("listar_ponto_externo_cpf" as any, { p_token: token, p_cpf: cpf, p_dias: 45 })
        : await supabasePublic.rpc("listar_ponto_externo" as any, { p_token: token, p_dias: 45 });
      if (error) { toast.error(error.message); setLoading(false); return; }
      const r = data as any;
      if (r?.error) { toast.error(r.error); setLoading(false); return; }
      setMarcacoes((r?.marcacoes || []) as Marcacao[]);
      setAjustesPend((r?.ajustes || []) as AjustePend[]);
      setPreAssinalado(!!r?.pre_assinalado);
      setLoading(false);
    })();
  }, [open, token, cpf]);

  // Gera lista de dias do mês ativo (limitado ao hoje)
  const diasMes = useMemo(() => {
    const [y, m] = mesAtivo.split("-").map(Number);
    const lastDay = new Date(y, m, 0).getDate();
    const arr: string[] = [];
    for (let d = 1; d <= lastDay; d++) {
      const iso = `${y}-${pad(m)}-${pad(d)}`;
      if (iso <= today) arr.push(iso);
    }
    return arr; // Ordem cronológica (01, 02, 03...)
  }, [mesAtivo, today]);

  const marcsPorDia = useMemo(() => {
    // Sequência cronológica de horários por dia (alternância entrada/saída).
    // Reúne TODAS as marcações do dia (não descarta repetidas por tipo).
    const map: Record<string, string[]> = {};
    const porDia: Record<string, { hora: string }[]> = {};
    marcacoes.forEach((m) => {
      // Só entra na folha o que é horário de verdade. Um registro sem hora
      // legível virava um campo vazio no meio do dia — uma "batida fantasma"
      // que empurrava as posições seguintes e, pior, fazia o primeiro horário
      // digitado ali ser lido como CORREÇÃO de uma batida que não existe.
      if (!/^\d{2}:\d{2}/.test(String(m.hora || ""))) return;
      (porDia[m.data] ||= []).push({ hora: m.hora });
    });
    Object.entries(porDia).forEach(([data, lista]) => {
      lista.sort((a, b) => String(a.hora).localeCompare(String(b.hora)));
      map[data] = lista.map((x) => fmtHora(x.hora));
    });
    return map;
  }, [marcacoes]);

  const pendentesPorDia = useMemo(() => {
    const map: Record<string, AjustePend[]> = {};
    ajustesPend.forEach((a) => {
      if (a.status !== "pendente") return;
      if (!map[a.data]) map[a.data] = [];
      map[a.data].push(a);
    });
    return map;
  }, [ajustesPend]);

  // Um dia está BLOQUEADO para ajuste enquanto tiver pedido pendente de
  // aprovação. O bloqueio é por dia: dias sem pendência seguem editáveis.
  const diaBloqueado = (data: string): boolean => (pendentesPorDia[data]?.length ?? 0) > 0;

  // Helpers de edição
  const editDia = (data: string): DiaEdit => edits[data] || EDIT_VAZIO;
  const patchDia = (data: string, patch: Partial<DiaEdit>) => {
    setEdits((prev) => ({ ...prev, [data]: { ...(prev[data] || EDIT_VAZIO), ...patch } }));
  };
  const patchAusencia = (data: string, patch: Partial<AusenciaEdit>) => {
    setEdits((prev) => {
      const cur = prev[data] || EDIT_VAZIO;
      return { ...prev, [data]: { ...cur, ausencia: { ...cur.ausencia, ...patch } } };
    });
  };

  // Troca de natureza: limpa o que não vale para a outra (a justificativa de
  // uma natureza não serve para a outra; os horários editados só existem na
  // correção; os documentos só na ausência).
  const escolherNatureza = (data: string, natureza: Natureza | undefined) => {
    setEdits((prev) => {
      const cur = prev[data] || EDIT_VAZIO;
      if (cur.natureza === natureza) return prev;
      return {
        ...prev,
        [data]: {
          ...cur,
          natureza,
          justificativaId: "",
          marcacoes: natureza === "correcao_batida" ? cur.marcacoes : undefined,
          ausencia: natureza === "ausencia" ? cur.ausencia : AUSENCIA_VAZIA,
        },
      };
    });
  };

  // Lista efetiva de marcações do dia (edição ou originais)
  const marcacoesEfetivas = (data: string): string[] => {
    const ed = editDia(data);
    if (ed.natureza === "correcao_batida" && ed.marcacoes !== undefined) return ed.marcacoes;
    return marcsPorDia[data] || [];
  };

  // Editar um horário já é escolher "Correção de batida" para o dia.
  const setMarcacao = (data: string, idx: number, valor: string) => {
    setEdits((prev) => {
      const cur = prev[data] || EDIT_VAZIO;
      const base = cur.marcacoes !== undefined ? [...cur.marcacoes] : [...(marcsPorDia[data] || [])];
      base[idx] = valor;
      return { ...prev, [data]: { ...cur, natureza: "correcao_batida", marcacoes: base,
        justificativaId: cur.natureza === "correcao_batida" ? cur.justificativaId : "" } };
    });
  };

  // Adiciona uma marcação avulsa ao fim
  const adicionarMarcacao = (data: string) => {
    setEdits((prev) => {
      const cur = prev[data] || EDIT_VAZIO;
      const base = cur.marcacoes !== undefined ? [...cur.marcacoes] : [...(marcsPorDia[data] || [])];
      base.push("");
      return { ...prev, [data]: { ...cur, natureza: "correcao_batida", marcacoes: base,
        justificativaId: cur.natureza === "correcao_batida" ? cur.justificativaId : "" } };
    });
  };

  // Remove uma marcação ACRESCENTADA agora. Nunca uma batida já registrada:
  // excluir batida não existe no sistema (ponto_ajustes só representa
  // inclusão/correção). Para anular o dia, use "Ausência".
  const removerMarcacao = (data: string, idx: number) => {
    const original = marcsPorDia[data] || [];
    if (idx < original.length) {
      toast.error(
        "Não é possível excluir um horário já registrado. Para corrigi-lo, altere a hora; se você faltou com documento, escolha \"Ausência\"."
      );
      return;
    }
    setEdits((prev) => {
      const cur = prev[data] || EDIT_VAZIO;
      const base = cur.marcacoes !== undefined ? [...cur.marcacoes] : [...(marcsPorDia[data] || [])];
      base.splice(idx, 1);
      return { ...prev, [data]: { ...cur, marcacoes: base } };
    });
  };

  // Correções efetivamente alteradas, comparando POSIÇÃO a posição — exatamente
  // o que a tela mostra: posição i < nº de originais e valor diferente ->
  // CORREÇÃO daquela batida; posição nova -> INCLUSÃO. Campo em branco não
  // vira pedido. O tipo (entrada/saída) vem da ordem cronológica do dia.
  const itensCorrecao = useMemo(() => {
    const out: { data: string; tipo: "entrada" | "saida"; hora: string; horaOriginal?: string }[] = [];
    Object.entries(edits).forEach(([data, ed]) => {
      if (ed.natureza !== "correcao_batida" || ed.marcacoes === undefined) return;
      if (diaBloqueado(data)) return; // dia com pendência não gera novo ajuste
      const original = marcsPorDia[data] || [];
      const propostas = ed.marcacoes.map((s) => (s || "").trim());
      const ordenadas = propostas.filter(Boolean).sort((a, b) => (toMin(a) ?? 0) - (toMin(b) ?? 0));
      const tipoDe = (hora: string) => tipoPorIndice(ordenadas.indexOf(hora));
      propostas.forEach((hora, i) => {
        if (!hora) return;                    // linha em branco: nada a pedir
        const orig = original[i];             // undefined = linha acrescentada agora
        if (orig === hora) return;            // não mexeu nesta batida
        out.push({ data, tipo: tipoDe(hora), hora, horaOriginal: orig || undefined });
      });
    });
    return out;
  }, [edits, marcsPorDia, pendentesPorDia]);

  const diasAusencia = useMemo(
    () => Object.entries(edits)
      .filter(([data, ed]) => ed.natureza === "ausencia" && !diaBloqueado(data))
      .map(([data]) => data)
      .sort(),
    [edits, pendentesPorDia]
  );

  // Batida registrada que o funcionário apagou (limpou o campo). Não vira
  // pedido — o banco não sabe representar "excluir batida" —, mas precisa de
  // aviso próprio.
  const apagouRegistrada = useMemo(() => {
    return Object.entries(edits).some(([data, ed]) => {
      if (ed.natureza !== "correcao_batida" || ed.marcacoes === undefined) return false;
      if (diaBloqueado(data)) return false;
      const original = marcsPorDia[data] || [];
      return original.some((o, i) => !!o && !((ed.marcacoes as string[])[i] || "").trim());
    });
  }, [edits, marcsPorDia, pendentesPorDia]);

  const totalAlteracoes = itensCorrecao.length + diasAusencia.length;
  const podeEnviar = justStatus === "ok";

  const filtrarArquivos = (list: FileList | null, atuais: File[]): File[] => {
    if (!list) return atuais;
    const validos: File[] = [];
    for (const f of Array.from(list)) {
      if (f.size > MAX_FILE_MB * 1024 * 1024) { toast.error(`${f.name}: ultrapassa ${MAX_FILE_MB}MB.`); continue; }
      validos.push(f);
    }
    return [...atuais, ...validos].slice(0, MAX_FILES);
  };

  const validar = (): string | null => {
    if (justStatus === "desatualizado") return "O app está sendo atualizado. Tente de novo em instantes.";
    if (justStatus === "vazio") return "Seu RH ainda não liberou os motivos de ajuste no app. Fale com o RH.";
    if (justStatus !== "ok") return "Não foi possível carregar os motivos de ajuste. Feche e abra de novo.";
    // Este aviso vem ANTES do "altere ao menos um horário": apagar uma batida
    // registrada não gera item, então os dois casos chegam aqui com contador zero.
    if (apagouRegistrada) {
      return "Não é possível excluir um horário já registrado. Para corrigi-lo, altere a hora; se você faltou com documento, escolha \"Ausência\".";
    }
    if (totalAlteracoes === 0) return "Corrija um horário ou informe uma ausência em ao menos um dia.";
    if (totalAlteracoes > MAX_ITENS) return `Máximo de ${MAX_ITENS} itens por envio.`;
    const now = new Date();
    const agoraMin = now.getHours() * 60 + now.getMinutes();

    // Correções: justificativa de correção + sequência coerente
    const diasCorrecao = new Set(itensCorrecao.map((i) => i.data));
    for (const data of diasCorrecao) {
      const ed = editDia(data);
      const just = justPorId[ed.justificativaId];
      if (!just || just.natureza !== "correcao_batida") return `Escolha o motivo da correção de ${isoToBR(data)}.`;
      if (ed.observacao.length > MAX_OBS) return `A observação de ${isoToBR(data)} pode ter no máximo ${MAX_OBS} caracteres.`;

      const seq = marcacoesEfetivas(data).map((x) => (x || "").trim());
      const preenchidas = seq.map((h) => ({ h, min: toMin(h) })).filter((x) => x.h !== "");
      for (const x of preenchidas) {
        if (x.min === null) return `Em ${isoToBR(data)}, há um horário inválido. Use o formato HH:MM.`;
      }
      // Permite lançar FORA DE ORDEM (o dia é ordenado na consolidação); só
      // bloqueia duas marcações no MESMO horário.
      const minsOrdenados = preenchidas.map((x) => x.min as number).sort((a, b) => a - b);
      for (let i = 1; i < minsOrdenados.length; i++) {
        if (minsOrdenados[i] === minsOrdenados[i - 1]) {
          return `Em ${isoToBR(data)}, há duas marcações no mesmo horário. Remova a duplicada.`;
        }
      }
    }
    for (const it of itensCorrecao) {
      if (it.data > today) return "Não é permitido ajustar data futura.";
      if (it.data === today && (toMin(it.hora) ?? 0) > agoraMin) return "Não é permitido ajustar horário futuro.";
    }

    // Ausências: justificativa de ausência + período + documento
    for (const data of diasAusencia) {
      const ed = editDia(data);
      const just = justPorId[ed.justificativaId];
      if (!just || just.natureza !== "ausencia") return `Escolha o motivo da ausência de ${isoToBR(data)}.`;
      if (ed.observacao.length > MAX_OBS) return `A observação de ${isoToBR(data)} pode ter no máximo ${MAX_OBS} caracteres.`;
      if (!ed.ausencia.diaInteiro) {
        const ini = toMin(ed.ausencia.inicio);
        const fim = toMin(ed.ausencia.fim);
        if (ini === null || fim === null) return `Informe o início e o fim da ausência de ${isoToBR(data)}, ou marque "Dia inteiro".`;
        if (fim <= ini) return `Na ausência de ${isoToBR(data)}, o fim precisa ser depois do início.`;
        if (data === today && fim > agoraMin) return "A ausência de hoje ainda não terminou. Envie depois do horário de fim.";
      }
      if (ed.ausencia.files.length === 0) return `Anexe a declaração ou o atestado da ausência de ${isoToBR(data)}.`;
    }

    if (exigirSelfie && !selfieFile) return "Tire a selfie para enviar o pedido.";
    return null;
  };

  const subirAnexos = async (lista: File[]) => {
    const anexos: { nome: string; url: string; tamanho: number; tipo: string }[] = [];
    for (const f of lista) {
      const path = `externo/${token}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${nomeSeguro(f.name)}`;
      const { error: upErr } = await supabasePublic.storage.from("ponto-ajustes-anexos").upload(path, f, { contentType: f.type });
      if (upErr) throw new Error(`Falha no envio de ${f.name}: ${upErr.message}`);
      anexos.push({ nome: f.name, url: path, tamanho: f.size, tipo: f.type });
    }
    return anexos;
  };

  const handleSubmit = async () => {
    const erro = validar();
    if (erro) { toast.error(erro); return; }
    setEnviando(true);
    try {
      // Selfie: bucket privado; grava só o CAMINHO (o RH vê por link temporário).
      let selfiePath: string | null = null;
      if (selfieFile) {
        const nome = `externo/ajustes/${token}/${Date.now()}_selfie.jpg`;
        const { data: up, error: upErr } = await supabasePublic.storage
          .from("ponto-selfies")
          .upload(nome, selfieFile, { contentType: "image/jpeg" });
        if (upErr || !up) {
          if (exigirSelfie) {
            toast.error("Não consegui enviar sua selfie agora. Verifique sua conexão e toque em Enviar novamente.");
            setEnviando(false);
            return;
          }
        } else {
          selfiePath = up.path;
        }
      }

      const anexosCorrecoes = itensCorrecao.length > 0 ? await subirAnexos(files) : [];

      const correcoes = itensCorrecao.map((it) => {
        const ed = editDia(it.data);
        return {
          data: it.data,
          hora: `${it.hora}:00`,
          hora_original: it.horaOriginal ? `${it.horaOriginal}:00` : null,
          tipo: it.tipo,
          justificativa_id: ed.justificativaId,
          observacao: ed.observacao.trim() || null,
        };
      });

      const ausencias = [];
      for (const data of diasAusencia) {
        const ed = editDia(data);
        const anexos = await subirAnexos(ed.ausencia.files);
        ausencias.push({
          data,
          dia_inteiro: ed.ausencia.diaInteiro,
          hora_inicio: ed.ausencia.diaInteiro ? null : ed.ausencia.inicio,
          hora_fim: ed.ausencia.diaInteiro ? null : ed.ausencia.fim,
          justificativa_id: ed.justificativaId,
          observacao: ed.observacao.trim() || null,
          anexos,
        });
      }

      // Uma chamada só: correções e ausências juntas (tudo ou nada).
      const { data: resp, error } = await supabasePublic.rpc("solicitar_ajustes_ponto_app" as any, {
        p_token: token,
        p_cpf: cpf || null,
        p_correcoes: correcoes as any,
        p_ausencias: ausencias as any,
        p_anexos: anexosCorrecoes as any,
        p_selfie_url: selfiePath,
      });
      if (error) {
        const semFuncao = (error as any)?.code === "PGRST202" || /could not find the function/i.test(error.message || "");
        toast.error(semFuncao ? "O app está sendo atualizado. Tente de novo em instantes." : error.message);
        setEnviando(false);
        return;
      }
      const r = resp as any;
      if (r?.error) { toast.error(r.error); setEnviando(false); return; }
      setTotalEnviado(Number(r?.total) || totalAlteracoes);
      setDone(true);
    } catch (e: any) {
      toast.error(e.message || "Erro ao enviar solicitação.");
    }
    setEnviando(false);
  };

  // Navegação de mês
  const navegarMes = (delta: number) => {
    const [y, m] = mesAtivo.split("-").map(Number);
    const nd = new Date(y, m - 1 + delta, 1);
    const novo = `${nd.getFullYear()}-${pad(nd.getMonth()+1)}`;
    // limita a hoje (não permite mês futuro)
    if (novo > `${hojeDate.getFullYear()}-${pad(hojeDate.getMonth()+1)}`) return;
    setMesAtivo(novo);
  };

  const mesLabel = useMemo(() => {
    const [y, m] = mesAtivo.split("-").map(Number);
    const nomes = ["Janeiro","Fevereiro","Março","Abril","Maio","Junho","Julho","Agosto","Setembro","Outubro","Novembro","Dezembro"];
    return `${nomes[m-1]} ${y}`;
  }, [mesAtivo]);

  // Escolha da natureza do dia (dois botões).
  const renderEscolha = (data: string, ed: DiaEdit) => (
    <div className="flex flex-wrap gap-1.5">
      <Button
        type="button"
        size="sm"
        variant={ed.natureza === "correcao_batida" ? "default" : "outline"}
        className="h-7 px-2 text-[11px]"
        onClick={() => escolherNatureza(data, ed.natureza === "correcao_batida" ? undefined : "correcao_batida")}
      >
        <PencilLine className="w-3 h-3 mr-1" /> Correção de batida
      </Button>
      <Button
        type="button"
        size="sm"
        variant={ed.natureza === "ausencia" ? "default" : "outline"}
        className={`h-7 px-2 text-[11px] ${ed.natureza === "ausencia" ? "bg-violet-600 hover:bg-violet-700" : ""}`}
        onClick={() => escolherNatureza(data, ed.natureza === "ausencia" ? undefined : "ausencia")}
      >
        <FileText className="w-3 h-3 mr-1" /> Ausência (declaração/atestado)
      </Button>
    </div>
  );

  // Blocos reutilizados no layout de tabela (desktop) e em cartões (mobile).
  const renderMarcacoes = (
    data: string,
    original: string[],
    ed: DiaEdit,
    qtdPendentes: number,
  ) => {
    if (diaBloqueado(data)) {
      return (
        <div className="flex items-start gap-2 py-1.5">
          <Clock className="w-3.5 h-3.5 text-amber-600 mt-0.5 shrink-0" />
          <div>
            <p className="text-[11px] font-medium text-amber-700 dark:text-amber-400">Pedido ainda pendente — aguarde a aprovação.</p>
            <p className="text-[10px] text-muted-foreground mt-0.5">
              Este dia tem {qtdPendentes} pedido(s) aguardando o gestor. Não é possível alterar até ser aprovado ou rejeitado.
            </p>
          </div>
        </div>
      );
    }

    // Ausência: os horários registrados ficam só para consulta.
    if (ed.natureza === "ausencia") {
      return (
        <div className="flex flex-col gap-1.5">
          {renderEscolha(data, ed)}
          <div className="text-[10px] text-muted-foreground">
            {original.length > 0 ? `Registrado no dia: ${original.join(" · ")}` : "Sem marcações no dia."}
            <span className="block italic">Ausência não altera as batidas: o documento vai para o RH.</span>
          </div>
        </div>
      );
    }

    const marcs = marcacoesEfetivas(data);

    // Renderiza o campo de UMA posição i. labelOverride força Entrada/Saída
    // (usado na folha pré-assinalada).
    const renderCampo = (i: number, labelOverride?: "entrada" | "saida") => {
      const valor = marcs[i] || "";
      const orig = original[i] || "";
      const novaMarc = i >= original.length;
      const alterado = ed.marcacoes !== undefined && (valor || "") !== orig && !novaMarc;
      const tipo = labelOverride || tipoPorIndice(i);
      const label = labelOverride ? (labelOverride === "entrada" ? "Entrada" : "Saída") : tipoLabelIndice(i);
      const ehUltima = i === marcs.length - 1;
      return (
        <div key={i} className="flex flex-col gap-0.5">
          <span className={`text-[9px] font-semibold ${tipo === "entrada" ? "text-emerald-600 dark:text-emerald-400" : "text-rose-600 dark:text-rose-400"}`}>
            {label}
          </span>
          <div className="flex items-center gap-1">
            <Input
              type="time"
              value={valor || ""}
              onChange={(e) => setMarcacao(data, i, e.target.value)}
              className={`h-9 text-xs font-mono px-1 w-[92px] ${
                novaMarc ? "border-emerald-500 bg-emerald-50 dark:bg-emerald-950/30"
                : alterado ? "border-amber-500 bg-amber-50 dark:bg-amber-950/30"
                : ""
              }`}
            />
            {/* Só a marcação ACRESCENTADA agora ganha o X. */}
            {novaMarc && ehUltima && (
              <button
                type="button"
                onClick={() => removerMarcacao(data, i)}
                className="text-muted-foreground hover:text-destructive shrink-0 p-1"
                title="Remover marcação adicionada"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </div>
          {orig && alterado && (
            <div className="text-[9px] text-muted-foreground line-through">orig: {orig}</div>
          )}
        </div>
      );
    };

    // Escala pré-assinalada: só 1 par (Entrada + Saída). O intervalo é
    // declarado, não batido (Súmula 338 — marcação é imutável).
    if (preAssinalado) {
      return (
        <div className="flex flex-col gap-1.5">
          {renderEscolha(data, ed)}
          {marcs.length === 0 ? (
            <span className="text-[10px] text-muted-foreground italic py-1.5">Sem marcações</span>
          ) : (
            <div className="flex flex-wrap items-start gap-2">
              {renderCampo(0, "entrada")}
              {renderCampo(marcs.length > 1 ? marcs.length - 1 : 1, "saida")}
              {marcs.length < 2 && (
                <button
                  type="button"
                  onClick={() => adicionarMarcacao(data)}
                  className="h-9 mt-[14px] px-2 text-[10px] rounded border border-dashed border-muted-foreground/40 text-muted-foreground hover:border-primary hover:text-primary shrink-0"
                  title="Adicionar saída"
                >
                  + marcação
                </button>
              )}
            </div>
          )}
          {marcs.length > 2 && (
            <span className="text-[9px] text-muted-foreground italic">
              Intervalo pré-assinalado: batidas de almoço preservadas no registro.
            </span>
          )}
        </div>
      );
    }

    return (
      <div className="flex flex-col gap-1.5">
        {renderEscolha(data, ed)}
        <div className="flex flex-wrap items-start gap-2">
          {marcs.length === 0 && (
            <span className="text-[10px] text-muted-foreground italic py-1.5">Sem marcações</span>
          )}
          {marcs.map((_, i) => renderCampo(i))}
          <button
            type="button"
            onClick={() => adicionarMarcacao(data)}
            className="h-9 mt-[14px] px-2 text-[10px] rounded border border-dashed border-muted-foreground/40 text-muted-foreground hover:border-primary hover:text-primary shrink-0"
            title="Adicionar marcação"
          >
            + marcação
          </button>
        </div>
      </div>
    );
  };

  const renderSelectJust = (data: string, ed: DiaEdit, lista: JustificativaApp[], placeholder: string) => (
    <Select value={ed.justificativaId} onValueChange={(v) => patchDia(data, { justificativaId: v })}>
      <SelectTrigger className="h-9 text-xs w-full bg-background">
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent className="max-h-[50vh]">
        {lista.length === 0 && (
          <SelectItem value="__nenhuma__" disabled className="text-xs">Nenhum motivo liberado pelo RH</SelectItem>
        )}
        {lista.map((j) => (
          <SelectItem key={j.id} value={j.id} className="text-xs">{j.nome}</SelectItem>
        ))}
      </SelectContent>
    </Select>
  );

  const renderObservacao = (data: string, ed: DiaEdit) => (
    <Input
      value={ed.observacao}
      onChange={(e) => patchDia(data, { observacao: e.target.value.slice(0, MAX_OBS) })}
      placeholder="Observação (opcional)"
      className="h-9 text-xs bg-background"
      maxLength={MAX_OBS}
    />
  );

  const renderDetalhe = (data: string, ed: DiaEdit) => {
    if (ed.natureza === "correcao_batida") {
      return (
        <div className="space-y-1.5">
          {renderSelectJust(data, ed, justCorrecao, "Motivo da correção...")}
          {renderObservacao(data, ed)}
        </div>
      );
    }
    if (ed.natureza === "ausencia") {
      const aus = ed.ausencia;
      return (
        <div className="space-y-1.5 rounded-md border border-violet-200 bg-violet-50/50 dark:bg-violet-950/20 p-2">
          <label className="flex items-center gap-2 text-[11px] cursor-pointer">
            <Switch checked={aus.diaInteiro} onCheckedChange={(v) => patchAusencia(data, { diaInteiro: v })} />
            <span>Dia inteiro</span>
          </label>
          {!aus.diaInteiro && (
            <div className="flex items-center gap-2">
              <div className="flex flex-col">
                <span className="text-[9px] text-muted-foreground">Início</span>
                <Input type="time" value={aus.inicio} onChange={(e) => patchAusencia(data, { inicio: e.target.value })} className="h-8 text-xs font-mono w-[92px]" />
              </div>
              <div className="flex flex-col">
                <span className="text-[9px] text-muted-foreground">Fim</span>
                <Input type="time" value={aus.fim} onChange={(e) => patchAusencia(data, { fim: e.target.value })} className="h-8 text-xs font-mono w-[92px]" />
              </div>
            </div>
          )}
          {renderSelectJust(data, ed, justAusencia, "Motivo da ausência...")}
          {renderObservacao(data, ed)}
          <div>
            <Label className="text-[10px] flex items-center gap-1">
              <Paperclip className="w-3 h-3" /> Declaração ou atestado (obrigatório, até {MAX_FILES} de {MAX_FILE_MB}MB)
            </Label>
            <Input
              type="file"
              multiple
              accept="image/*,application/pdf"
              onChange={(e) => { patchAusencia(data, { files: filtrarArquivos(e.target.files, aus.files) }); e.target.value = ""; }}
              disabled={aus.files.length >= MAX_FILES}
              className="h-9 mt-1 text-xs"
            />
            {aus.files.length > 0 && (
              <ul className="mt-1 space-y-1">
                {aus.files.map((f, i) => (
                  <li key={i} className="flex items-center justify-between text-[11px] bg-background px-2 py-1 rounded">
                    <span className="truncate max-w-[220px]">{f.name}</span>
                    <button type="button" onClick={() => patchAusencia(data, { files: aus.files.filter((_, j) => j !== i) })} className="text-destructive">
                      <X className="w-3 h-3" />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      );
    }
    return <span className="text-[10px] text-muted-foreground">—</span>;
  };

  const temAlteracaoDia = (data: string, original: string[], ed: DiaEdit) =>
    ed.natureza === "ausencia" ||
    (ed.natureza === "correcao_batida" && ed.marcacoes !== undefined && (
      ed.marcacoes.length !== original.length ||
      ed.marcacoes.some((v, i) => (v || "") !== (original[i] || ""))
    )) ||
    (ed.natureza === "correcao_batida" && ed.marcacoes === undefined);

  const avisoLista = justStatus === "vazio"
    ? "Seu RH ainda não liberou os motivos de ajuste no app. Fale com o RH."
    : justStatus === "desatualizado"
      ? "O app está sendo atualizado. Tente de novo em instantes."
      : justStatus === "erro"
        ? "Não foi possível carregar os motivos de ajuste. Feche e abra de novo."
        : null;

  return (
    <Dialog open={open} onOpenChange={(v) => { onOpenChange(v); if (!v) reset(); }}>
      <DialogContent className="w-[95vw] max-w-[95vw] md:max-w-5xl h-[92vh] max-h-[92vh] flex flex-col overflow-hidden p-4 md:p-6 gap-3">
        {done ? (
          <div className="text-center space-y-3 py-6">
            <CheckCircle2 className="w-14 h-14 text-emerald-500 mx-auto" />
            <DialogTitle>Solicitação enviada!</DialogTitle>
            <DialogDescription>
              {totalEnviado === 1
                ? "Seu pedido foi registrado e ficará pendente para aprovação do gestor."
                : `Seus ${totalEnviado} pedidos foram registrados e ficarão pendentes para aprovação do gestor.`}
            </DialogDescription>
            <Button onClick={() => { onOpenChange(false); reset(); }} className="w-full">Fechar</Button>
          </div>
        ) : (
          <>
            <DialogHeader>
              <DialogTitle>Folha de Ponto · Ajustes</DialogTitle>
              <DialogDescription>
                Em cada dia, escolha <strong>Correção de batida</strong> (para corrigir ou incluir um horário que você
                trabalhou) ou <strong>Ausência</strong> (para um período em que você não trabalhou e tem declaração ou
                atestado — o documento é obrigatório). Tudo vai para o gestor de uma vez.
              </DialogDescription>
            </DialogHeader>

            {avisoLista && (
              <div className="flex items-center gap-2 text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-3 py-2 shrink-0">
                <AlertCircle className="w-4 h-4 shrink-0" /> {avisoLista}
              </div>
            )}

            <div className="flex-1 min-h-0 flex flex-col gap-3 overflow-hidden">
              {/* Navegação de mês */}
              <div className="flex items-center justify-between bg-muted/30 rounded-md px-3 py-2 shrink-0">
                <Button variant="ghost" size="sm" onClick={() => navegarMes(-1)} className="h-8">
                  <ChevronLeft className="w-4 h-4 mr-1" /> Mês anterior
                </Button>
                <span className="text-sm font-semibold capitalize">{mesLabel}</span>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => navegarMes(1)}
                  className="h-8"
                  disabled={mesAtivo >= `${hojeDate.getFullYear()}-${pad(hojeDate.getMonth()+1)}`}
                >
                  Próximo mês <ChevronRight className="w-4 h-4 ml-1" />
                </Button>
              </div>

              {/* Folha */}
              <div
                ref={scrollRef}
                className="flex-1 min-h-0 w-full overflow-x-auto overflow-y-auto border rounded-md ponto-scroll-visible"
              >
                <div className={`${isMobile ? "w-full" : "min-w-[760px] md:min-w-full"} min-h-full`}>
                  {loading ? (
                    <div className="flex items-center justify-center py-12">
                      <Loader2 className="w-5 h-5 animate-spin text-muted-foreground" />
                    </div>
                  ) : diasMes.length === 0 ? (
                    <p className="text-center text-sm text-muted-foreground py-8">Nenhum dia disponível neste mês.</p>
                  ) : isMobile ? (
                    <div className="divide-y">
                      {diasMes.map((data) => {
                        const original = marcsPorDia[data] || [];
                        const pendentes = pendentesPorDia[data] || [];
                        const ed = editDia(data);
                        const temAlteracao = !diaBloqueado(data) && temAlteracaoDia(data, original, ed);
                        const isWeekend = [0,6].includes(new Date(data + "T12:00:00").getDay());
                        return (
                          <div
                            key={data}
                            className={`p-3 space-y-2 ${ed.natureza === "ausencia" ? "bg-violet-50/40 dark:bg-violet-950/10" : temAlteracao ? "bg-primary/5" : isWeekend ? "bg-muted/20" : ""}`}
                          >
                            <div className="flex items-center gap-2">
                              <span className="font-mono font-semibold text-sm">{isoToBR(data).slice(0,5)}</span>
                              <span className="text-[11px] text-muted-foreground">{diaSemana(data)}</span>
                              {pendentes.length > 0 && (
                                <Badge variant="outline" className="text-[9px] border-amber-500 text-amber-700 dark:text-amber-400">
                                  {pendentes.length} pend.
                                </Badge>
                              )}
                            </div>
                            {renderMarcacoes(data, original, ed, pendentes.length)}
                            {temAlteracao && (
                              <div className="space-y-1.5">
                                <Label className="text-[11px]">{ed.natureza === "ausencia" ? "Ausência" : "Motivo da correção"}</Label>
                                {renderDetalhe(data, ed)}
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  ) : (
                    <table className="w-full text-[11px] table-fixed">
                    <thead className="bg-muted/50 sticky top-0 z-10">
                      <tr className="text-left">
                        <th className="px-2 py-2 font-medium w-[10%]">Dia</th>
                        <th className="px-1.5 py-2 font-medium w-[58%]">Marcações (Entrada / Saída)</th>
                        <th className="px-2 py-2 font-medium w-[32%]">Motivo</th>
                      </tr>
                    </thead>
                    <tbody>
                      {diasMes.map((data) => {
                        const original = marcsPorDia[data] || [];
                        const pendentes = pendentesPorDia[data] || [];
                        const ed = editDia(data);
                        const temAlteracao = !diaBloqueado(data) && temAlteracaoDia(data, original, ed);
                        const isWeekend = [0,6].includes(new Date(data + "T12:00:00").getDay());
                        return (
                          <tr
                            key={data}
                            className={`border-t ${ed.natureza === "ausencia" ? "bg-violet-50/40 dark:bg-violet-950/10" : temAlteracao ? "bg-primary/5" : isWeekend ? "bg-muted/20" : ""}`}
                          >
                            <td className="px-2 py-1.5 align-top">
                              <div className="font-mono font-semibold">{isoToBR(data).slice(0,5)}</div>
                              <div className="text-[10px] text-muted-foreground">{diaSemana(data)}</div>
                              {pendentes.length > 0 && (
                                <Badge variant="outline" className="text-[9px] mt-1 border-amber-500 text-amber-700 dark:text-amber-400">
                                  {pendentes.length} pend.
                                </Badge>
                              )}
                            </td>
                            <td className="px-1.5 py-1.5 align-top">
                              {renderMarcacoes(data, original, ed, pendentes.length)}
                            </td>
                            <td className="px-2 py-1.5 align-top">
                              {temAlteracao ? renderDetalhe(data, ed) : (
                                <span className="text-[10px] text-muted-foreground">—</span>
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                    </table>
                  )}
                </div>
              </div>
            </div>

            {/* Rodapé com anexos das correções, selfie e envio */}
            <div className="space-y-3 pt-3 border-t shrink-0 bg-background max-h-[40vh] overflow-y-auto">
              <div className="flex items-start justify-between gap-3 flex-wrap">
                {itensCorrecao.length > 0 && (
                  <div className="flex-1 min-w-[220px]">
                    <Label className="text-xs flex items-center gap-1">
                      <Paperclip className="w-3 h-3" /> Anexos das correções (opcional, até {MAX_FILES} de {MAX_FILE_MB}MB)
                    </Label>
                    <Input
                      type="file"
                      multiple
                      accept="image/*,application/pdf"
                      onChange={(e) => { setFiles(filtrarArquivos(e.target.files, files)); e.target.value = ""; }}
                      disabled={files.length >= MAX_FILES}
                      className="h-9 mt-1"
                    />
                    {files.length > 0 && (
                      <ul className="mt-1 space-y-1">
                        {files.map((f, i) => (
                          <li key={i} className="flex items-center justify-between text-xs bg-muted/50 px-2 py-1 rounded">
                            <span className="truncate max-w-[300px]">{f.name}</span>
                            <button type="button" onClick={() => setFiles(files.filter((_, j) => j !== i))} className="text-destructive">
                              <X className="w-3 h-3" />
                            </button>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                )}

                <div className="text-right space-y-1 ml-auto">
                  <div className="text-xs text-muted-foreground flex items-center gap-1 justify-end">
                    {totalAlteracoes > 0 ? (
                      <Badge variant="secondary" className="text-xs">
                        {itensCorrecao.length > 0 && `${itensCorrecao.length} correç${itensCorrecao.length !== 1 ? "ões" : "ão"}`}
                        {itensCorrecao.length > 0 && diasAusencia.length > 0 && " · "}
                        {diasAusencia.length > 0 && `${diasAusencia.length} ausência${diasAusencia.length !== 1 ? "s" : ""}`}
                      </Badge>
                    ) : (
                      <span className="flex items-center gap-1"><AlertCircle className="w-3 h-3" /> Nenhuma alteração ainda</span>
                    )}
                  </div>
                </div>
              </div>

              {exigirSelfie && totalAlteracoes > 0 && (
                <div className="max-w-sm mx-auto w-full">
                  <p className="text-[11px] text-muted-foreground text-center mb-1">
                    Sua empresa pede uma selfie para confirmar que é você quem está enviando o pedido.
                  </p>
                  <PontoSelfieCapture
                    selfieFile={selfieFile}
                    selfiePreview={selfiePreview}
                    onChange={(file, preview) => { setSelfieFile(file); setSelfiePreview(preview); }}
                    obrigatoria
                    abrirSozinha={false}
                  />
                </div>
              )}

              <div className="grid grid-cols-2 gap-2 mt-auto">
                <Button variant="outline" className="w-full" onClick={() => onOpenChange(false)}>Cancelar</Button>
                {/* O botão não fica desabilitado por falta de alteração: ele clica,
                    valida e DIZ o motivo. Só `enviando` bloqueia, para não enviar
                    duas vezes. */}
                <Button className="w-full" onClick={handleSubmit} disabled={enviando || !podeEnviar}>
                  {enviando ? <Loader2 className="w-4 h-4 animate-spin" /> : `Enviar (${totalAlteracoes || 0})`}
                </Button>
              </div>

            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
