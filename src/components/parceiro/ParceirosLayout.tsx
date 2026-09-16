import { Link, useNavigate } from "react-router-dom";
import { LogOut, User, LayoutDashboard, MessageCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuthContext } from "@/contexts/AuthContext";
import logoLocal from "@/assets/logo-youreyes.svg";

export const CONTATO_WHATSAPP = "https://wa.me/554699337504?text=" + encodeURIComponent("Olá! Quero saber mais sobre o Programa de Parceiros YourEyes.");
export const CONTATO_EMAIL = "mailto:contato@youreyes.com.br?subject=" + encodeURIComponent("Programa de Parceiros YourEyes");

// Casca leve da Área do Parceiro e da seção pública Parceiros: mesma
// identidade do site (fundo escuro, azul #60ABEF, laranja #FF8A00), sem a
// sidebar nem o menu do sistema.
export function ParceirosLayout({ children, titulo }: { children: React.ReactNode; titulo?: string }) {
  const { user, parceiroId, profile, signOut } = useAuthContext();
  const navigate = useNavigate();
  return (
    <div className="min-h-screen bg-[#0B1D34] text-slate-100">
      <header className="sticky top-0 z-20 border-b border-white/10 bg-[#0B1D34]/95 backdrop-blur">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <Link to="/parceiros" className="flex items-center gap-3">
            <img src={logoLocal} alt="YourEyes" className="h-9 w-auto" />
            <div className="leading-tight">
              <div className="font-bold text-white">YourEyes</div>
              <div className="text-[10px] uppercase tracking-[0.18em] text-slate-400">{titulo ?? "Programa de Parceiros"}</div>
            </div>
          </Link>
          <div className="flex-1" />
          <nav className="flex items-center gap-2 text-sm">
            {user && parceiroId && (
              <>
                <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/parceiro"><LayoutDashboard className="w-4 h-4 mr-1" />Painel</Link></Button>
                <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/parceiro/perfil"><User className="w-4 h-4 mr-1" />Meu cadastro</Link></Button>
                {profile && <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/">Ir ao sistema</Link></Button>}
                <Button variant="ghost" className="text-slate-300 hover:text-white hover:bg-white/10" onClick={async () => { await signOut(); navigate("/parceiros"); }}><LogOut className="w-4 h-4 mr-1" />Sair</Button>
              </>
            )}
            <Button asChild variant="ghost" className="hidden sm:inline-flex text-slate-200 hover:text-white hover:bg-white/10"><a href={CONTATO_WHATSAPP} target="_blank" rel="noreferrer"><MessageCircle className="w-4 h-4 mr-1" />Fale conosco</a></Button>
            {!user && (
              <>
                <Button asChild variant="ghost" className="text-slate-200 hover:text-white hover:bg-white/10"><Link to="/parceiros/entrar">Entrar</Link></Button>
                <Button asChild className="bg-[#FF8A00] hover:bg-[#e67a00] text-white"><Link to="/parceiros/cadastro">Quero ser parceiro</Link></Button>
              </>
            )}
          </nav>
        </div>
      </header>
      <main className="max-w-6xl mx-auto px-4 sm:px-6 py-8">{children}</main>
      <footer className="max-w-6xl mx-auto px-6 py-8 text-xs text-slate-500 border-t border-white/10">
        YourEyes · Programa de Parceiros · comissões calculadas sobre o MRR de tabela das assinaturas das contas originadas. <Link to="/parceiros/contrato" className="hover:text-white underline underline-offset-2">Contrato de Parceria</Link> · <Link to="/termos-de-uso" className="hover:text-white underline underline-offset-2">Termos de Uso</Link> · Dúvidas: <a href="mailto:contato@youreyes.com.br" className="hover:text-white">contato@youreyes.com.br</a>
      </footer>
    </div>
  );
}
