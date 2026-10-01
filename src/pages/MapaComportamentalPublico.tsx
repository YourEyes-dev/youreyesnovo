import { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import { Fingerprint, Loader2, AlertCircle, CheckCircle2, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { supabasePublic } from "@/lib/supabasePublic";
import { formatCpf, cleanCpf, validateCpf } from "@/lib/cpf";
import { toast } from "sonner";
import { ResponderMapa } from "@/components/mapa-comportamental/ResponderMapa";
import { RelatorioMeuMapa } from "@/components/mapa-comportamental/RelatorioMeuMapa";
import { AVISO_TRATAMENTO_VERSAO } from "@/components/mapa-comportamental/AvisoTratamento";
import { calcularMapa, type MapaResultado, type MapaRespostas } from "@/data/instrumentos/mapaComportamental";

type Etapa = "carregando" | "erro" | "identificacao" | "respondendo" | "enviando" | "concluido";

const AVISO_PADRAO =
  "As suas respostas são confidenciais. O resultado é uma leitura do seu estilo de trabalhar — " +
  "não é avaliação de desempenho, não é exame psicológico e não decide promoção, salário ou desligamento. " +
  "Responder é voluntário.";

export default function MapaComportamentalPublico() {
  const { token } = useParams<{ token: string }>();
  const [etapa, setEtapa] = useState<Etapa>("carregando");
  const [empresaNome, setEmpresaNome] = useState("");
  const [aviso, setAviso] = useState<string>(AVISO_PADRAO);
  const [erro, setErro] = useState<string | null>(null);

  const [cpf, setCpf] = useState("");
  const [nome, setNome] = useState("");
  const [aceito, setAceito] = useState(false);
  const [resultado, setResultado] = useState<MapaResultado | null>(null);

  useEffect(() => {
    if (!token) { setErro("Link inválido."); setEtapa("erro"); return; }
    (async () => {
      const { data, error } = await (supabasePublic as unknown as {
        rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
      }).rpc("mapa_comportamental_link_por_token", { p_token: token });
      const r = (data || {}) as { valido?: boolean; empresa_nome?: string; aviso?: string | null; error?: string };
      if (error || !r.valido) {
        setErro(r.error || "Link inválido ou expirado.");
        setEtapa("erro");
        return;
      }
      setEmpresaNome(r.empresa_nome || "");
      if (r.aviso) setAviso(r.aviso);
      setEtapa("identificacao");
    })();
  }, [token]);

  const enviar = async (respostas: MapaRespostas, tempo: number) => {
    if (!token) return;
    const r = calcularMapa(respostas, { tempoTotalSegundos: tempo });
    setResultado(r);
    setEtapa("enviando");
    const payload = {
      respostas,
      resultado: r,
      arquetipo: r.arquetipos.join("-"),
      indice_consistencia: r.indiceConsistencia,
      confiabilidade: r.confiabilidade,
      instrumento_versao: r.instrumentoVersao,
      algoritmo_versao: r.algoritmoVersao,
      tempo_total_segundos: tempo,
      aviso_versao: AVISO_TRATAMENTO_VERSAO,
    };
    const { data, error } = await (supabasePublic as unknown as {
      rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
    }).rpc("mapa_comportamental_salvar_por_token", {
      p_token: token, p_cpf: cleanCpf(cpf), p_nome: nome.trim(), p_payload: payload,
    });
    const res = (data || {}) as { success?: boolean; error?: string };
    if (error || !res.success) {
      toast.error(res.error || "Não foi possível enviar agora. Tente novamente.");
      setEtapa("respondendo");
      return;
    }
    setEtapa("concluido");
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-50 to-background dark:from-indigo-950/20 p-4 md:p-8">
      <div className="max-w-2xl mx-auto">
        {etapa === "carregando" && (
          <Card><CardContent className="py-16 text-center"><Loader2 className="w-6 h-6 animate-spin mx-auto" /></CardContent></Card>
        )}

        {etapa === "erro" && (
          <Card>
            <CardContent className="py-16 text-center space-y-3">
              <AlertCircle className="w-10 h-10 text-destructive mx-auto" />
              <p className="font-medium">{erro}</p>
              <p className="text-sm text-muted-foreground">Peça um novo link a quem te enviou.</p>
            </CardContent>
          </Card>
        )}

        {etapa === "identificacao" && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Fingerprint className="w-5 h-5 text-indigo-600" /> MODUS™ — seu modo de operar
              </CardTitle>
              {empresaNome && <p className="text-sm text-muted-foreground">{empresaNome}</p>}
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm text-muted-foreground">
                São 28 perguntas rápidas sobre o seu jeito de trabalhar. Ao final, você vê o seu resultado na hora.
              </p>
              <div className="space-y-1">
                <Label>Seu CPF *</Label>
                <Input
                  inputMode="numeric"
                  value={formatCpf(cpf)}
                  onChange={(e) => setCpf(cleanCpf(e.target.value))}
                  placeholder="000.000.000-00"
                  maxLength={14}
                />
              </div>
              <div className="space-y-1">
                <Label>Seu nome completo *</Label>
                <Input value={nome} onChange={(e) => setNome(e.target.value)} placeholder="Nome e sobrenome" />
              </div>
              <div className="flex items-start gap-2 rounded-md border border-sky-500/30 bg-sky-500/5 p-3 text-xs text-muted-foreground">
                <ShieldCheck className="w-4 h-4 text-sky-600 shrink-0 mt-0.5" />
                <span>{aviso}</span>
              </div>
              <label className="flex items-start gap-2 text-sm">
                <Checkbox checked={aceito} onCheckedChange={(v) => setAceito(v === true)} className="mt-0.5" />
                <span>Li o aviso acima e concordo em responder de forma voluntária.</span>
              </label>
              <Button
                className="w-full"
                disabled={!validateCpf(cpf) || !nome.trim() || !aceito}
                onClick={() => setEtapa("respondendo")}
              >
                Começar
              </Button>
              {cpf.length > 0 && !validateCpf(cpf) && (
                <p className="text-xs text-destructive">Informe um CPF válido.</p>
              )}
            </CardContent>
          </Card>
        )}

        {etapa === "respondendo" && (
          <ResponderMapa
            onAutosave={() => { /* anônimo: sem rascunho */ }}
            onPausar={() => setEtapa("identificacao")}
            onConcluir={enviar}
          />
        )}

        {etapa === "enviando" && (
          <Card><CardContent className="py-16 text-center space-y-2">
            <Loader2 className="w-6 h-6 animate-spin mx-auto" />
            <p className="text-sm text-muted-foreground">Calculando o seu mapa…</p>
          </CardContent></Card>
        )}

        {etapa === "concluido" && resultado && (
          <div className="space-y-4">
            <Card className="border-emerald-300 bg-emerald-50/50 dark:bg-emerald-950/20">
              <CardContent className="py-4 flex items-center gap-2 text-sm">
                <CheckCircle2 className="w-5 h-5 text-emerald-600 shrink-0" />
                <span>Pronto, {nome.split(" ")[0]}! Seu mapa foi registrado. Veja o seu resultado abaixo — você pode baixá-lo em PDF.</span>
              </CardContent>
            </Card>
            <RelatorioMeuMapa resultado={resultado} nome={nome} publico />
          </div>
        )}
      </div>
    </div>
  );
}
