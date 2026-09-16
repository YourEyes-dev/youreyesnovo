import { useState, useEffect, useCallback, useRef } from "react";
import { useParams } from "react-router-dom";
import { motion } from "framer-motion";
import { Clock, MapPin, LogIn, LogOut, CheckCircle2, AlertCircle, Loader2, Shield, FileEdit, IdCard, ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { supabasePublic } from "@/lib/supabasePublic";
import { useGeolocation } from "@/hooks/useGeolocation";
import { formatCpf, cleanCpf } from "@/lib/cpf";
import { PontoSelfieCapture } from "@/components/ponto/PontoSelfieCapture";
import { SolicitarAjusteModal } from "@/components/ponto/SolicitarAjusteModal";
import { PontoPWASetup } from "@/components/ponto/PontoPWASetup";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";

interface ColaboradorData {
  colaborador_nome: string;
  colaborador_cpf_parcial: string;
  tenant_id: string;
  colaborador_id: string;
  colaborador_cpf: string;
}

interface RegistroResult {
  success: boolean;
  colaborador_nome: string;
  tipo_marcacao: string;
  hora: string;
  data: string;
}

type TipoMarcacao = "entrada" | "saida";
type MarcacaoDia = { tipo: string; classe: "in" | "out"; hora: string };
type Modo = "colaborador" | "compartilhado" | null;

const TIPO_LABELS: Record<TipoMarcacao, { label: string; icon: React.ReactNode; color: string }> = {
  entrada: { label: "Entrada", icon: <LogIn className="w-5 h-5" />, color: "bg-emerald-500 hover:bg-emerald-600" },
  saida: { label: "Saída", icon: <LogOut className="w-5 h-5" />, color: "bg-rose-500 hover:bg-rose-600" },
};

const traduzirErroPonto = (mensagem?: string | null) => {
  const texto = (mensagem || "").trim();

  if (!texto) return "Não foi possível registrar o ponto agora. Tente novamente em instantes.";
  if (texto.includes('column "origem"')) return "Não foi possível concluir o registro de ponto agora. Tente novamente em instantes.";
  if (texto.includes("Link inválido") || texto.includes("expirado")) return "Link inválido ou expirado.";
  if (/tipo inválido/i.test(texto)) return "Use apenas Entrada ou Saída.";
  // O banco já devolve a mensagem pronta do anti-toque-duplo, com os segundos
  // que faltam. Não traduzir aqui — traduzir engoliria o tempo real.

  return texto;
};

const PontoExterno = () => {
  const { token } = useParams<{ token: string }>();
  const geo = useGeolocation();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [modo, setModo] = useState<Modo>(null);
  const [colaborador, setColaborador] = useState<ColaboradorData | null>(null);
  const [registrando, setRegistrando] = useState(false);
  const [resultado, setResultado] = useState<RegistroResult | null>(null);

  // Identificação por CPF (modo compartilhado)
  const [cpf, setCpf] = useState("");
  const [identificando, setIdentificando] = useState(false);

  // Selfie
  const [selfieFile, setSelfieFile] = useState<File | null>(null);
  const [selfiePreview, setSelfiePreview] = useState<string | null>(null);
  const [ajusteOpen, setAjusteOpen] = useState(false);

  // Clock
  const [currentTime, setCurrentTime] = useState(new Date());

  useEffect(() => {
    const interval = setInterval(() => setCurrentTime(new Date()), 1000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      (window.navigator as any).standalone === true;

    if (token) return;

    try {
      const savedPath = window.localStorage.getItem("ponto-pwa-path");
      const savedToken = window.localStorage.getItem("ponto-pwa-token");
      const fallbackPath = savedToken ? `/ponto-externo/${savedToken}` : null;
      const targetPath = savedPath || fallbackPath;

      if (targetPath && targetPath !== window.location.pathname) {
        window.location.replace(targetPath);
        return;
      }
    } catch {
      // Se não conseguir ler o storage, mantém o fluxo normal da página.
    }

    if (standalone) {
      setError("Abra novamente o link original de ponto para atualizar o atalho deste colaborador.");
      setLoading(false);
    }
  }, [token]);

  // Resolve o link: por-colaborador (legado) ou compartilhado (etapa CPF)
  useEffect(() => {
    if (!token) return;
    (async () => {
      setLoading(true);
      const { data, error } = await supabasePublic.rpc("buscar_ponto_link_por_token", { p_token: token });
      if (error || !data) {
        setError("Link inválido ou expirado.");
        setLoading(false);
        return;
      }
      const result = data as any;
      if (result.compartilhado) {
        setModo("compartilhado");
        setLoading(false);
        return;
      }
      if (result.error) {
        setError(result.error);
        setLoading(false);
        return;
      }
      setModo("colaborador");
      setColaborador(result);
      setLoading(false);
    })();
  }, [token]);

  // Próximo tipo a registrar (sequência CLT decidida pelo backend)
  const [proximoTipo, setProximoTipo] = useState<TipoMarcacao>("entrada");
  const [marcacoesDia, setMarcacoesDia] = useState<MarcacaoDia[]>([]);
  const [afastamento, setAfastamento] = useState<{ desde: string | null; ate: string | null } | null>(null);

  const carregarProximoTipo = useCallback(async () => {
    if (!token || !colaborador) return;
    const { data, error: rpcError } =
      modo === "compartilhado"
        ? await supabasePublic.rpc("proximo_tipo_marcacao_externo_cpf" as any, { p_token: token, p_cpf: cleanCpf(cpf) })
        : await supabasePublic.rpc("proximo_tipo_marcacao_externo", { p_token: token });
    if (rpcError) {
      setError(`Não foi possível atualizar o status do ponto: ${rpcError.message}`);
      return;
    }
    const r = data as any;
    if (r?.error) {
      setError(traduzirErroPonto(r.error));
      return;
    }
    if (r?.afastado) {
      setAfastamento({ desde: r.afastado_desde || null, ate: r.afastado_ate || null });
      return;
    }
    setAfastamento(null);
    if (r?.proximo === "entrada" || r?.proximo === "saida") {
      setProximoTipo(r.proximo);
    }
    if (Array.isArray(r?.marcacoes)) {
      setMarcacoesDia(r.marcacoes);
    }
  }, [token, colaborador, modo, cpf]);

  // Auto-capture geolocation + carrega próximo tipo quando há colaborador
  useEffect(() => {
    if (colaborador) {
      geo.capturarLocalizacao();
      carregarProximoTipo();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [colaborador]);

  // Revalida o próximo tipo ao voltar para o app (PWA reaberto / foco)
  useEffect(() => {
    if (!colaborador) return;
    const onVisible = () => {
      if (document.visibilityState === "visible") carregarProximoTipo();
    };
    const onFocus = () => carregarProximoTipo();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onFocus);
    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onFocus);
    };
  }, [colaborador, carregarProximoTipo]);

  // Identificação por CPF (modo compartilhado). Aceita um CPF opcional para a
  // identificação automática (CPF lembrado do aparelho).
  const CPF_STORAGE_KEY = token ? `ponto-cpf-${token}` : null;
  const identificarPorCpf = useCallback(async (cpfArg?: string) => {
    if (!token) return;
    const digits = cleanCpf(cpfArg ?? cpf);
    if (digits.length !== 11) {
      setError("Digite um CPF válido (11 dígitos).");
      return;
    }
    setIdentificando(true);
    setError(null);
    const { data, error: rpcError } = await supabasePublic.rpc("buscar_colaborador_por_cpf" as any, {
      p_token: token,
      p_cpf: digits,
    });
    setIdentificando(false);
    if (rpcError) {
      setError(traduzirErroPonto(rpcError.message));
      return;
    }
    const r = data as any;
    const encontrou = !!r && !r.error;

    // LGPD arts. 46-49 (PONTO-362): o link identifica por CPF, então tentar CPFs
    // em sequência é uma forma de descobrir quem trabalha aqui — e de marcar
    // ponto por terceiros. Cada tentativa é contada no próprio link; ao estourar
    // o limite, o link fica bloqueado por alguns minutos e o evento vai para a
    // trilha. Acerto zera o contador.
    let bloqueio: any = null;
    try {
      const { data: tent } = await supabasePublic.rpc("ponto_link_registrar_tentativa" as any, {
        p_token: token,
        p_cpf_tentado: digits,
        p_sucesso: encontrou,
      });
      bloqueio = tent as any;
    } catch {
      // A contenção não pode impedir quem é legítimo de bater o ponto.
    }

    if (bloqueio?.bloqueado) {
      setError(
        "Muitas tentativas com CPF que não confere. Por segurança, este link ficou bloqueado " +
        "por alguns minutos. Procure o RH se precisar registrar agora.",
      );
      return;
    }

    if (!encontrou) {
      setError(r?.error || "CPF não encontrado. Confira os números e tente novamente.");
      return;
    }
    // Lembra o CPF neste aparelho para não precisar redigitar nas próximas vezes.
    try { if (CPF_STORAGE_KEY) localStorage.setItem(CPF_STORAGE_KEY, digits); } catch { /* storage indisponível */ }
    setColaborador(r as ColaboradorData);
  }, [token, cpf, CPF_STORAGE_KEY]);

  // Ao abrir no modo compartilhado, se houver um CPF lembrado neste aparelho,
  // pré-preenche e identifica automaticamente (1x por carregamento).
  const autoIdentRef = useRef(false);
  useEffect(() => {
    if (modo !== "compartilhado" || colaborador || autoIdentRef.current || !CPF_STORAGE_KEY) return;
    let saved: string | null = null;
    try { saved = localStorage.getItem(CPF_STORAGE_KEY); } catch { /* storage indisponível */ }
    if (saved && cleanCpf(saved).length === 11) {
      autoIdentRef.current = true;
      setCpf(formatCpf(saved));
      identificarPorCpf(saved);
    }
  }, [modo, colaborador, CPF_STORAGE_KEY, identificarPorCpf]);

  // Volta para a etapa de CPF (aparelho compartilhado: próxima pessoa).
  // Esquece o CPF lembrado para não auto-identificar a pessoa anterior.
  const trocarColaborador = useCallback(() => {
    autoIdentRef.current = true;
    try { if (CPF_STORAGE_KEY) localStorage.removeItem(CPF_STORAGE_KEY); } catch { /* storage indisponível */ }
    setColaborador(null);
    setCpf("");
    setResultado(null);
    setError(null);
    setAfastamento(null);
    setMarcacoesDia([]);
    setProximoTipo("entrada");
    setSelfieFile(null);
    setSelfiePreview(null);
  }, [CPF_STORAGE_KEY]);

  const selfieObrigatoriaFaltando = modo === "compartilhado" && !selfieFile;

  const handleRegistrar = useCallback(async () => {
    if (!token || !colaborador || !proximoTipo) return;
    if (selfieObrigatoriaFaltando) {
      setError("Tire a selfie para registrar o ponto.");
      return;
    }
    setError(null);
    setRegistrando(true);
    try {
      // Sobe a selfie (se capturada) e obtém a URL pública — mesmo padrão do kiosk interno
      let selfieUrl: string | null = null;
      let selfieNome: string | null = null;
      if (selfieFile) {
        const fileName = `externo/${colaborador.colaborador_id}/${Date.now()}_${proximoTipo}.jpg`;
        const { data: uploadData, error: uploadError } = await supabasePublic.storage
          .from("ponto-selfies")
          .upload(fileName, selfieFile, { contentType: "image/jpeg" });
        if (!uploadError && uploadData) {
          const { data: urlData } = supabasePublic.storage.from("ponto-selfies").getPublicUrl(uploadData.path);
          selfieUrl = urlData.publicUrl;
          selfieNome = selfieFile.name || `selfie_${proximoTipo}.jpg`;
        }
        // Se o upload falhar, segue sem selfie no modo colaborador; no modo
        // compartilhado a selfie é obrigatória e o backend rejeita sem ela.
      }

      const { data, error } =
        modo === "compartilhado"
          ? await supabasePublic.rpc("registrar_ponto_externo_cpf" as any, {
              p_token: token,
              p_cpf: cleanCpf(cpf),
              p_tipo_marcacao: proximoTipo,
              p_latitude: geo.latitude,
              p_longitude: geo.longitude,
              p_endereco: geo.endereco,
              p_selfie_url: selfieUrl,
              p_selfie_nome: selfieNome,
            })
          : await supabasePublic.rpc("registrar_ponto_externo", {
              p_token: token,
              p_tipo_marcacao: proximoTipo,
              p_latitude: geo.latitude,
              p_longitude: geo.longitude,
              p_endereco: geo.endereco,
              p_selfie_url: selfieUrl,
              p_selfie_nome: selfieNome,
            });
      if (error) {
        setError(traduzirErroPonto(error.message));
        setRegistrando(false);
        return;
      }
      const result = data as any;
      if (result.error) {
        setError(traduzirErroPonto(result.error));
        setRegistrando(false);
        return;
      }
      setResultado(result);
      // Atualiza o próximo tipo IMEDIATAMENTE com base no que acabou de ser
      // registrado (entrada→saída, saída→entrada), sem depender da segunda
      // chamada assíncrona nem de timing/replicação.
      if (result.tipo_marcacao === "entrada") {
        setProximoTipo("saida");
      } else if (result.tipo_marcacao === "saida") {
        setProximoTipo("entrada");
      }
      carregarProximoTipo();
    } catch (e: any) {
      setError(traduzirErroPonto(e.message));
    }
    setRegistrando(false);
  }, [token, colaborador, modo, cpf, geo.latitude, geo.longitude, geo.endereco, selfieFile, proximoTipo, selfieObrigatoriaFaltando, carregarProximoTipo]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    );
  }

  // Erro de link só bloqueia quando NÃO é o passo de CPF do modo compartilhado
  if (error && !colaborador && modo !== "compartilhado") {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 p-4">
        <Card className="w-full max-w-md">
          <CardContent className="pt-6 text-center space-y-4">
            <AlertCircle className="w-12 h-12 text-destructive mx-auto" />
            <h2 className="text-xl font-bold">Link Inválido</h2>
            <p className="text-muted-foreground">{error}</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  // Modo compartilhado: etapa de identificação por CPF (antes do registro)
  if (modo === "compartilhado" && !colaborador) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 p-4 flex flex-col items-center justify-start pt-10 gap-6">
        <div className="text-center space-y-2">
          <h1 className="text-2xl font-bold text-white flex items-center justify-center gap-2">
            <Clock className="w-6 h-6 text-primary" /> Registro de Ponto
          </h1>
          <p className="text-slate-400 text-sm">Informe seu CPF para continuar</p>
        </div>
        <div className="text-center">
          <div className="text-4xl font-mono font-bold text-white tracking-wider">{format(currentTime, "HH:mm:ss")}</div>
          <p className="text-slate-400 text-sm mt-1">{format(currentTime, "EEEE, dd 'de' MMMM", { locale: ptBR })}</p>
        </div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="w-full max-w-md">
          <Card>
            <CardContent className="pt-6 space-y-4">
              <div className="flex items-center gap-2 text-sm font-medium">
                <IdCard className="w-5 h-5 text-primary" /> Identificação
              </div>
              <div className="space-y-1.5">
                <Input
                  inputMode="numeric"
                  autoComplete="off"
                  placeholder="000.000.000-00"
                  value={cpf}
                  onChange={(e) => { setCpf(formatCpf(e.target.value)); if (error) setError(null); }}
                  onKeyDown={(e) => { if (e.key === "Enter") identificarPorCpf(); }}
                  className="text-center text-lg font-mono h-12"
                  maxLength={14}
                />
                <p className="text-[11px] text-muted-foreground text-center">Use o CPF cadastrado na empresa.</p>
              </div>

              {error && (
                <div className="flex items-center gap-2 text-xs text-destructive bg-destructive/10 p-2 rounded-md">
                  <AlertCircle className="w-4 h-4 shrink-0" />
                  {error}
                </div>
              )}

              <Button
                className="w-full h-12 text-base font-semibold"
                disabled={identificando || cleanCpf(cpf).length !== 11}
                onClick={() => identificarPorCpf()}
              >
                {identificando ? <Loader2 className="w-5 h-5 mr-2 animate-spin" /> : null}
                Continuar
              </Button>
            </CardContent>
          </Card>
          <PontoPWASetup token={token} />
        </motion.div>

        <p className="text-slate-500 text-[10px] text-center max-w-xs">
          Identificação por CPF • Selfie obrigatória no registro • Geolocalização e horário capturados automaticamente
        </p>
      </div>
    );
  }

  if (resultado) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 p-4">
        <motion.div initial={{ scale: 0.8, opacity: 0 }} animate={{ scale: 1, opacity: 1 }}>
          <Card className="w-full max-w-md">
            <CardContent className="pt-6 text-center space-y-4">
              <CheckCircle2 className="w-16 h-16 text-emerald-500 mx-auto" />
              <h2 className="text-xl font-bold">Ponto Registrado!</h2>
              <div className="space-y-2 text-sm">
                <p><span className="text-muted-foreground">Colaborador:</span> <strong>{resultado.colaborador_nome}</strong></p>
                <p><span className="text-muted-foreground">Tipo:</span> <Badge>{TIPO_LABELS[resultado.tipo_marcacao]?.label || resultado.tipo_marcacao}</Badge></p>
                <p><span className="text-muted-foreground">Hora:</span> <strong className="font-mono text-lg">{resultado.hora?.substring(0, 5)}</strong></p>
                <p><span className="text-muted-foreground">Data:</span> {resultado.data}</p>
              </div>
              <div className="pt-2">
                <Badge variant="outline" className="text-xs">
                  <Shield className="w-3 h-3 mr-1" /> Registro auditável • Link externo
                </Badge>
              </div>
              <Button variant="outline" onClick={() => { setResultado(null); setError(null); setSelfieFile(null); setSelfiePreview(null); carregarProximoTipo(); }} className="w-full mt-4">
                Registrar outra marcação
              </Button>
              {modo === "compartilhado" && (
                <Button variant="ghost" onClick={trocarColaborador} className="w-full text-xs">
                  <ArrowLeft className="w-3.5 h-3.5 mr-1" /> Trocar colaborador
                </Button>
              )}
            </CardContent>
          </Card>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 p-4 flex flex-col items-center justify-start pt-8 gap-6">
      {/* Header */}
      <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} className="text-center space-y-2">
        <h1 className="text-2xl font-bold text-white flex items-center justify-center gap-2">
          <Clock className="w-6 h-6 text-primary" /> Registro de Ponto
        </h1>
        <p className="text-slate-400 text-sm">Registre sua marcação de forma segura</p>
      </motion.div>

      {/* Clock */}
      <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.1 }}
        className="text-center">
        <div className="text-5xl font-mono font-bold text-white tracking-wider">
          {format(currentTime, "HH:mm:ss")}
        </div>
        <p className="text-slate-400 text-sm mt-1">
          {format(currentTime, "EEEE, dd 'de' MMMM", { locale: ptBR })}
        </p>
      </motion.div>

      {/* Collaborator Card */}
      <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }} className="w-full max-w-md">
        <Card>
          <CardContent className="pt-4 space-y-3">
            <div className="text-center">
              <h3 className="font-semibold text-lg">{colaborador?.colaborador_nome}</h3>
              <p className="text-xs text-muted-foreground font-mono">{colaborador?.colaborador_cpf_parcial}</p>
            </div>

            {/* Selfie */}
            <PontoSelfieCapture
              selfieFile={selfieFile}
              selfiePreview={selfiePreview}
              onChange={(file, preview) => { setSelfieFile(file); setSelfiePreview(preview); }}
            />

            {/* Error */}
            {error && (
              <div className="flex items-center gap-2 text-xs text-destructive bg-destructive/10 p-2 rounded-md">
                <AlertCircle className="w-4 h-4 shrink-0" />
                {error}
                <Button variant="ghost" size="sm" className="ml-auto text-xs h-6" onClick={() => setError(null)}>OK</Button>
              </div>
            )}

            {afastamento ? (
              <div className="rounded-lg border border-sky-500/30 bg-sky-500/10 p-4 text-center space-y-1">
                <p className="text-sm font-semibold text-sky-700">🩺 Você está afastado(a)</p>
                <p className="text-xs text-muted-foreground">
                  {afastamento.ate
                    ? `Afastamento de ${afastamento.desde} até ${afastamento.ate}.`
                    : `Afastamento desde ${afastamento.desde} — em aberto.`}
                </p>
                <p className="text-xs text-muted-foreground">
                  Seus dias ficam <strong>abonados automaticamente</strong> no ponto. Não é necessário registrar marcações nem solicitar ajustes neste período.
                </p>
              </div>
            ) : (
            <>
            {/* Selfie obrigatória no modo compartilhado */}
            {selfieObrigatoriaFaltando && (
              <p className="text-[11px] text-amber-600 text-center">Tire a selfie acima para liberar o registro.</p>
            )}

            {/* Botão principal: próximo tipo pela alternância entrada/saída */}
            <Button
              className={`${TIPO_LABELS[proximoTipo].color} text-white h-16 w-full flex items-center justify-center gap-2 text-base font-semibold`}
              disabled={registrando || selfieObrigatoriaFaltando}
              onClick={handleRegistrar}
            >
              {registrando ? <Loader2 className="w-5 h-5 animate-spin" /> : TIPO_LABELS[proximoTipo].icon}
              Registrar {TIPO_LABELS[proximoTipo].label}
            </Button>

            {/* A próxima marcação alterna automaticamente: entrada ↔ saída */}
            <div className="grid grid-cols-2 gap-1.5 pt-1">
              {(["entrada", "saida"] as TipoMarcacao[]).map((tipo) => {
                const selecionado = tipo === proximoTipo;
                return (
                  <div
                    key={tipo}
                    className={`text-[11px] py-1.5 px-2 rounded-md border text-center transition-colors ${
                      selecionado
                        ? "border-primary bg-primary/10 text-primary font-semibold"
                        : "border-transparent bg-muted text-muted-foreground opacity-60"
                    }`}
                  >
                    {selecionado ? "→ " : ""}{TIPO_LABELS[tipo].label}
                  </div>
                );
              })}
            </div>

            {/* Marcações de hoje (suporta múltiplos ciclos entrada/saída) */}
            {marcacoesDia.length > 0 && (
              <div className="rounded-md border bg-muted/40 p-2.5 space-y-1">
                <p className="text-[11px] font-semibold text-muted-foreground uppercase tracking-wide">Suas marcações de hoje</p>
                <div className="flex flex-wrap gap-1.5">
                  {marcacoesDia.map((m, i) => (
                    <span
                      key={i}
                      className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                        m.classe === "in" ? "bg-emerald-500/15 text-emerald-600" : "bg-rose-500/15 text-rose-600"
                      }`}
                    >
                      {m.classe === "in" ? "↳ Entrada" : "↰ Saída"} {m.hora}
                    </span>
                  ))}
                </div>
                {proximoTipo === "saida" && (
                  <p className="text-[11px] text-muted-foreground">Jornada em aberto — não esqueça de registrar a saída.</p>
                )}
              </div>
            )}
            </>
            )}

            {/* Solicitar Ajuste */}
            {!afastamento && (
            <Button
              variant="outline"
              className="w-full mt-2 h-10 text-xs"
              onClick={() => setAjusteOpen(true)}
            >
              <FileEdit className="w-4 h-4 mr-2" /> Solicitar Ajuste de Ponto
            </Button>)}

            {/* Trocar colaborador (aparelho compartilhado) */}
            {modo === "compartilhado" && (
              <Button variant="ghost" className="w-full h-9 text-xs" onClick={trocarColaborador}>
                <ArrowLeft className="w-3.5 h-3.5 mr-1" /> Não sou eu / trocar colaborador
              </Button>
            )}

            {/* Instalar como app (PWA) - só fora do preview/iframe */}
            <PontoPWASetup token={token} />
          </CardContent>
        </Card>
      </motion.div>

      <p className="text-slate-500 text-[10px] text-center max-w-xs">
        Registro via link externo • Geolocalização e horário capturados automaticamente • Dados protegidos
      </p>

      {colaborador && (
        <SolicitarAjusteModal
          open={ajusteOpen}
          onOpenChange={setAjusteOpen}
          token={token!}
          cpf={modo === "compartilhado" ? cleanCpf(cpf) : undefined}
          colaboradorNome={colaborador.colaborador_nome}
        />
      )}
    </div>
  );
};

export default PontoExterno;
