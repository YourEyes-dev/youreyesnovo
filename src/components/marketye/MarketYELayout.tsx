import { Link, useNavigate } from "react-router-dom";
import { LogOut, LayoutDashboard, Store, Building2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuthContext } from "@/contexts/AuthContext";
import logoLocal from "@/assets/logo-youreyes.svg";

// Casca leve do MarketYE público e do portal do especialista: mesma
// identidade do site (fundo escuro, azul #60ABEF, laranja #FF8A00), sem a
// sidebar nem o menu do sistema. O especialista não entra no sistema das
// empresas (entidade global, sem tenant).
export function MarketYELayout({ children, titulo }: { children: React.ReactNode; titulo?: string }) {
  const { user, especialistaId, profile, isSuperAdmin, signOut } = useAuthContext();
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-[#0B1D34] text-slate-100">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-[#0B1D34]/95 backdrop-blur">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <Link to="/marketye" className="flex items-center gap-3">
            <img src={logoLocal} alt="YourEyes" className="h-9 w-auto" />
            <div className="leading-tight">
              <div className="font-bold text-white">MarketYE</div>
              <div className="text-[10px] uppercase tracking-[0.18em] text-slate-400">{titulo ?? "Marketplace de serviços"}</div>
            </div>
          </Link>
          <div className="flex-1" />
          <nav className="flex items-center gap-2 text-sm">
            {user && especialistaId && (
              <>
                <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/marketye/portal"><LayoutDashboard className="w-4 h-4 mr-1" />Meu portal</Link></Button>
                {(profile || isSuperAdmin) && <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/marketplace"><Store className="w-4 h-4 mr-1" />Vitrine</Link></Button>}
              </>
            )}
            {user && !especialistaId && (profile || isSuperAdmin) && (
              <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/"><Building2 className="w-4 h-4 mr-1" />Ir ao sistema</Link></Button>
            )}
            {user ? (
              <Button variant="ghost" className="text-slate-300 hover:text-white hover:bg-white/10" onClick={async () => { await signOut(); navigate("/marketye"); }}><LogOut className="w-4 h-4 mr-1" />Sair</Button>
            ) : (
              <>
                <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/marketye/entrar">Entrar</Link></Button>
                <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/marketye/cadastro">Quero me cadastrar</Link></Button>
              </>
            )}
          </nav>
        </div>
      </header>
      <main className="max-w-6xl mx-auto px-4 sm:px-6 py-8">{children}</main>
      <footer className="max-w-6xl mx-auto px-6 py-8 text-xs text-slate-500 border-t border-white/10">
        YourEyes · MarketYE · o YourEyes faz o encontro entre empresas e especialistas; quem faz o serviço é o especialista. O selo diz que os dados foram conferidos, não que o serviço é garantido.{" "}
        <Link to="/termos-de-uso" className="hover:text-white underline underline-offset-2">Termos de Uso</Link> · <Link to="/politica-de-privacidade" className="hover:text-white underline underline-offset-2">Privacidade</Link> · Fale com a gente: <a href="mailto:contato@youreyes.com.br" className="hover:text-white">contato@youreyes.com.br</a>
      </footer>
    </div>
  );
}
