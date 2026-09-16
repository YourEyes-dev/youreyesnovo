import { Link, Navigate, useLocation } from "react-router-dom";
import { Loader2, Building2, Handshake } from "lucide-react";
import { useAuthContext } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { ParceirosLayout } from "@/components/parceiro/ParceirosLayout";

// Guarda da Área do Parceiro: exige login E vínculo em parceiro_usuarios.
// Não passa pelo ProtectedRoute do sistema (que exige perfil de tenant).
export function ParceiroRoute({ children }: { children: React.ReactNode }) {
  const { user, loading, parceiroId, profile, isSuperAdmin } = useAuthContext();
  const location = useLocation();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#0B1D34]">
        <Loader2 className="w-8 h-8 animate-spin text-[#60ABEF]" />
      </div>
    );
  }
  if (!user) return <Navigate to="/parceiros/entrar" state={{ from: location }} replace />;
  // Conta do sistema (perfil de empresa ou superadmin) sem vínculo de parceiro:
  // em vez de decidir sozinho, mostra a escolha — ir ao sistema ou tornar esta
  // conta parceira. Evita tanto "caí no cadastro sem querer" quanto "caí no
  // sistema quando queria a Área do Parceiro".
  if (!parceiroId && (profile || isSuperAdmin)) {
    return (
      <ParceirosLayout titulo="Área do Parceiro">
        <div className="max-w-xl mx-auto text-center py-10 space-y-6" data-testid="parceiro-conta-escolha">
          <h1 className="text-2xl font-bold text-white">Esta conta ainda não é de parceiro</h1>
          <p className="text-slate-300 text-sm">
            Você entrou com <b className="text-white">{user.email}</b>, que é uma conta do sistema YourEyes{profile ? " (empresa)" : ""}.
            A Área do Parceiro é para quem tem cadastro no Programa de Parceiros. O que você quer fazer?
          </p>
          <div className="grid sm:grid-cols-2 gap-3">
            <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white h-auto py-4 flex-col gap-1">
              <Link to="/parceiros/cadastro"><Handshake className="w-5 h-5" /><span>Quero ser parceiro com esta conta</span></Link>
            </Button>
            <Button asChild variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10 h-auto py-4 flex-col gap-1">
              <Link to="/"><Building2 className="w-5 h-5" /><span>Ir ao sistema</span></Link>
            </Button>
          </div>
          <p className="text-xs text-slate-400">Se você já é parceiro com outro e-mail, saia desta conta e entre com o e-mail do cadastro de parceiro.</p>
        </div>
      </ParceirosLayout>
    );
  }
  if (!parceiroId) return <Navigate to="/parceiros/cadastro" replace />;
  return <>{children}</>;
}
