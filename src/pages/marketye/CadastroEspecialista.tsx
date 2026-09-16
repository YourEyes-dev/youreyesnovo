import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Loader2, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { MarketYELayout } from "@/components/marketye/MarketYELayout";
import { useMarketYEPublico } from "./MarketYEPublico";
import { validateCpf } from "@/lib/cpf";
import { validateCnpj } from "@/lib/cnpj";
import { geocodeCidade } from "@/lib/nominatim";

const UFS = ["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO"];

// Dois caminhos, um formulário (mesmo desenho do Programa de Parceiros):
//  * visitante sem conta → Edge Function marketye-cadastro (cria a conta e o cadastro);
//  * quem já está logado (empresa, parceiro) → função SQL marketye_cadastrar_especialista.
// Sem rótulos obrigatórios: o prestador conta o que faz em uma frase; a área
// é só uma ajuda opcional para as empresas encontrarem.
export default function CadastroEspecialista() {
  const navigate = useNavigate();
  const { user, especialistaId, signIn, loading: authLoading } = useAuthContext();
  const { data: publico } = useMarketYEPublico();
  const [f, setF] = useState({
    nome_completo: "", email: user?.email ?? "", senha: "", tipo_pessoa: "pf", cpf_cnpj: "", telefone: "", cidade: "", estado: "",
    o_que_faz: "", categoria_slug: "", registro: "", modalidades: ["presencial", "online"] as string[], aceite: false,
  });
  const [enviando, setEnviando] = useState(false);
  const set = (k: keyof typeof f, v: unknown) => setF((x) => ({ ...x, [k]: v }));
  const toggleMod = (m: string) => set("modalidades", f.modalidades.includes(m) ? f.modalidades.filter((x) => x !== m) : [...f.modalidades, m]);
  const versoes = publico?.termos_versoes ?? {};

  if (!authLoading && user && especialistaId) {
    return (
      <MarketYELayout>
        <div className="max-w-lg mx-auto text-center py-16 space-y-4">
          <h1 className="text-2xl font-bold text-white">Você já tem cadastro no MarketYE</h1>
          <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/marketye/portal">Abrir meu portal</Link></Button>
        </div>
      </MarketYELayout>
    );
  }

  const docLimpo = f.cpf_cnpj.replace(/\D/g, "");
  const docValido = f.tipo_pessoa === "pj" ? validateCnpj(docLimpo) : validateCpf(docLimpo);
  const registroPartes = f.registro.trim().split(/\s+/);
  const conselho = registroPartes.length > 1 ? registroPartes[0].toUpperCase() : (f.registro.trim() ? f.registro.trim().toUpperCase() : null);
  const numeroRegistro = registroPartes.length > 1 ? registroPartes.slice(1).join(" ") : null;

  const enviar = async () => {
    if (f.nome_completo.trim().length < 3) return toast.error("Informe seu nome");
    if (!docValido) return toast.error(f.tipo_pessoa === "pj" ? "Confira o CNPJ: os dígitos não batem" : "Confira o CPF: os dígitos não batem");
    if (f.o_que_faz.trim().length < 10) return toast.error("Conte em uma frase o que você faz");
    if (f.modalidades.length === 0) return toast.error("Marque como você atende");
    if (!f.aceite) return toast.error("É preciso aceitar os termos para continuar");
    setEnviando(true);
    try {
      const geo = f.cidade && f.estado ? await geocodeCidade(f.cidade, f.estado) : null;
      const areaNome = f.categoria_slug ? publico?.categorias.flatMap((c) => [c, ...c.filhas]).find((c) => c.slug === f.categoria_slug)?.nome : undefined;
      const dados = {
        nome_completo: f.nome_completo.trim(), email: f.email.trim().toLowerCase(), tipo_pessoa: f.tipo_pessoa, cpf_cnpj: docLimpo, telefone: f.telefone || null,
        cidade: f.cidade || null, estado: f.estado || null, latitude: geo?.lat ?? null, longitude: geo?.lng ?? null,
        conselho, registro_profissional: numeroRegistro, bio: f.o_que_faz.trim(), modalidades: f.modalidades,
        especialidades: areaNome ? [areaNome] : [], aceite_termos: true, user_agent: navigator.userAgent, origem: "site",
      };
      if (user) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const { data, error } = await (supabase as any).rpc("marketye_cadastrar_especialista", { _dados: dados });
        if (error) throw error;
        toast.success(data?.ja_existia ? "Você já tinha cadastro. Abrindo seu portal…" : "Cadastro recebido! Agora é só seguir o passo a passo do portal.");
        window.location.assign(`${import.meta.env.BASE_URL.replace(/\/$/, "")}/marketye/portal`);
        return;
      }
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email)) return toast.error("Confira o e-mail");
      if (f.senha.length < 6) return toast.error("A senha precisa ter ao menos 6 caracteres");
      const { data, error } = await supabase.functions.invoke("marketye-cadastro", { body: { ...dados, senha: f.senha } });
      const erro = error ? await extrairErro(error) : data?.error;
      if (erro) {
        if (/Já existe uma conta/i.test(erro)) { toast.warning(erro); navigate("/marketye/entrar"); return; }
        throw new Error(erro);
      }
      toast.success("Cadastro recebido! Entrando no seu portal…");
      const { error: loginErr } = await signIn(f.email.trim().toLowerCase(), f.senha);
      if (loginErr) { navigate("/marketye/entrar"); return; }
      navigate("/marketye/portal", { replace: true });
    } catch (e) {
      toast.error(e instanceof Error ? e.message.replace(/^.*?:\s*/, "") : "Não foi possível concluir o cadastro");
    } finally {
      setEnviando(false);
    }
  };

  const inputCls = "bg-black/20 border-white/15 text-white";
  return (
    <MarketYELayout titulo="Cadastro">
      <div className="max-w-2xl mx-auto" data-testid="marketye-cadastro">
        <h1 className="text-3xl font-bold text-white">Quero oferecer meus serviços às empresas</h1>
        <p className="text-slate-300 mt-2">
          {user ? `Você está usando a conta ${user.email}. O cadastro fica ligado a ela.` : "Leva um minuto. Depois, no seu portal, um passo a passo mostra o que fazer. Já tem conta no YourEyes? "}
          {!user && <Link to="/marketye/entrar" className="text-[#60ABEF] hover:underline">Entre primeiro</Link>}
        </p>

        <div className="mt-6 rounded-2xl border border-white/10 bg-white/[0.04] p-5 grid grid-cols-2 gap-4">
          <div className="col-span-2"><Label className="text-slate-300">Seu nome ou o nome da sua empresa*</Label><Input data-testid="cad-nome" className={inputCls} value={f.nome_completo} onChange={(e) => set("nome_completo", e.target.value)} /></div>
          <div><Label className="text-slate-300">Você atua como</Label>
            <Select value={f.tipo_pessoa} onValueChange={(v) => set("tipo_pessoa", v)}><SelectTrigger className={inputCls}><SelectValue /></SelectTrigger><SelectContent><SelectItem value="pf">Pessoa física (CPF)</SelectItem><SelectItem value="pj">Empresa (CNPJ)</SelectItem></SelectContent></Select>
          </div>
          <div><Label className="text-slate-300">{f.tipo_pessoa === "pj" ? "CNPJ*" : "CPF*"}</Label><Input data-testid="cad-documento" className={`${inputCls} ${f.cpf_cnpj && !docValido ? "border-red-400" : ""}`} value={f.cpf_cnpj} onChange={(e) => set("cpf_cnpj", e.target.value)} placeholder={f.tipo_pessoa === "pj" ? "00.000.000/0000-00" : "000.000.000-00"} /></div>
          <div className="col-span-2"><Label className="text-slate-300">O que você faz para empresas?* (uma frase basta)</Label><Textarea data-testid="cad-o-que-faz" className={inputCls} rows={2} value={f.o_que_faz} onChange={(e) => set("o_que_faz", e.target.value)} placeholder="Ex.: dou treinamentos de NR-35 e brigada de incêndio · faço manutenção de ar-condicionado · sou contadora e cuido de folha e eSocial" /></div>
          <div><Label className="text-slate-300">Área mais próxima (opcional)</Label>
            <Select value={f.categoria_slug || "nenhuma"} onValueChange={(v) => set("categoria_slug", v === "nenhuma" ? "" : v)}>
              <SelectTrigger className={inputCls}><SelectValue placeholder="Se quiser" /></SelectTrigger>
              <SelectContent><SelectItem value="nenhuma">Prefiro não escolher agora</SelectItem>{(publico?.categorias ?? []).map((c) => <SelectItem key={c.id} value={c.slug}>{c.nome}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div><Label className="text-slate-300">Registro profissional, se a sua área tiver (opcional)</Label><Input className={inputCls} value={f.registro} onChange={(e) => set("registro", e.target.value)} placeholder="Ex.: CREA 12345-PR · CRP 06/1234 · CRC PR-012345" /></div>
          <div><Label className="text-slate-300">Cidade</Label><Input className={inputCls} value={f.cidade} onChange={(e) => set("cidade", e.target.value)} /></div>
          <div><Label className="text-slate-300">Estado</Label>
            <Select value={f.estado} onValueChange={(v) => set("estado", v)}><SelectTrigger className={inputCls}><SelectValue placeholder="UF" /></SelectTrigger><SelectContent>{UFS.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent></Select>
          </div>
          <div><Label className="text-slate-300">Telefone / WhatsApp (só aparece quando a empresa liberar)</Label><Input className={inputCls} value={f.telefone} onChange={(e) => set("telefone", e.target.value)} /></div>
          <div>
            <Label className="text-slate-300">Como você atende</Label>
            <div className="flex gap-2 mt-1 flex-wrap">
              {[["presencial", "Na empresa"], ["online", "A distância"], ["hibrido", "Dos dois jeitos"]].map(([m, l]) => (
                <button key={m} type="button" onClick={() => toggleMod(m)} className={`px-3 py-2 rounded-lg border text-sm transition ${f.modalidades.includes(m) ? "border-[#FF8A00] bg-[#FF8A00]/10 text-white" : "border-white/15 text-slate-300 hover:border-white/30"}`}>{l}</button>
              ))}
            </div>
          </div>
          {!user && (
            <>
              <div><Label className="text-slate-300">E-mail para entrar*</Label><Input data-testid="cad-email" type="email" autoComplete="email" className={inputCls} value={f.email} onChange={(e) => set("email", e.target.value)} /></div>
              <div><Label className="text-slate-300">Crie uma senha*</Label><Input type="password" autoComplete="new-password" className={inputCls} value={f.senha} onChange={(e) => set("senha", e.target.value)} /></div>
            </>
          )}
          <div className="col-span-2 rounded-xl border border-white/10 bg-black/20 p-3 text-xs text-slate-300 flex gap-2">
            <ShieldCheck className="w-4 h-4 text-[#60ABEF] shrink-0 mt-0.5" />
            <p>As empresas veem seu nome, o que você faz, sua cidade, suas avaliações e o selo de dados verificados. Telefone, e-mail e documentos não aparecem: o contato só sai quando a empresa liberar, dentro de uma conversa registrada. Você pode baixar ou excluir seus dados quando quiser.</p>
          </div>
          <div className="col-span-2 flex items-start gap-2 text-sm text-slate-300">
            <Checkbox id="aceite" data-testid="cad-aceite" checked={f.aceite} onCheckedChange={(v) => set("aceite", v === true)} className="mt-0.5 border-white/40" />
            <label htmlFor="aceite">Li e aceito os <Link to="/termos-de-uso" className="text-[#60ABEF] hover:underline" target="_blank">Termos do Especialista</Link>{versoes.termos_especialista ? ` (versão ${versoes.termos_especialista})` : ""}, a <Link to="/politica-de-privacidade" className="text-[#60ABEF] hover:underline" target="_blank">Política de Privacidade</Link> e o Código de Ética. Sem exclusividade: você define preço e horários e pode atender fora do MarketYE.</label>
          </div>
          <div className="col-span-2 flex justify-end">
            <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={enviando} onClick={enviar} data-testid="cad-enviar">{enviando && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}Concluir cadastro</Button>
          </div>
        </div>
      </div>
    </MarketYELayout>
  );
}

async function extrairErro(error: unknown): Promise<string> {
  const ctx = (error as { context?: Response }).context;
  if (ctx && typeof ctx.json === "function") {
    try { const b = await ctx.json(); if (b?.error) return String(b.error); } catch { /* segue */ }
  }
  return error instanceof Error ? error.message : "Falha ao cadastrar";
}
