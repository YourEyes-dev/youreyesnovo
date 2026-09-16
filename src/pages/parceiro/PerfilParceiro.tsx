import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { ParceirosLayout } from "@/components/parceiro/ParceirosLayout";
import { useParceiroPortal } from "@/hooks/useParceiroPortal";
import { PARCEIRO_TIPO_LABEL, PARCEIRO_STATUS_LABEL } from "@/hooks/useParceiros";

export default function PerfilParceiro() {
  const { dados, isLoading, salvarPerfil } = useParceiroPortal();
  const [f, setF] = useState({ email: "", telefone: "", endereco: "", cidade: "", uf: "", cep: "", pix_chave: "" });
  useEffect(() => {
    if (dados) setF({ email: dados.parceiro.email ?? "", telefone: dados.parceiro.telefone ?? "", endereco: dados.parceiro.endereco ?? "", cidade: dados.parceiro.cidade ?? "", uf: dados.parceiro.uf ?? "", cep: "", pix_chave: dados.parceiro.pix_chave ?? "" });
  }, [dados]);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF((x) => ({ ...x, [k]: e.target.value }));

  return (
    <ParceirosLayout>
      <div className="max-w-2xl space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-white">Meu cadastro</h1>
          {dados && <p className="text-sm text-slate-400 mt-1">{dados.parceiro.nome} · {PARCEIRO_TIPO_LABEL[dados.parceiro.tipo_parceiro]} · código <span className="font-mono">{dados.parceiro.codigo}</span> · {PARCEIRO_STATUS_LABEL[dados.parceiro.status]}</p>}
        </div>
        {isLoading && <Skeleton className="h-64 w-full bg-white/10" />}
        {dados && (
          <div className="rounded-2xl border border-white/10 bg-white/[0.04] p-5 grid grid-cols-2 gap-4">
            <div className="col-span-2 sm:col-span-1"><Label className="text-slate-300">E-mail de contato</Label><Input className="bg-black/20 border-white/15 text-white" value={f.email} onChange={set("email")} /></div>
            <div className="col-span-2 sm:col-span-1"><Label className="text-slate-300">Telefone</Label><Input className="bg-black/20 border-white/15 text-white" value={f.telefone} onChange={set("telefone")} /></div>
            <div><Label className="text-slate-300">Cidade</Label><Input className="bg-black/20 border-white/15 text-white" value={f.cidade} onChange={set("cidade")} /></div>
            <div className="grid grid-cols-2 gap-2">
              <div><Label className="text-slate-300">UF</Label><Input className="bg-black/20 border-white/15 text-white uppercase" maxLength={2} value={f.uf} onChange={set("uf")} /></div>
              <div className="sm:col-span-2"><Label className="text-slate-300">Endereço (rua, número, bairro)</Label><Input className="bg-black/20 border-white/15 text-white" value={f.endereco} onChange={set("endereco")} /></div>
              <div><Label className="text-slate-300">CEP</Label><Input className="bg-black/20 border-white/15 text-white" value={f.cep} onChange={set("cep")} placeholder="mantém o atual" /></div>
            </div>
            <div className="col-span-2"><Label className="text-slate-300">Chave PIX para pagamento das comissões</Label><Input className="bg-black/20 border-white/15 text-white" value={f.pix_chave} onChange={set("pix_chave")} placeholder="CPF/CNPJ, e-mail, telefone ou chave aleatória" />
              <p className="text-[11px] text-slate-500 mt-1">Visível só para você e para a equipe financeira YourEyes.</p></div>
            <div className="col-span-2 flex justify-end">
              <Button className="bg-[#FF8A00] hover:bg-[#e67a00] text-white" disabled={salvarPerfil.isPending} onClick={() => salvarPerfil.mutate({ ...f, cep: f.cep || undefined })}>Salvar</Button>
            </div>
          </div>
        )}
        <p className="text-xs text-slate-500">Nome, tipo de parceiro e documento só mudam com a equipe YourEyes (contato@youreyes.com.br).</p>
      </div>
    </ParceirosLayout>
  );
}
