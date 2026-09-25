import { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import { motion } from "framer-motion";
import {
  MessageSquare, Loader2, AlertCircle, CheckCircle2, Shield, UserCheck, EyeOff, Copy,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";
import { supabasePublic } from "@/lib/supabasePublic";
import { formatCpf, cleanCpf } from "@/lib/cpf";
import {
  TIPO_MANIFESTACAO_LABELS, TIPO_MANIFESTACAO_ICONS, type TipoManifestacao,
} from "@/types/ouvidoria";
import { toast } from "sonner";

const TIPOS: TipoManifestacao[] = ["denuncia", "reclamacao", "sugestao", "elogio", "duvida"];

type Etapa = "carregando" | "erro" | "formulario" | "enviando" | "concluido";

export default function OuvidoriaExterna() {
  const { token } = useParams<{ token: string }>();

  const [etapa, setEtapa] = useState<Etapa>("carregando");
  const [empresaNome, setEmpresaNome] = useState<string>("");
  const [erro, setErro] = useState<string | null>(null);

  // Formulário
  const [tipo, setTipo] = useState<TipoManifestacao>("denuncia");
  const [anonimo, setAnonimo] = useState(true);
  const [cpf, setCpf] = useState("");
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [assunto, setAssunto] = useState("");
  const [mensagem, setMensagem] = useState("");
  const [protocolo, setProtocolo] = useState<string>("");

  // Resolve o link
  useEffect(() => {
    if (!token) {
      setErro("Link inválido.");
      setEtapa("erro");
      return;
    }
    (async () => {
      const { data, error } = await (supabasePublic as any).rpc("buscar_ouvidoria_link_por_token", { p_token: token });
      const result = (data || {}) as any;
      if (error || !result.valido) {
        setErro(result.error || "Link inválido ou expirado.");
        setEtapa("erro");
        return;
      }
      setEmpresaNome(result.empresa_nome || "");
      setEtapa("formulario");
    })();
  }, [token]);

  // Identificação declaratória: ao completar o CPF, tenta preencher o nome.
  const resolverCpf = async (valor: string) => {
    const limpo = cleanCpf(valor);
    if (limpo.length !== 11 || !token) return;
    const { data } = await (supabasePublic as any).rpc("buscar_colaborador_ouvidoria_por_cpf", {
      p_token: token, p_cpf: limpo,
    });
    const r = (data || {}) as any;
    if (r.encontrado && r.nome && !nome.trim()) setNome(r.nome);
  };

  const enviar = async () => {
    if (!token) return;
    if (!assunto.trim() || !mensagem.trim()) {
      toast.error("Preencha o assunto e a mensagem.");
      return;
    }
    if (!anonimo && cleanCpf(cpf).length > 0 && cleanCpf(cpf).length !== 11) {
      toast.error("Informe um CPF completo ou deixe em branco.");
      return;
    }
    setEtapa("enviando");
    const { data, error } = await (supabasePublic as any).rpc("registrar_manifestacao_externa", {
      p_token: token,
      p_tipo: tipo,
      p_assunto: assunto.trim(),
      p_mensagem: mensagem.trim(),
      p_anonimo: anonimo,
      p_cpf: anonimo ? null : (cleanCpf(cpf) || null),
      p_nome: anonimo ? null : (nome.trim() || null),
      p_email: anonimo ? null : (email.trim() || null),
    });
    const r = (data || {}) as any;
    if (error || r.error || !r.success) {
      toast.error(r.error || "Não foi possível enviar agora. Tente novamente.");
      setEtapa("formulario");
      return;
    }
    setProtocolo(r.protocolo || "");
    setEtapa("concluido");
  };

  const copiarProtocolo = () => {
    navigator.clipboard.writeText(protocolo);
    toast.success("Protocolo copiado!");
  };

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-50 to-slate-100 dark:from-slate-950 dark:to-slate-900 flex flex-col items-center justify-center p-4 gap-4">
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="w-full max-w-lg">
        <div className="text-center mb-4">
          <div className="w-12 h-12 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-2">
            <MessageSquare className="w-6 h-6 text-primary" />
          </div>
          <h1 className="text-xl font-bold text-foreground">Canal de Ouvidoria</h1>
          {empresaNome && <p className="text-sm text-muted-foreground">{empresaNome}</p>}
        </div>

        {etapa === "carregando" && (
          <Card><CardContent className="py-12 text-center"><Loader2 className="w-6 h-6 animate-spin mx-auto text-muted-foreground" /></CardContent></Card>
        )}

        {etapa === "erro" && (
          <Card>
            <CardContent className="py-12 text-center space-y-3">
              <AlertCircle className="w-10 h-10 text-rose-500 mx-auto" />
              <p className="font-medium">{erro}</p>
              <p className="text-sm text-muted-foreground">Peça um novo link à sua empresa.</p>
            </CardContent>
          </Card>
        )}

        {etapa === "concluido" && (
          <Card>
            <CardContent className="py-10 text-center space-y-4">
              <CheckCircle2 className="w-12 h-12 text-emerald-500 mx-auto" />
              <div>
                <p className="font-semibold text-lg">Manifestação enviada!</p>
                <p className="text-sm text-muted-foreground">Sua manifestação foi registrada e será tratada pela empresa.</p>
              </div>
              {protocolo && (
                <div className="rounded-lg border bg-muted/40 p-4 space-y-2">
                  <p className="text-xs text-muted-foreground">Guarde o seu protocolo de acompanhamento:</p>
                  <div className="flex items-center justify-center gap-2">
                    <code className="text-base font-bold tracking-wide">{protocolo}</code>
                    <Button variant="ghost" size="icon" className="h-7 w-7" onClick={copiarProtocolo}>
                      <Copy className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {(etapa === "formulario" || etapa === "enviando") && (
          <Card>
            <CardContent className="py-6 space-y-5">
              {/* Tipo */}
              <div className="space-y-2">
                <Label className="text-sm">Tipo de manifestação</Label>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {TIPOS.map((t) => (
                    <button
                      key={t}
                      type="button"
                      onClick={() => setTipo(t)}
                      className={`flex items-center gap-1.5 rounded-lg border px-3 py-2 text-sm transition-colors ${
                        tipo === t ? "border-primary bg-primary/10 text-foreground font-medium" : "border-border hover:bg-muted/50 text-muted-foreground"
                      }`}
                    >
                      <span>{TIPO_MANIFESTACAO_ICONS[t]}</span>
                      {TIPO_MANIFESTACAO_LABELS[t]}
                    </button>
                  ))}
                </div>
              </div>

              {/* Identificação */}
              <div className="space-y-2">
                <Label className="text-sm">Como deseja registrar?</Label>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setAnonimo(true)}
                    className={`flex items-center gap-2 rounded-lg border px-3 py-2.5 text-sm transition-colors ${
                      anonimo ? "border-primary bg-primary/10 font-medium" : "border-border hover:bg-muted/50 text-muted-foreground"
                    }`}
                  >
                    <EyeOff className="w-4 h-4" /> Anônimo
                  </button>
                  <button
                    type="button"
                    onClick={() => setAnonimo(false)}
                    className={`flex items-center gap-2 rounded-lg border px-3 py-2.5 text-sm transition-colors ${
                      !anonimo ? "border-primary bg-primary/10 font-medium" : "border-border hover:bg-muted/50 text-muted-foreground"
                    }`}
                  >
                    <UserCheck className="w-4 h-4" /> Identificar-me
                  </button>
                </div>
              </div>

              {!anonimo && (
                <div className="space-y-3 rounded-lg border bg-muted/20 p-3">
                  <div className="space-y-1.5">
                    <Label htmlFor="cpf" className="text-xs">CPF</Label>
                    <Input
                      id="cpf"
                      inputMode="numeric"
                      placeholder="000.000.000-00"
                      value={cpf}
                      onChange={(e) => setCpf(formatCpf(e.target.value))}
                      onBlur={(e) => resolverCpf(e.target.value)}
                      maxLength={14}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="nome" className="text-xs">Nome</Label>
                    <Input id="nome" placeholder="Seu nome" value={nome} onChange={(e) => setNome(e.target.value)} />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="email" className="text-xs">E-mail (opcional)</Label>
                    <Input id="email" type="email" placeholder="seu@email.com" value={email} onChange={(e) => setEmail(e.target.value)} />
                  </div>
                </div>
              )}

              {/* Conteúdo */}
              <div className="space-y-1.5">
                <Label htmlFor="assunto" className="text-sm">Assunto</Label>
                <Input id="assunto" placeholder="Resumo em poucas palavras" value={assunto} maxLength={200} onChange={(e) => setAssunto(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="mensagem" className="text-sm">Mensagem</Label>
                <Textarea id="mensagem" placeholder="Descreva sua manifestação com o máximo de detalhes." rows={6} maxLength={5000} value={mensagem} onChange={(e) => setMensagem(e.target.value)} />
              </div>

              <Button className="w-full" size="lg" onClick={enviar} disabled={etapa === "enviando"}>
                {etapa === "enviando" ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <MessageSquare className="w-4 h-4 mr-2" />}
                Enviar manifestação
              </Button>

              <div className="flex items-start gap-2 rounded-md border border-sky-500/30 bg-sky-500/5 p-3 text-xs text-muted-foreground">
                <Shield className="w-4 h-4 text-sky-600 shrink-0 mt-0.5" />
                <span>
                  No modo <strong>anônimo</strong>, nenhum dado de identificação é registrado. Ao se identificar, seus dados ficam visíveis apenas aos responsáveis pela ouvidoria.
                </span>
              </div>
            </CardContent>
          </Card>
        )}
      </motion.div>

      <p className="text-slate-500 text-[10px] text-center max-w-xs">
        Canal de Ouvidoria • Registro via link externo • Dados protegidos (LGPD)
      </p>
    </div>
  );
}
