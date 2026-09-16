import { useEffect, useRef, useState, useCallback } from "react";
import { useParams } from "react-router-dom";
import { supabasePublic } from "@/lib/supabasePublic";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Loader2, CheckCircle2, AlertCircle, Shield, MapPin, Camera, RefreshCw, Eraser, Building2 } from "lucide-react";
import { buscarCnpj, formatCnpj, cleanCnpj } from "@/lib/brasilapi";
import SignatureCanvas from "react-signature-canvas";
import { toast } from "sonner";
import logoImage from "@/assets/logo-youreyes.svg";
import { Link } from "react-router-dom";

interface ContratoInfo {
  id: string;
  titulo: string;
  categoria: string;
  descricao_publica: string | null;
  corpo_html: string;
  versao: number;
  requer_cpf: boolean;
  requer_rg: boolean;
  requer_endereco: boolean;
  requer_telefone: boolean;
  requer_selfie: boolean;
  requer_geolocalizacao: boolean;
  requer_cnpj: boolean;
  requer_razao_social: boolean;
  requer_representante: boolean;
}

async function sha256(text: string): Promise<string> {
  const buf = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("");
}

export default function AssinarContrato() {
  const { token } = useParams<{ token: string }>();
  const [loading, setLoading] = useState(true);
  const [contrato, setContrato] = useState<ContratoInfo | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [signatarioEmail, setSignatarioEmail] = useState<string>("");

  const [nome, setNome] = useState("");
  const [cpf, setCpf] = useState("");
  const [email, setEmail] = useState("");
  const [telefone, setTelefone] = useState("");
  const [rg, setRg] = useState("");
  const [endereco, setEndereco] = useState("");
  const [aceito, setAceito] = useState(false);
  const [selfie, setSelfie] = useState<string | null>(null);
  const [geo, setGeo] = useState<{ lat: number; lng: number } | null>(null);
  const [enviando, setEnviando] = useState(false);
  const [buscandoCnpj, setBuscandoCnpj] = useState(false);
  const [cnpj, setCnpj] = useState("");
  const [razaoSocial, setRazaoSocial] = useState("");
  const [representante, setRepresentante] = useState("");
  const [sucesso, setSucesso] = useState(false);
  // Contrato de Parceria: leva o parceiro de volta à Área do Parceiro depois de assinar
  const [parceiro, setParceiro] = useState(false);

  // Signature
  const sigRef = useRef<SignatureCanvas>(null);
  const sigBoxRef = useRef<HTMLDivElement>(null);
  const [sigWidth, setSigWidth] = useState(600);
  const [hasSig, setHasSig] = useState(false);

  // Camera
  const videoRef = useRef<HTMLVideoElement>(null);
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [camOpen, setCamOpen] = useState(false);
  const [camError, setCamError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      if (!token) return;
      const { data, error } = await supabasePublic.rpc("obter_contrato_publico" as any, { _token: token });
      setLoading(false);
      if (error) { setErro("Erro ao carregar contrato"); return; }
      const result = data as any;
      if (result?.erro) {
        if (result.parceiro_id) setParceiro(true);
        const map: Record<string, string> = {
          token_invalido: "Link inválido ou expirado.",
          ja_assinado: "Este contrato já foi assinado.",
          revogado: "Este link foi revogado.",
          expirado: "Este link expirou.",
          contrato_inativo: "Este contrato não está mais disponível.",
          limite_atingido: "Limite de assinaturas atingido.",
        };
        setErro(map[result.erro] || "Não foi possível abrir o contrato.");
        return;
      }
      setContrato(result.contrato);
      setParceiro(!!result.assinatura?.parceiro_id);
      setSignatarioEmail(result.assinatura?.signatario_email || "");
      if (result.assinatura?.signatario_cpf) setCpf(result.assinatura.signatario_cpf);
      if (result.assinatura?.signatario_telefone) setTelefone(result.assinatura.signatario_telefone);
      if (result.assinatura?.signatario_endereco) setEndereco(result.assinatura.signatario_endereco);
      if (result.assinatura?.signatario_cnpj) setCnpj(result.assinatura.signatario_cnpj);
      if (result.assinatura?.signatario_razao_social) setRazaoSocial(result.assinatura.signatario_razao_social);
      if (result.assinatura?.signatario_email) setEmail(result.assinatura.signatario_email);
      if (result.assinatura?.signatario_nome) setNome(result.assinatura.signatario_nome);
    })();
  }, [token]);

  // Responsive signature width
  useEffect(() => {
    const update = () => {
      if (sigBoxRef.current) setSigWidth(sigBoxRef.current.clientWidth);
    };
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, [contrato]);

  // Attach stream when video mounts
  useEffect(() => {
    if (camOpen && stream && videoRef.current) {
      videoRef.current.srcObject = stream;
      videoRef.current.play().catch(() => {});
    }
  }, [camOpen, stream]);

  // Cleanup camera on unmount
  useEffect(() => {
    return () => { stream?.getTracks().forEach(t => t.stop()); };
  }, [stream]);

  // Localização: pedida sozinha ao abrir (quando exigida) e de novo na hora de
  // assinar, para o signatário não precisar achar um botão à parte.
  const [geoErro, setGeoErro] = useState<string | null>(null);
  const [geoBuscando, setGeoBuscando] = useState(false);
  const obterGeo = useCallback((): Promise<{ lat: number; lng: number } | null> => new Promise(resolve => {
    if (!navigator.geolocation) { setGeoErro("Este navegador não oferece localização."); resolve(null); return; }
    setGeoBuscando(true); setGeoErro(null);
    navigator.geolocation.getCurrentPosition(
      p => { const g = { lat: p.coords.latitude, lng: p.coords.longitude }; setGeo(g); setGeoBuscando(false); resolve(g); },
      e => {
        setGeoBuscando(false);
        setGeoErro(e.code === 1
          ? "Permissão de localização negada. Clique no ícone de cadeado/localização na barra de endereço, permita a localização e tente de novo."
          : e.code === 2 ? "Localização indisponível no dispositivo. Verifique se o GPS/serviço de localização está ligado."
          : "Tempo esgotado ao obter a localização. Tente de novo.");
        resolve(null);
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }
    );
  }), []);
  const capturarGeo = async () => { const g = await obterGeo(); if (g) toast.success("Localização capturada"); };
  useEffect(() => { if (contrato?.requer_geolocalizacao && !geo) void obterGeo(); }, [contrato?.requer_geolocalizacao]); // eslint-disable-line react-hooks/exhaustive-deps

  const iniciarCamera = useCallback(async () => {
    setCamError(null);
    if (!navigator.mediaDevices?.getUserMedia) {
      setCamError("Câmera não disponível neste navegador. Em iPhone use Safari e em Android use Chrome.");
      return;
    }
    if (window.location.protocol !== "https:" && window.location.hostname !== "localhost") {
      setCamError("Câmera requer conexão segura (HTTPS).");
      return;
    }
    try {
      const s = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false,
      });
      setStream(s);
      setCamOpen(true);
    } catch (e: any) {
      const msg = e?.name === "NotAllowedError"
        ? "Permissão negada. Autorize o uso da câmera nas configurações do navegador."
        : e?.name === "NotFoundError"
        ? "Nenhuma câmera encontrada no dispositivo."
        : "Não foi possível acessar a câmera.";
      setCamError(msg);
    }
  }, []);

  const pararCamera = useCallback(() => {
    stream?.getTracks().forEach(t => t.stop());
    setStream(null);
    setCamOpen(false);
  }, [stream]);

  const capturarSelfie = useCallback(() => {
    const v = videoRef.current;
    if (!v || !v.videoWidth) return;
    const canvas = document.createElement("canvas");
    canvas.width = v.videoWidth;
    canvas.height = v.videoHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(v, 0, 0);
    setSelfie(canvas.toDataURL("image/jpeg", 0.8));
    pararCamera();
    toast.success("Selfie capturada");
  }, [pararCamera]);

  const handleCnpjLookup = async (value: string) => {
    const cleaned = cleanCnpj(value);
    setCnpj(formatCnpj(cleaned));
    
    if (cleaned.length === 14) {
      setBuscandoCnpj(true);
      try {
        const data = await buscarCnpj(cleaned);
        if (data?.razao_social) {
          setRazaoSocial(data.razao_social);
          if (data.logradouro) {
            setEndereco(`${data.logradouro}, ${data.numero}${data.complemento ? ` - ${data.complemento}` : ""} - ${data.bairro}, ${data.municipio} - ${data.uf}, ${data.cep}`);
          }
          toast.success("Dados da empresa localizados");
        }
      } catch (error) {
        console.error("Erro ao buscar CNPJ:", error);
      } finally {
        setBuscandoCnpj(false);
      }
    }
  };

  const limparAssinatura = () => { sigRef.current?.clear(); setHasSig(false); };

  const handleEnviar = async () => {
    if (!contrato || !token) return;
    if (!aceito) { toast.error("Você precisa concordar com os termos"); return; }
    if (!nome.trim()) { toast.error("Informe seu nome"); return; }
    if (contrato.requer_cpf && !cpf.trim()) { toast.error("CPF obrigatório"); return; }
    if (contrato.requer_cnpj && !cnpj.trim()) { toast.error("CNPJ obrigatório"); return; }
    if (contrato.requer_razao_social && !razaoSocial.trim()) { toast.error("Razão Social obrigatória"); return; }
    if (contrato.requer_representante && !representante.trim()) { toast.error("Nome do representante legal obrigatório"); return; }
    if (contrato.requer_telefone && !telefone.trim()) { toast.error("Telefone obrigatório"); return; }
    if (contrato.requer_rg && !rg.trim()) { toast.error("RG obrigatório"); return; }
    if (contrato.requer_endereco && !endereco.trim()) { toast.error("Endereço obrigatório"); return; }
    if (contrato.requer_selfie && !selfie) { toast.error("Selfie obrigatória"); return; }
    let geoFinal = geo;
    if (contrato.requer_geolocalizacao && !geoFinal) {
      geoFinal = await obterGeo();   // tenta de novo antes de barrar
      if (!geoFinal) { toast.error("Precisamos da sua localização para registrar a assinatura", { description: "Permita a localização no navegador e clique em Assinar novamente." }); return; }
    }
    if (!sigRef.current || sigRef.current.isEmpty()) { toast.error("Assine no campo abaixo"); return; }

    const assinatura = sigRef.current.toDataURL("image/png");

    setEnviando(true);
    try {
      const hash = await sha256(
        `${contrato.id}|${contrato.versao}|${contrato.corpo_html}|${nome}|${cpf}|${email}|${Date.now()}`
      );

      let ip: string | null = null;
      try {
        const r = await fetch("https://api.ipify.org?format=json");
        ip = (await r.json()).ip;
      } catch {}

      const { data, error } = await supabasePublic.rpc("registrar_assinatura_contrato" as any, {
        _token: token,
        _nome: nome,
        _cpf: cpf || null,
        _email: email || null,
        _telefone: telefone || null,
        _rg: rg || null,
        _endereco: endereco || null,
        _assinatura_imagem: assinatura,
        _selfie_imagem: selfie,
        _ip: ip,
        _user_agent: navigator.userAgent,
        _geo_lat: geoFinal?.lat ?? null,
        _geo_lng: geoFinal?.lng ?? null,
        _hash: hash,
        _cnpj: cnpj || null,
        _razao_social: razaoSocial || null,
        _representante: representante || null,
      });
      if (error) throw error;
      const result = data as any;
      if (!result.ok) {
        toast.error(result.erro === "ja_assinado" ? "Contrato já foi assinado" : "Erro ao registrar assinatura");
        return;
      }
      setSucesso(true);
    } catch (e: any) {
      toast.error(e.message || "Erro ao enviar assinatura");
    } finally {
      setEnviando(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    );
  }

  if (erro) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-6">
        <Card className="max-w-md w-full">
          <CardContent className="pt-6 text-center space-y-4">
            <img src={logoImage} alt="YourEyes" className="h-10 mx-auto" />
            <AlertCircle className="w-16 h-16 mx-auto text-destructive" />
            <h1 className="text-xl font-semibold">Não foi possível abrir o contrato</h1>
            <p className="text-muted-foreground">{erro}</p>
            {parceiro && <Button asChild variant="outline"><Link to="/parceiro">Ir para a Área do Parceiro</Link></Button>}
          </CardContent>
        </Card>
      </div>
    );
  }

  if (sucesso) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background p-6">
        <Card className="max-w-md w-full">
          <CardContent className="pt-6 text-center space-y-4">
            <img src={logoImage} alt="YourEyes" className="h-10 mx-auto" />
            <CheckCircle2 className="w-16 h-16 mx-auto text-emerald-500" />
            <h1 className="text-2xl font-semibold">Contrato assinado!</h1>
            <p className="text-muted-foreground">
              Sua assinatura foi registrada com sucesso e tem validade jurídica conforme Lei 14.063/2020.
            </p>
            {parceiro ? (
              <>
                <p className="text-sm text-muted-foreground">Seu Contrato de Parceria está assinado e guardado pela YourEyes. Bem-vindo(a) ao programa!</p>
                <Button asChild className="w-full" data-testid="assinatura-voltar-portal"><Link to="/parceiro">Ir para a Área do Parceiro</Link></Button>
              </>
            ) : (
              <p className="text-xs text-muted-foreground">Você pode fechar esta janela.</p>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!contrato) return null;

  return (
    <div className="min-h-screen bg-gradient-to-b from-background to-muted/30 py-6 px-4">
      <div className="max-w-3xl mx-auto space-y-5">
        <div className="text-center pt-2 pb-4">
          <img src={logoImage} alt="YourEyes" className="h-12 mx-auto mb-4" />
          <h1 className="text-2xl md:text-3xl font-bold text-foreground break-words">{contrato.titulo}</h1>
          {contrato.descricao_publica && (
            <p className="text-muted-foreground mt-2 text-sm md:text-base">{contrato.descricao_publica}</p>
          )}
        </div>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Termos do contrato</CardTitle>
          </CardHeader>
          <CardContent>
            {/* Contrato gerado (ex.: parceria) já traz o próprio CSS ABNT: sem a tipografia "prose" por cima */}
            <div
              className={contrato.corpo_html.includes("contrato-abnt")
                ? "max-h-[60vh] overflow-y-auto border rounded-md bg-white"
                : "prose prose-sm max-w-none max-h-[50vh] overflow-y-auto border rounded-md p-4 bg-card"}
              dangerouslySetInnerHTML={{ __html: contrato.corpo_html }}
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base">Seus dados</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            <div className="grid md:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Nome completo *</Label>
                <Input value={nome} onChange={e => setNome(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>E-mail</Label>
                <Input type="email" value={email} onChange={e => setEmail(e.target.value)} disabled={!!signatarioEmail} />
              </div>
              {contrato.requer_cpf && (
                <div className="space-y-1.5">
                  <Label>CPF *</Label>
                  <Input value={cpf} onChange={e => setCpf(e.target.value)} inputMode="numeric" />
                </div>
              )}
              {contrato.requer_telefone && (
                <div className="space-y-1.5">
                  <Label>Telefone *</Label>
                  <Input value={telefone} onChange={e => setTelefone(e.target.value)} inputMode="tel" />
                </div>
              )}
              {contrato.requer_rg && (
                <div className="space-y-1.5">
                  <Label>RG *</Label>
                  <Input value={rg} onChange={e => setRg(e.target.value)} />
                </div>
              )}
              {contrato.requer_endereco && (
                <div className="space-y-1.5 md:col-span-2">
                  <Label>Endereço completo *</Label>
                  <Input value={endereco} onChange={e => setEndereco(e.target.value)} />
                </div>
              )}
            </div>
            
            {(contrato.requer_cnpj || contrato.requer_razao_social || contrato.requer_representante) && (
              <div className="pt-4 border-t space-y-4">
                <div className="flex items-center gap-2 text-primary">
                  <Building2 className="w-4 h-4" />
                  <span className="text-sm font-semibold">Dados da Empresa</span>
                </div>
                
                <div className="grid md:grid-cols-2 gap-3">
                  {contrato.requer_cnpj && (
                    <div className="space-y-1.5">
                      <Label className="flex items-center gap-2">
                        CNPJ * {buscandoCnpj && <Loader2 className="w-3 h-3 animate-spin" />}
                      </Label>
                      <Input 
                        value={cnpj} 
                        onChange={e => handleCnpjLookup(e.target.value)} 
                        placeholder="00.000.000/0000-00"
                        inputMode="numeric"
                      />
                    </div>
                  )}
                  {contrato.requer_razao_social && (
                    <div className="space-y-1.5">
                      <Label>Razão Social *</Label>
                      <Input value={razaoSocial} onChange={e => setRazaoSocial(e.target.value)} />
                    </div>
                  )}
                  {contrato.requer_representante && (
                    <div className="space-y-1.5 md:col-span-2">
                      <Label>Nome do Representante Legal *</Label>
                      <Input value={representante} onChange={e => setRepresentante(e.target.value)} />
                    </div>
                  )}
                </div>
              </div>
            )}

            {contrato.requer_geolocalizacao && (
              <div className={`border rounded-lg p-3 space-y-2 ${geo ? "bg-emerald-50 border-emerald-200" : "bg-muted/30"}`}>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <Label className="flex items-center gap-2">
                    <MapPin className="w-4 h-4" /> Localização *
                    {geo && <span className="text-emerald-700 text-xs font-normal">capturada ({geo.lat.toFixed(4)}, {geo.lng.toFixed(4)})</span>}
                    {!geo && geoBuscando && <span className="text-xs font-normal text-muted-foreground flex items-center gap-1"><Loader2 className="w-3 h-3 animate-spin" /> obtendo…</span>}
                  </Label>
                  <Button type="button" variant={geo ? "ghost" : "outline"} size="sm" onClick={capturarGeo} disabled={geoBuscando}>
                    <MapPin className="w-4 h-4 mr-2" />{geo ? "Atualizar" : "Permitir localização"}
                  </Button>
                </div>
                <p className="text-xs text-muted-foreground">A localização é registrada junto com a assinatura como prova de autoria. O navegador pede a sua permissão.</p>
                {geoErro && (
                  <Alert variant="destructive">
                    <AlertCircle className="h-4 w-4" />
                    <AlertDescription className="text-xs">{geoErro}</AlertDescription>
                  </Alert>
                )}
              </div>
            )}

            {contrato.requer_selfie && (
              <div className="border rounded-lg p-4 space-y-3 bg-muted/30">
                <Label className="flex items-center gap-2">
                  <Camera className="w-4 h-4" /> Selfie ao vivo *
                </Label>
                <p className="text-xs text-muted-foreground">
                  Sua selfie é usada apenas para confirmar sua identidade na assinatura deste contrato.
                </p>

                {camError && (
                  <Alert variant="destructive">
                    <AlertCircle className="h-4 w-4" />
                    <AlertDescription className="text-xs">{camError}</AlertDescription>
                  </Alert>
                )}

                {selfie ? (
                  <div className="space-y-2">
                    <img src={selfie} alt="selfie" className="w-full max-w-xs rounded-md border" />
                    <Button size="sm" variant="outline" onClick={() => { setSelfie(null); iniciarCamera(); }}>
                      <RefreshCw className="w-4 h-4 mr-2" /> Tirar novamente
                    </Button>
                  </div>
                ) : camOpen ? (
                  <div className="space-y-2">
                    <div className="relative rounded-md overflow-hidden border bg-black w-full max-w-sm">
                      <video
                        ref={videoRef}
                        autoPlay
                        playsInline
                        muted
                        className="w-full h-auto"
                        style={{ transform: "scaleX(-1)" }}
                      />
                    </div>
                    <div className="flex gap-2">
                      <Button size="sm" onClick={capturarSelfie}>
                        <Camera className="w-4 h-4 mr-2" /> Capturar
                      </Button>
                      <Button size="sm" variant="outline" onClick={pararCamera}>Cancelar</Button>
                    </div>
                  </div>
                ) : (
                  <Button size="sm" variant="outline" onClick={iniciarCamera}>
                    <Camera className="w-4 h-4 mr-2" /> Abrir câmera
                  </Button>
                )}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3"><CardTitle className="text-base">Assinatura</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-start gap-2">
              <Checkbox id="aceito" checked={aceito} onCheckedChange={v => setAceito(!!v)} className="mt-0.5" />
              <Label htmlFor="aceito" className="text-sm leading-relaxed cursor-pointer">
                Li e concordo com todos os termos do contrato acima. Declaro que as informações
                fornecidas são verdadeiras e autorizo o registro desta assinatura eletrônica.
              </Label>
            </div>

            <div className="space-y-2">
              <Label>Assine abaixo usando o dedo (mobile) ou mouse</Label>
              <div ref={sigBoxRef} className="border-2 border-dashed rounded-md bg-white overflow-hidden">
                <SignatureCanvas
                  ref={sigRef}
                  canvasProps={{
                    width: sigWidth,
                    height: 220,
                    className: "touch-none block",
                    style: { width: "100%", height: 220 },
                  }}
                  backgroundColor="white"
                  penColor="#0a0a0a"
                  minWidth={1.2}
                  maxWidth={2.8}
                  onEnd={() => setHasSig(true)}
                />
              </div>
              <div className="flex items-center justify-between">
                <p className="text-xs text-muted-foreground">Assinatura do(a) {nome || "signatário(a)"}</p>
                <Button type="button" size="sm" variant="ghost" onClick={limparAssinatura} disabled={!hasSig}>
                  <Eraser className="w-4 h-4 mr-1" /> Limpar
                </Button>
              </div>
            </div>

            <Alert>
              <Shield className="h-4 w-4" />
              <AlertTitle>Validade jurídica</AlertTitle>
              <AlertDescription className="text-xs">
                Sua assinatura será registrada com IP, dispositivo, data/hora e hash criptográfico,
                conforme Lei 14.063/2020 e MP 2.200-2/2001.
              </AlertDescription>
            </Alert>

            <Button onClick={handleEnviar} disabled={enviando || !aceito} className="w-full" size="lg">
              {enviando ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Registrando...</> : "Assinar contrato"}
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
