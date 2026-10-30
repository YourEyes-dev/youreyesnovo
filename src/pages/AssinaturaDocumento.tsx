import { lazy, Suspense, useCallback, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { AlertCircle, CheckCircle2, FileText, Loader2, Mail, ShieldCheck, Camera } from "lucide-react";
import { TELA } from "@/lib/assinaturaTextos";
import {
  FINALIDADE_CONSENTIMENTO_BIOMETRICO,
  VERSAO_CONSENTIMENTO_BIOMETRICO,
} from "@/lib/assinaturaConsentimento";
import type { LivenessResultado } from "@/components/epi/entrega/LivenessDetection";

// A câmera (MediaPipe) só carrega quando o colaborador chega à prova de vida.
const LivenessDetection = lazy(() =>
  import("@/components/epi/entrega/LivenessDetection").then((m) => ({ default: m.LivenessDetection })),
);

/**
 * /assinar/:token — página pública da assinatura eletrônica (1º uso: Espelho
 * de Ponto). Sem login: a identidade é provada por CPF (conferido no servidor),
 * código de uso único enviado ao e-mail e prova de vida (ou a recusa registrada
 * da câmera). Tudo passa pela função de borda assinatura-documento; nada de
 * hash, IP ou hora sai daqui. Textos: src/lib/assinaturaTextos.ts.
 */
type Decisao = "assinado" | "assinado_com_ressalva" | "contestado";
type Etapa = "carregando" | "invalido" | "expirado" | "cancelado" | "bloqueado" | "cpf" | "codigo" | "prova" | "camera" | "decisao" | "concluido";

interface Estado {
  status: string;
  primeiro_nome: string | null;
  empresa: string | null;
  competencia_br: string;
  expira_em: string | null;
  tem_email: boolean;
  email_mascarado: string;
  bloqueado: boolean;
  etapas: { cpf: boolean; codigo: boolean; consentimento: boolean; prova_vida: boolean; sem_prova_vida: boolean };
}

const TOKEN_OK = /^[0-9a-f]{64}$/;

const MENSAGEM_ERRO: Record<string, string> = {
  cpf_nao_confere: "O CPF não confere com o cadastro.",
  bloqueado: TELA.bloqueado,
  codigo_nao_confere: "Código incorreto.",
  codigo_expirado: "O código expirou. Peça um novo.",
  codigo_bloqueado: "Muitas tentativas com este código. Peça um novo.",
  aguarde_um_minuto: "Aguarde um minuto para pedir outro código.",
  limite_de_codigos: "Limite de códigos atingido. Tente mais tarde.",
  email_falhou: "Não conseguimos enviar o e-mail agora. Tente de novo em instantes.",
  sem_email: TELA.semEmail,
  documento_alterado: "O documento não confere com o que foi enviado. Procure o RH.",
  expirado: TELA.expiradoTexto,
  sem_prova_vida: "Falta a confirmação de presença.",
  texto_obrigatorio: "Descreva a ressalva ou o motivo.",
};

async function chamar(token: string, acao: string, extra: Record<string, unknown> = {}) {
  const { data, error } = await supabase.functions.invoke("assinatura-documento", {
    body: { token, acao, ...extra },
  });
  if (error) {
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      try {
        return (await ctx.json()) as Record<string, any>;
      } catch {
        /* sem corpo */
      }
    }
    return { ok: false, erro: "falha_de_rede" } as Record<string, any>;
  }
  return data as Record<string, any>;
}

function lerGeolocalizacao(): Promise<{ lat: number; lng: number; precisao: number } | null> {
  return new Promise((resolve) => {
    if (!("geolocation" in navigator)) return resolve(null);
    const t = setTimeout(() => resolve(null), 6000);
    navigator.geolocation.getCurrentPosition(
      (p) => { clearTimeout(t); resolve({ lat: p.coords.latitude, lng: p.coords.longitude, precisao: p.coords.accuracy }); },
      () => { clearTimeout(t); resolve(null); },
      { enableHighAccuracy: false, timeout: 5000, maximumAge: 60000 },
    );
  });
}

export default function AssinaturaDocumento() {
  const { token = "" } = useParams();
  const [etapa, setEtapa] = useState<Etapa>("carregando");
  const [estado, setEstado] = useState<Estado | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [cpf, setCpf] = useState("");
  const [urlDoc, setUrlDoc] = useState<string | null>(null);
  const [lido, setLido] = useState(false);
  const [codigoEnviado, setCodigoEnviado] = useState(false);
  const [codigo, setCodigo] = useState("");
  const [aceite, setAceite] = useState(false);
  const [recusando, setRecusando] = useState(false);
  const [decisao, setDecisao] = useState<Decisao>("assinado");
  const [texto, setTexto] = useState("");
  const [resultado, setResultado] = useState<string | null>(null);

  const definirEtapa = useCallback((e: Estado) => {
    if (e.status === "expirado") return setEtapa("expirado");
    if (e.status === "cancelado") return setEtapa("cancelado");
    if (["assinado", "assinado_com_ressalva", "contestado"].includes(e.status)) return setEtapa("concluido");
    if (e.bloqueado) return setEtapa("bloqueado");
    if (!e.etapas.cpf) return setEtapa("cpf");
    if (!e.etapas.codigo) return setEtapa("codigo");
    if (!e.etapas.prova_vida && !e.etapas.sem_prova_vida) return setEtapa(e.etapas.consentimento ? "camera" : "prova");
    return setEtapa("decisao");
  }, []);

  useEffect(() => {
    if (!TOKEN_OK.test(token)) {
      setEtapa("invalido");
      return;
    }
    (async () => {
      const r = await chamar(token, "abrir");
      if (!r?.ok) {
        setEtapa("invalido");
        return;
      }
      setEstado(r as unknown as Estado);
      definirEtapa(r as unknown as Estado);
      if (r.etapas?.cpf && ["enviado", "visualizado"].includes(r.status)) {
        const d = await chamar(token, "documento");
        if (d?.ok) { setUrlDoc(d.url_documento); setLido(true); }
      }
    })();
  }, [token, definirEtapa]);

  const falhou = (r: Record<string, any> | null, padrao = "Não foi possível concluir.") => {
    setErro(MENSAGEM_ERRO[r?.erro] || (r?.restantes !== undefined ? `${MENSAGEM_ERRO[r?.erro] || padrao} Restam ${r.restantes} tentativa(s).` : padrao));
    if (r?.erro === "bloqueado") setEtapa("bloqueado");
  };

  const enviarCpf = async () => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "cpf", { cpf });
    setOcupado(false);
    if (!r?.ok) {
      const base = MENSAGEM_ERRO[r?.erro] || "Não foi possível conferir o CPF.";
      setErro(r?.restantes !== undefined ? `${base} Restam ${r.restantes} tentativa(s).` : base);
      if (r?.erro === "bloqueado") setEtapa("bloqueado");
      return;
    }
    setUrlDoc(r.url_documento);
    setEstado((e) => (e ? { ...e, etapas: { ...e.etapas, cpf: true } } : e));
    setEtapa("codigo");
  };

  const pedirCodigo = async () => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "otp_enviar");
    setOcupado(false);
    if (!r?.ok) return falhou(r, "Não foi possível enviar o código.");
    setCodigoEnviado(true);
  };

  const validarCodigo = async () => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "otp_validar", { codigo });
    setOcupado(false);
    if (!r?.ok) {
      const base = MENSAGEM_ERRO[r?.erro] || "Código incorreto.";
      setErro(r?.restantes !== undefined ? `${base} Restam ${r.restantes} tentativa(s).` : base);
      return;
    }
    setEtapa("prova");
  };

  const aceitarCamera = async () => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "consentimento", {
      versao_texto: VERSAO_CONSENTIMENTO_BIOMETRICO,
      finalidade: FINALIDADE_CONSENTIMENTO_BIOMETRICO,
    });
    setOcupado(false);
    if (!r?.ok) return falhou(r);
    setEtapa("camera");
  };

  const recusarCamera = async () => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "consentimento", { recusou: true, versao_texto: VERSAO_CONSENTIMENTO_BIOMETRICO });
    setOcupado(false);
    if (!r?.ok) return falhou(r);
    setEstado((e) => (e ? { ...e, etapas: { ...e.etapas, sem_prova_vida: true } } : e));
    setEtapa("decisao");
  };

  const aoConcluirCamera = async (d: LivenessResultado) => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "evidencia", {
      frames: (d.frames || []).slice(-4),
      metodo_liveness: d.metodo,
      versao_detector: d.versao_do_detector || null,
      liveness_data: { actions: d.actions, timestamps: d.timestamps, detalhes: d.detalhes, tentativas_sem_sucesso: d.tentativas_sem_sucesso },
    });
    setOcupado(false);
    if (!r?.ok) return falhou(r, "Não foi possível guardar a verificação. Tente de novo.");
    setEtapa("decisao");
  };

  const responder = async () => {
    setOcupado(true); setErro(null);
    const geolocalizacao = await lerGeolocalizacao();
    const r = await chamar(token, "responder", { decisao, texto, geolocalizacao });
    setOcupado(false);
    if (!r?.ok) return falhou(r, "Não foi possível registrar a resposta.");
    setResultado(r.status);
    setEtapa("concluido");
  };

  const verVia = async () => {
    setOcupado(true); setErro(null);
    const r = await chamar(token, "via", { cpf });
    setOcupado(false);
    if (!r?.ok || !r.url) return falhou(r, "Informe o CPF para ver a sua via.");
    window.open(r.url, "_blank", "noopener,noreferrer");
  };

  const cabecalho = estado && (
    <div className="space-y-1">
      <h1 className="text-xl font-semibold flex items-center gap-2"><FileText className="h-5 w-5 text-primary" /> {TELA.titulo}</h1>
      <p className="text-sm text-muted-foreground">
        {estado.empresa ? `${estado.empresa} · ` : ""}Competência {estado.competencia_br}
        {estado.primeiro_nome ? ` · ${estado.primeiro_nome}` : ""}
      </p>
    </div>
  );

  const aviso = erro && (
    <div className="flex items-center gap-2 rounded-md bg-destructive/10 p-3 text-sm text-destructive" role="alert">
      <AlertCircle className="h-4 w-4 shrink-0" /> <span>{erro}</span>
    </div>
  );

  const telaSimples = (titulo: string, textoTela: string) => (
    <div className="min-h-screen bg-background p-4 flex items-center justify-center">
      <Card className="max-w-md w-full p-6 space-y-3 text-center">
        <AlertCircle className="h-8 w-8 mx-auto text-muted-foreground" />
        <h1 className="text-lg font-semibold">{titulo}</h1>
        <p className="text-sm text-muted-foreground">{textoTela}</p>
      </Card>
    </div>
  );

  if (etapa === "carregando") {
    return <div className="min-h-screen flex items-center justify-center"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>;
  }
  if (etapa === "invalido") return telaSimples(TELA.linkInvalido, TELA.linkInvalidoTexto);
  if (etapa === "expirado") return telaSimples(TELA.expirado, TELA.expiradoTexto);
  if (etapa === "cancelado") return telaSimples(TELA.cancelado, TELA.canceladoTexto);
  if (etapa === "bloqueado") return telaSimples("Link bloqueado", TELA.bloqueado);

  return (
    <div className="min-h-screen bg-background p-4">
      <div className="mx-auto max-w-3xl space-y-4">
        {cabecalho}

        {etapa === "concluido" ? (
          <Card className="p-6 space-y-3">
            <div className="flex items-center gap-2 text-green-700">
              <CheckCircle2 className="h-6 w-6" /> <h2 className="text-lg font-semibold">{TELA.concluidoAssinado}</h2>
            </div>
            <p className="text-sm text-muted-foreground">{TELA.concluidoTexto}</p>
            {(resultado || estado?.status) !== "contestado" && (
              <div className="space-y-2">
                <Label htmlFor="cpf-via">Para ver a sua via, informe o seu CPF</Label>
                <div className="flex gap-2">
                  <Input id="cpf-via" inputMode="numeric" value={cpf} onChange={(e) => setCpf(e.target.value)} placeholder="000.000.000-00" />
                  <Button onClick={verVia} disabled={ocupado || cpf.replace(/\D/g, "").length !== 11}>Ver minha via</Button>
                </div>
              </div>
            )}
            {aviso}
          </Card>
        ) : (
          <>
            <p className="text-sm text-muted-foreground">{TELA.introducao}</p>

            {etapa === "cpf" && (
              <Card className="p-6 space-y-3">
                <Label htmlFor="cpf">{TELA.pedirCpf}</Label>
                <div className="flex gap-2">
                  <Input id="cpf" inputMode="numeric" autoComplete="off" value={cpf} onChange={(e) => setCpf(e.target.value)} placeholder="000.000.000-00" />
                  <Button onClick={enviarCpf} disabled={ocupado || cpf.replace(/\D/g, "").length !== 11}>
                    {ocupado ? <Loader2 className="h-4 w-4 animate-spin" /> : "Continuar"}
                  </Button>
                </div>
                {aviso}
              </Card>
            )}

            {urlDoc && etapa !== "cpf" && (
              <Card className="p-2">
                <iframe title="Documento para assinatura" src={`${urlDoc}#toolbar=0&navpanes=0`} className="h-[60vh] w-full rounded" />
                <label className="flex items-center gap-2 p-3 text-sm">
                  <Checkbox checked={lido} onCheckedChange={(v) => setLido(v === true)} /> {TELA.marcarLido}
                </label>
              </Card>
            )}

            {etapa === "codigo" && lido && (
              <Card className="p-6 space-y-3">
                {!estado?.tem_email ? (
                  <p className="text-sm text-destructive">{TELA.semEmail}</p>
                ) : !codigoEnviado ? (
                  <Button onClick={pedirCodigo} disabled={ocupado}>
                    <Mail className="h-4 w-4 mr-2" /> Enviar código para {estado.email_mascarado}
                  </Button>
                ) : (
                  <>
                    <Label htmlFor="codigo">{TELA.pedirCodigo(estado.email_mascarado)}</Label>
                    <div className="flex gap-2">
                      <Input id="codigo" inputMode="numeric" maxLength={6} value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ""))} />
                      <Button onClick={validarCodigo} disabled={ocupado || codigo.length !== 6}>Confirmar</Button>
                    </div>
                    <Button variant="link" className="px-0" onClick={pedirCodigo} disabled={ocupado}>Enviar outro código</Button>
                  </>
                )}
                {aviso}
              </Card>
            )}

            {etapa === "prova" && (
              <Card className="p-6 space-y-3">
                <h2 className="font-semibold flex items-center gap-2"><ShieldCheck className="h-5 w-5 text-primary" /> {TELA.provaDeVidaTitulo}</h2>
                <p className="text-sm text-muted-foreground">{TELA.provaDeVidaTexto}</p>
                <p className="text-sm"><strong>Finalidade:</strong> {FINALIDADE_CONSENTIMENTO_BIOMETRICO}</p>
                {!recusando ? (
                  <>
                    <label className="flex items-start gap-3 rounded-md border p-3 text-sm">
                      <Checkbox checked={aceite} onCheckedChange={(v) => setAceite(v === true)} className="mt-0.5" />
                      <span>Li e concordo com o uso da câmera para confirmar a minha identidade nesta assinatura.</span>
                    </label>
                    <div className="flex flex-col gap-2 sm:flex-row">
                      <Button onClick={aceitarCamera} disabled={!aceite || ocupado}><Camera className="h-4 w-4 mr-2" /> Concordar e abrir a câmera</Button>
                      <Button variant="outline" onClick={() => setRecusando(true)} disabled={ocupado}>{TELA.recusarCamera}</Button>
                    </div>
                  </>
                ) : (
                  <>
                    <p className="text-sm rounded-md bg-amber-50 border border-amber-200 p-3 text-amber-900">{TELA.recusarCameraAviso}</p>
                    <div className="flex flex-col gap-2 sm:flex-row">
                      <Button onClick={recusarCamera} disabled={ocupado}>Continuar sem a câmera</Button>
                      <Button variant="outline" onClick={() => setRecusando(false)} disabled={ocupado}>Voltar</Button>
                    </div>
                  </>
                )}
                {aviso}
              </Card>
            )}

            {etapa === "camera" && (
              <Suspense fallback={<div className="flex justify-center p-6"><Loader2 className="h-6 w-6 animate-spin" /></div>}>
                {ocupado ? (
                  <div className="flex items-center justify-center gap-2 p-6 text-sm text-muted-foreground">
                    <Loader2 className="h-5 w-5 animate-spin" /> Guardando a verificação...
                  </div>
                ) : (
                  <LivenessDetection onComplete={aoConcluirCamera} onError={(m) => setErro(m)} />
                )}
                {aviso}
              </Suspense>
            )}

            {etapa === "decisao" && (
              <Card className="p-6 space-y-4">
                <h2 className="font-semibold">{TELA.decisaoTitulo}</h2>
                <div className="space-y-2">
                  {(Object.keys(TELA.decisoes) as Decisao[]).map((k) => (
                    <label key={k} className={`flex items-start gap-3 rounded-md border p-3 text-sm cursor-pointer ${decisao === k ? "border-primary bg-primary/5" : ""}`}>
                      <input type="radio" name="decisao" className="mt-1" checked={decisao === k} onChange={() => setDecisao(k)} />
                      <span>
                        <strong>{TELA.decisoes[k].rotulo}</strong>
                        <span className="block text-muted-foreground">{TELA.decisoes[k].declaracao}</span>
                      </span>
                    </label>
                  ))}
                </div>
                {decisao !== "assinado" && (
                  <div className="space-y-1">
                    <Label htmlFor="texto">{decisao === "contestado" ? TELA.decisoes.contestado.campo : TELA.decisoes.assinado_com_ressalva.campo}</Label>
                    <Textarea id="texto" rows={3} value={texto} onChange={(e) => setTexto(e.target.value)} />
                  </div>
                )}
                {estado?.etapas.sem_prova_vida && (
                  <p className="text-xs text-muted-foreground">Registro sem prova de vida (você recusou a câmera).</p>
                )}
                <Button onClick={responder} disabled={ocupado || !lido || (decisao !== "assinado" && !texto.trim())}>
                  {ocupado ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                  {TELA.decisoes[decisao].rotulo}
                </Button>
                {!lido && <p className="text-xs text-muted-foreground">Marque que leu o espelho para responder.</p>}
                {aviso}
              </Card>
            )}
          </>
        )}
        <p className="text-center text-xs text-muted-foreground">{TELA.rodape}</p>
      </div>
    </div>
  );
}
