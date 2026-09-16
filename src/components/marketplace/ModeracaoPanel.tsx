import { useState } from "react";
import { CheckCircle2, XCircle, FileText, Shield, Clock, MapPin, Eye, PauseCircle, PlayCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
import { useMarketYEModeracao } from "@/hooks/useMarketYE";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { BUCKET_DOCS, caminhoNoBucket } from "@/lib/marketyeAnexos";

interface Pendente {
  id: string; nome_completo: string; email: string; telefone: string | null; cpf_cnpj: string | null; tipo_pessoa: string; foto_url: string | null; bio: string | null;
  formacao_academica: string | null; registro_profissional: string | null; conselho: string | null; uf_registro: string | null; registro_validade: string | null;
  especialidades: string[] | null; areas_atuacao: string[] | null; cidade: string | null; estado: string | null; created_at: string; status: string; origem_cadastro: string;
  moderacao_motivo: string | null; documentos: { id: string; categoria: string; nome_arquivo: string; arquivo_url: string; created_at: string }[];
  consentimentos: { tipo: string; versao: string; aceito_em: string }[]; anuncios: number; denuncias_abertas: number; reputacao: { nivel?: string; saude_cor?: string } | null;
}

const categoriaLabels: Record<string, string> = {
  documento_pessoal: "Documento pessoal", cpf_comprovante: "CPF / CNPJ", registro_conselho: "Registro do conselho", formacao: "Diploma / formação",
  certificacao: "Certificação", comprovante_endereco: "Comprovante de endereço", atestado_capacidade_tecnica: "Atestado de capacidade técnica", selfie_verificacao: "Selfie de verificação", foto_perfil: "Foto de perfil",
};

export function ModeracaoPanel({ ativo }: { ativo: boolean }) {
  const { fila, suspensos, moderar, situacao } = useMarketYEModeracao(ativo);
  const [sel, setSel] = useState<Pendente | null>(null);
  const [motivo, setMotivo] = useState("");
  const [selo, setSelo] = useState(true);
  const [rejeitando, setRejeitando] = useState(false);
  const pendentes = (fila.data ?? []) as Pendente[];
  const listaSuspensos = (suspensos.data ?? []) as Pendente[];

  // Os documentos ficam num bucket PRIVADO: a URL "pública" guardada nas
  // primeiras versões não abre. O link é assinado na hora, por dois minutos.
  // A janela abre antes da chamada (dentro do clique) para o navegador não
  // bloquear como pop-up.
  const abrirDocumento = async (d: Pendente["documentos"][number]) => {
    const janela = window.open("about:blank", "_blank");
    try {
      const caminho = caminhoNoBucket(d.arquivo_url, BUCKET_DOCS);
      const { data, error } = await supabase.storage.from(BUCKET_DOCS).createSignedUrl(caminho, 120);
      if (error || !data?.signedUrl) throw new Error(error?.message ?? "sem link");
      if (janela) janela.location.href = data.signedUrl; else window.open(data.signedUrl, "_blank", "noopener,noreferrer");
    } catch (e) {
      janela?.close();
      toast.error(`Não foi possível abrir ${d.nome_arquivo}: ${e instanceof Error ? e.message : "erro"}`);
    }
  };

  const Lista = ({ itens, vazio }: { itens: Pendente[]; vazio: string }) => (
    itens.length === 0 ? <p className="text-sm text-muted-foreground py-6 text-center">{vazio}</p> : (
      <div className="grid gap-3 md:grid-cols-2">
        {itens.map((p) => (
          <div key={p.id} className="rounded-2xl border border-border p-4 space-y-2">
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-3 min-w-0">
                {p.foto_url ? <img src={p.foto_url} alt="" className="w-10 h-10 rounded-xl object-cover" /> : <div className="w-10 h-10 rounded-xl bg-muted flex items-center justify-center font-bold">{p.nome_completo.charAt(0)}</div>}
                <div className="min-w-0">
                  <p className="font-medium truncate">{p.nome_completo}</p>
                  <p className="text-xs text-muted-foreground">{p.conselho ? `${p.conselho} ${p.registro_profissional ?? ""}` : "sem registro informado"} · {[p.cidade, p.estado].filter(Boolean).join("/")}</p>
                </div>
              </div>
              <Badge variant="secondary" className="text-[10px]"><Clock className="h-3 w-3 mr-1" />{format(new Date(p.created_at), "dd/MM", { locale: ptBR })}</Badge>
            </div>
            <div className="flex flex-wrap gap-1 text-[10px]">
              <Badge variant="outline">{p.documentos.length} documento(s)</Badge>
              <Badge variant="outline">{p.consentimentos.length} aceite(s)</Badge>
              <Badge variant="outline">origem: {p.origem_cadastro}</Badge>
              {p.denuncias_abertas > 0 && <Badge className="bg-red-100 text-red-700">{p.denuncias_abertas} denúncia(s)</Badge>}
            </div>
            {p.moderacao_motivo && <p className="text-xs text-muted-foreground">Motivo anterior: {p.moderacao_motivo}</p>}
            <div className="flex gap-2">
              <Button size="sm" variant="outline" onClick={() => { setSel(p); setMotivo(""); setSelo(true); setRejeitando(false); }}><Eye className="h-3.5 w-3.5 mr-1" />Ver cadastro</Button>
              {p.status === "suspenso" && <Button size="sm" variant="outline" className="text-emerald-700" onClick={() => situacao.mutate({ id: p.id, situacao: "ativo", motivo: "Reativado pela moderação" })}><PlayCircle className="h-3.5 w-3.5 mr-1" />Reativar</Button>}
            </div>
          </div>
        ))}
      </div>
    )
  );

  return (
    <div className="space-y-6">
      <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-800 flex gap-2">
        <Shield className="h-4 w-4 mt-0.5 shrink-0" />
        <p>Aqui você confere os dados e documentos de quem se cadastrou e decide se pode aparecer para as empresas. Aprovar liga o selo <b>"dados verificados"</b> (o selo diz que os dados conferem, não que o serviço é garantido). Para não aprovar é preciso escrever o motivo: o especialista lê e pode pedir revisão.</p>
      </div>
      <section>
        <h3 className="font-semibold mb-2">Aguardando aprovação ({pendentes.length})</h3>
        {fila.isLoading ? <p className="text-sm text-muted-foreground">Carregando...</p> : <Lista itens={pendentes} vazio="Nenhum cadastro aguardando aprovação." />}
      </section>
      <section>
        <h3 className="font-semibold mb-2">Suspensos ({listaSuspensos.length})</h3>
        <Lista itens={listaSuspensos} vazio="Nenhum especialista suspenso." />
      </section>

      <Dialog open={!!sel} onOpenChange={(v) => { if (!v) setSel(null); }}>
        <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
          {sel && (
            <>
              <DialogHeader><DialogTitle>{sel.nome_completo}</DialogTitle></DialogHeader>
              <div className="space-y-4 text-sm">
                <div className="grid sm:grid-cols-2 gap-2">
                  <p><span className="text-muted-foreground">E-mail:</span> {sel.email}</p>
                  <p><span className="text-muted-foreground">Telefone:</span> {sel.telefone ?? "—"}</p>
                  <p><span className="text-muted-foreground">{sel.tipo_pessoa === "pj" ? "CNPJ" : "CPF"}:</span> {sel.cpf_cnpj ?? "—"}</p>
                  <p><span className="text-muted-foreground">Registro:</span> {sel.conselho ?? "—"} {sel.registro_profissional ?? ""} {sel.uf_registro ?? ""} {sel.registro_validade ? `(até ${format(new Date(sel.registro_validade), "dd/MM/yyyy")})` : ""}</p>
                  <p><span className="text-muted-foreground">Formação:</span> {sel.formacao_academica ?? "—"}</p>
                  <p className="flex items-center gap-1"><MapPin className="h-3 w-3" />{[sel.cidade, sel.estado].filter(Boolean).join(", ") || "—"}</p>
                </div>
                {sel.bio && <p className="text-muted-foreground">{sel.bio}</p>}
                {sel.especialidades && sel.especialidades.length > 0 && <div className="flex flex-wrap gap-1">{sel.especialidades.map((e) => <Badge key={e} variant="secondary" className="text-xs">{e}</Badge>)}</div>}
                <div>
                  <p className="font-medium mb-1">Documentos</p>
                  {sel.documentos.length === 0 ? <p className="text-xs text-muted-foreground">Nenhum documento enviado.</p> : (
                    <ul className="space-y-1">
                      {sel.documentos.map((d) => (
                        <li key={d.id} className="flex items-center gap-2 text-xs"><FileText className="h-3.5 w-3.5" /><span className="text-muted-foreground">{categoriaLabels[d.categoria] ?? d.categoria}:</span><button type="button" className="underline text-left" onClick={() => void abrirDocumento(d)} data-testid="admin-marketye-documento">{d.nome_arquivo}</button></li>
                      ))}
                    </ul>
                  )}
                </div>
                <div>
                  <p className="font-medium mb-1">Termos aceitos</p>
                  <ul className="text-xs text-muted-foreground">{sel.consentimentos.map((c, i) => <li key={i}>{c.tipo} · versão {c.versao} · {format(new Date(c.aceito_em), "dd/MM/yyyy HH:mm")}</li>)}</ul>
                </div>
                {sel.status === "pendente" && (
                  <div className="space-y-3 border-t pt-3">
                    <div className="flex items-center gap-2"><Checkbox id="selo" checked={selo} onCheckedChange={(v) => setSelo(!!v)} /><label htmlFor="selo" className="text-xs">Conferi os documentos e o registro: mostrar o selo "dados verificados"</label></div>
                    {rejeitando && (
                      <div className="space-y-1"><Label>Explique o motivo (o especialista vai ler)</Label><Textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} /></div>
                    )}
                    <div className="flex gap-2 justify-end">
                      {!rejeitando ? (
                        <>
                          <Button variant="outline" className="text-red-600" onClick={() => setRejeitando(true)}><XCircle className="h-4 w-4 mr-1" />Não aprovar</Button>
                          <Button className="bg-emerald-600 hover:bg-emerald-700 text-white" disabled={moderar.isPending} onClick={() => moderar.mutate({ id: sel.id, resultado: "aprovado", selo }, { onSuccess: () => setSel(null) })}><CheckCircle2 className="h-4 w-4 mr-1" />Aprovar</Button>
                        </>
                      ) : (
                        <>
                          <Button variant="ghost" onClick={() => setRejeitando(false)}>Voltar</Button>
                          <Button variant="destructive" disabled={moderar.isPending || motivo.trim().length < 5} onClick={() => moderar.mutate({ id: sel.id, resultado: "rejeitado", motivo, selo: false }, { onSuccess: () => setSel(null) })}>Confirmar</Button>
                        </>
                      )}
                    </div>
                  </div>
                )}
                {sel.status === "suspenso" && (
                  <div className="flex gap-2 justify-end border-t pt-3">
                    <Button variant="outline" className="text-emerald-700" onClick={() => situacao.mutate({ id: sel.id, situacao: "ativo", motivo: "Reativado pela moderação" }, { onSuccess: () => setSel(null) })}><PlayCircle className="h-4 w-4 mr-1" />Reativar</Button>
                  </div>
                )}
                {sel.status === "ativo" && (
                  <div className="flex gap-2 justify-end border-t pt-3">
                    <Button variant="outline" className="text-amber-700" onClick={() => situacao.mutate({ id: sel.id, situacao: "suspenso", motivo: "Suspenso pela moderação" }, { onSuccess: () => setSel(null) })}><PauseCircle className="h-4 w-4 mr-1" />Suspender</Button>
                  </div>
                )}
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
