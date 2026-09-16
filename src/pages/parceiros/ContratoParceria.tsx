import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Loader2, FileSignature, CheckCircle2, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { supabase } from "@/integrations/supabase/client";
import { useAuthContext } from "@/contexts/AuthContext";
import { ParceirosLayout } from "@/components/parceiro/ParceirosLayout";
import { useParceiroPortal } from "@/hooks/useParceiroPortal";

// O texto do contrato vive no banco (parceiro_contratos_versoes) e é público,
// como os Termos de Uso. Ele já vem formatado (padrão ABNT) e, para quem é
// parceiro, com a qualificação das duas partes. A assinatura acontece no
// mesmo fluxo dos contratos do SuperAdmin (/assinar-contrato/:token):
// assinatura na tela, selfie, IP, dispositivo, localização e hash.
export default function ContratoParceria() {
  const navigate = useNavigate();
  const { user, parceiroId } = useAuthContext();
  const { dados } = useParceiroPortal();
  const [versao, setVersao] = useState<{ versao: number; titulo: string; html: string; publicado_em: string } | null>(null);
  const [carregando, setCarregando] = useState(true);
  const [iniciando, setIniciando] = useState(false);

  useEffect(() => {
    (async () => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data } = await (supabase as any).rpc("parceiro_contrato_publico");
      setVersao(data ?? null); setCarregando(false);
    })();
  }, []);

  const aguardando = !!(user && parceiroId && dados?.contrato?.aguardando_aprovacao);
  const pendente = !!(user && parceiroId && dados?.contrato?.pendente) && !aguardando;
  const assinar = async () => {
    setIniciando(true);
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const { data, error } = await (supabase as any).rpc("parceiro_contrato_iniciar_assinatura");
      if (error) throw error;
      if (data?.ja_assinado) { toast.info("Esta versão já está assinada."); return; }
      if (!data?.token) throw new Error("Não foi possível gerar o link de assinatura");
      navigate(`/assinar-contrato/${data.token}`);
    } catch (e) { toast.error(e instanceof Error ? e.message : "Não foi possível iniciar a assinatura"); }
    finally { setIniciando(false); }
  };

  return (
    <ParceirosLayout titulo="Contrato de Parceria">
      <div className="max-w-4xl mx-auto">
        {carregando && <Loader2 className="w-6 h-6 animate-spin text-[#60ABEF]" />}
        {!carregando && !versao && <p className="text-slate-300">Nenhuma versão do contrato publicada ainda.</p>}
        {versao && (
          <>
            <div className="flex items-start justify-between gap-4 flex-wrap mb-6">
              <div className="max-w-2xl">
                <div className="text-xs font-semibold uppercase tracking-widest text-[#60ABEF] mb-2 flex items-center gap-2"><FileSignature className="w-4 h-4" />Versão {versao.versao} · publicada em {new Date(versao.publicado_em).toLocaleDateString("pt-BR")}</div>
                <p className="text-sm text-slate-400">
                  O contrato é gerado com os dados da YourEyes e os seus. A assinatura é eletrônica e tem validade jurídica (Lei 14.063/2020 e MP 2.200-2/2001):
                  você assina na tela, tira uma selfie e o sistema registra IP, dispositivo, localização, data/hora e o hash do texto.
                  A cópia assinada fica guardada pela YourEyes e disponível para você.
                </p>
              </div>
              {aguardando && <span className="inline-flex items-center gap-1.5 text-sm text-amber-300 max-w-xs"><ShieldCheck className="w-4 h-4 shrink-0" />A assinatura é liberada depois que a equipe YourEyes aprovar o seu cadastro.</span>}
              {pendente && (
                <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={iniciando} onClick={assinar} data-testid="contrato-assinar">
                  {iniciando ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <FileSignature className="w-4 h-4 mr-2" />}Assinar eletronicamente
                </Button>
              )}
              {user && parceiroId && dados?.contrato && !dados.contrato.pendente && (
                <span className="inline-flex items-center gap-1.5 text-sm text-emerald-300"><CheckCircle2 className="w-4 h-4" />Assinado em {dados.contrato.aceito_em ? new Date(dados.contrato.aceito_em).toLocaleDateString("pt-BR") : "—"}</span>
              )}
              {!user && <Button asChild variant="outline" className="border-white/20 bg-transparent text-slate-200 hover:bg-white/10"><Link to="/parceiros/cadastro">Quero ser parceiro</Link></Button>}
            </div>
            {pendente && (
              <div className="mb-4 rounded-xl border border-[#60ABEF]/40 bg-[#60ABEF]/10 p-3 text-sm text-slate-100 flex items-start gap-2">
                <ShieldCheck className="w-4 h-4 mt-0.5 shrink-0 text-[#60ABEF]" />
                <span>Leia o contrato abaixo. Quando estiver de acordo, clique em <b>Assinar eletronicamente</b>: você será levado à página de assinatura, onde confirma seus dados, tira a selfie e assina.</span>
              </div>
            )}
            {/* Conteúdo da casa (tabela própria, só superadmin escreve). O HTML já traz o CSS ABNT; a "folha" branca é o próprio contrato. */}
            <article className="rounded-2xl bg-white shadow-2xl overflow-hidden" data-testid="contrato-texto" dangerouslySetInnerHTML={{ __html: versao.html }} />
          </>
        )}
      </div>
    </ParceirosLayout>
  );
}
