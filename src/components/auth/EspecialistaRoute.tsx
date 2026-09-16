import { Link, Navigate, useLocation } from "react-router-dom";
import { Loader2, Building2, Store } from "lucide-react";
import { useAuthContext } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { MarketYELayout } from "@/components/marketye/MarketYELayout";

// Guarda do portal do especialista: exige login E cadastro em
// marketplace_profissionais. Não passa pelo ProtectedRoute do sistema (que
// exige perfil de empresa) — o especialista é uma entidade global, sem tenant.
export function EspecialistaRoute({ children }: { children: React.ReactNode }) {
  const { user, loading, especialistaId, profile, isSuperAdmin } = useAuthContext();
  const location = useLocation();

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center bg-[#0B1D34]"><Loader2 className="w-8 h-8 animate-spin text-[#60ABEF]" /></div>;
  }
  if (!user) return <Navigate to="/marketye/entrar" state={{ from: location }} replace />;
  if (!especialistaId && (profile || isSuperAdmin)) {
    return (
      <MarketYELayout titulo="Portal do especialista">
        <div className="max-w-xl mx-auto text-center py-10 space-y-6" data-testid="especialista-conta-escolha">
          <h1 className="text-2xl font-bold text-white">Esta conta ainda não é de especialista</h1>
          <p className="text-slate-300 text-sm">Você entrou com <b className="text-white">{user.email}</b>, uma conta do sistema YourEyes. O portal é para quem se cadastrou como especialista do MarketYE. O que você quer fazer?</p>
          <div className="grid sm:grid-cols-2 gap-3">
            <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white h-auto py-4 flex-col gap-1"><Link to="/marketye/cadastro"><Store className="w-5 h-5" /><span>Quero me cadastrar com esta conta</span></Link></Button>
            <Button asChild variant="outline" className="border-white/20 bg-transparent text-slate-100 hover:bg-white/10 h-auto py-4 flex-col gap-1"><Link to="/marketplace"><Building2 className="w-5 h-5" /><span>Ir à vitrine (empresa)</span></Link></Button>
          </div>
        </div>
      </MarketYELayout>
    );
  }
  if (!especialistaId) return <Navigate to="/marketye/cadastro" replace />;
  return <>{children}</>;
}
