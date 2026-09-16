import { Navigate, useLocation, Link } from "react-router-dom";
import { useAuthContext } from "@/contexts/AuthContext";
import type { AppRole } from "@/types/database";
import { Loader2, Ban, ShieldOff } from "lucide-react";
import { useUsuarioStatus } from "@/hooks/useUsuarioStatus";
import { Button } from "@/components/ui/button";
import { usePerfilPermissions } from "@/hooks/usePerfilPermissions";
import { getModuloForPath, ALWAYS_ALLOWED_PATHS, isAdminPath } from "@/lib/moduleAccess";

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredRole?: AppRole;
}

export function ProtectedRoute({ children, requiredRole }: ProtectedRouteProps) {
  const { user, profile, loading, hasMinimumRole, signOut, isSuperAdmin, parceiroId, especialistaId } = useAuthContext();
  const location = useLocation();
  const { isBloqueado, isLoading: loadingStatus } = useUsuarioStatus(user?.id, profile?.tenant_id);
  const { temAcessoModulo, temAcessoModuloAdmin, perfilVinculado, isLoading: loadingPerfil, isOwner } = usePerfilPermissions();

  if (loading || (user && profile && loadingStatus)) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#0a111f]">
        <div className="flex flex-col items-center gap-4">
          <Loader2 className="w-10 h-10 animate-spin text-primary" />
          <p className="text-slate-400 font-medium animate-pulse">Carregando...</p>
        </div>
      </div>
    );
  }

  // Not logged in
  if (!user) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  // Superadmins podem não ter profile - redirecionar para área admin
  if (!profile && isSuperAdmin) {
    return <Navigate to="/admin" replace />;
  }

  // Parceiro comercial sem perfil de tenant: a casa dele é a Área do Parceiro,
  // fora do sistema (planejamento do Programa de Parceiros, seção 2.4).
  if (!profile && !isSuperAdmin && parceiroId) {
    return <Navigate to="/parceiro" replace />;
  }

  // Especialista do MarketYE sem perfil de empresa: a casa dele é o portal do
  // especialista, fora do sistema (entidade global, sem tenant).
  if (!profile && !isSuperAdmin && especialistaId) {
    return <Navigate to="/marketye/portal" replace />;
  }

  // Logged in, but missing tenant/profile linkage (não é superadmin)
  if (!profile && !isSuperAdmin) {
    return <Navigate to="/login" replace />;
  }

  // Usuário bloqueado/suspenso/inativo — impedir acesso
  if (isBloqueado && !isSuperAdmin) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="max-w-md w-full mx-4 text-center space-y-6">
          <div className="w-16 h-16 rounded-full bg-destructive/10 flex items-center justify-center mx-auto">
            <Ban className="w-8 h-8 text-destructive" />
          </div>
          <div className="space-y-2">
            <h1 className="text-2xl font-bold text-foreground">Acesso Bloqueado</h1>
            <p className="text-muted-foreground">
              Sua conta foi bloqueada por um administrador. 
              Você não pode acessar o sistema até que o bloqueio seja removido.
            </p>
          </div>
          <p className="text-sm text-muted-foreground">
            Entre em contato com o administrador da sua empresa para mais informações.
          </p>
          <Button
            variant="outline"
            onClick={() => signOut()}
            className="mt-4"
          >
            Sair da conta
          </Button>
        </div>
      </div>
    );
  }

  if (requiredRole && !hasMinimumRole(requiredRole)) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <h1 className="text-2xl font-bold mb-2">Acesso Negado</h1>
          <p className="text-muted-foreground">
            Você não tem permissão para acessar esta página.
          </p>
        </div>
      </div>
    );
  }

  // Perfil-based gating: se o usuário tem perfil vinculado (e não é owner/superadmin),
  // checa se a rota atual está liberada para o módulo do seu perfil.
  if (
    !isSuperAdmin &&
    !isOwner &&
    perfilVinculado &&
    !loadingPerfil &&
    !ALWAYS_ALLOWED_PATHS.has(location.pathname.split("?")[0].split("#")[0])
  ) {
    const modulo = getModuloForPath(location.pathname);
    const requerAdmin = isAdminPath(location.pathname);
    // Gating estrito:
    //  - rota sem módulo mapeado → bloqueada
    //  - rota administrativa → exige permissão com escopo ≠ proprio_usuario
    //  - demais rotas → basta ter qualquer permissão no módulo
    const blocked =
      !modulo ||
      (requerAdmin ? !temAcessoModuloAdmin(modulo) : !temAcessoModulo(modulo));
    if (blocked) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-background p-4">
          <div className="max-w-md w-full text-center space-y-6">
            <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center mx-auto">
              <ShieldOff className="w-8 h-8 text-muted-foreground" />
            </div>
            <div className="space-y-2">
              <h1 className="text-2xl font-bold text-foreground">Acesso Restrito</h1>
              <p className="text-muted-foreground">
                Seu perfil de acesso não inclui este módulo. Solicite ao administrador
                da sua empresa para revisar suas permissões.
              </p>
            </div>
            <Link
              to="/"
              className="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:opacity-90"
            >
              Voltar ao início
            </Link>
          </div>
        </div>
      );
    }
  }

  return <>{children}</>;
}

function NavigateButton({ to, children }: { to: string; children: React.ReactNode }) {
  return (
    <Link
      to={to}
      className="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:opacity-90"
    >
      {children}
    </Link>
  );
}
