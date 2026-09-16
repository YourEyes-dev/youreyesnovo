import { lazy, Suspense } from "react";
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { VersionCheck } from "@/components/VersionCheck";
import { ConfirmDialogProvider } from "@/components/ui/confirm-dialog";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { AuthProvider, useAuthContext } from "@/contexts/AuthContext";
import { ProtectedRoute } from "@/components/auth/ProtectedRoute";
import { MainLayout } from "@/components/layout/MainLayout";
import { AuthLayout } from "@/components/layout/AuthLayout";
import { ParceiroRoute } from "@/components/auth/ParceiroRoute";
const ParceirosPublico = lazy(() => import("./pages/parceiros/ParceirosPublico"));
const CadastroParceiro = lazy(() => import("./pages/parceiros/CadastroParceiro"));
const PortalParceiro = lazy(() => import("./pages/parceiro/PortalParceiro"));
const PerfilParceiro = lazy(() => import("./pages/parceiro/PerfilParceiro"));
const ContratoParceria = lazy(() => import("./pages/parceiros/ContratoParceria"));
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { SuperAdminRoute } from "@/components/admin/SuperAdminRoute";
import { SuperAdminLayout } from "@/components/admin/superadmin/SuperAdminLayout";
import { Loader2 } from "lucide-react";

// Eager imports for all protected app pages (no loading delay on navigation)
import Dashboard from "./pages/Dashboard";
import Colaboradores from "./pages/Colaboradores";
import Ponto from "./pages/Ponto";
import Ferias from "./pages/Ferias";
import Documentos from "./pages/Documentos";
import ContratosExperiencia from "./pages/ContratosExperiencia";
import Epis from "./pages/Epis";
import Feed from "./pages/Feed";
import Ouvidoria from "./pages/Ouvidoria";
import FeedbackOcorrencias from "./pages/FeedbackOcorrencias";
import AprendizadoPapeis from "./pages/AprendizadoPapeis";
import Trilhas from "./pages/Trilhas";
import Estrategia from "./pages/Estrategia";
import Ergonomia from "./pages/Ergonomia";
import Psicossocial from "./pages/Psicossocial";
import ComplianceSST from "./pages/ComplianceSST";
import PlanoAcao from "./pages/PlanoAcao";
import PlanoAcaoDetalhe from "./pages/PlanoAcaoDetalhe";
import Avaliacoes from "./pages/Avaliacoes";
import MetasModule from "./pages/MetasModule";
import CentralGaf from "./pages/CentralGaf";
import Pdi from "./pages/Pdi";
import Financeiro from "./pages/Financeiro";
import Academia from "./pages/Academia";
import Empresa from "./pages/Empresa";
import Marketplace from "./pages/Marketplace";
import MarketYEPublico from "./pages/marketye/MarketYEPublico";
import CadastroEspecialista from "./pages/marketye/CadastroEspecialista";
import PortalEspecialista from "./pages/marketye/PortalEspecialista";
import { EspecialistaRoute } from "./components/auth/EspecialistaRoute";
import Terceiros from "./pages/Terceiros";
import IncidentesAcidentes from "./pages/IncidentesAcidentes";
import CulturaCelebracoes from "./pages/CulturaCelebracoes";
import BemEstar from "./pages/BemEstar";
import Onboarding from "./pages/Onboarding";
import FinanceiroBeneficios from "./pages/FinanceiroBeneficios";
import HubContabil from "./pages/HubContabil";
import Configuracoes from "./pages/Configuracoes";
import Suporte from "./pages/Suporte";
import SobreSistema from "./pages/SobreSistema";
import Usuarios from "./pages/Usuarios";
import PerfisAcesso from "./pages/PerfisAcesso";
import MeuPerfil from "./pages/MeuPerfil";
import MeuPlano from "./pages/MeuPlano";
import Pendencias from "./pages/Pendencias";
import Departamentos from "./pages/cadastros/Departamentos";
import Cargos from "./pages/cadastros/Cargos";
import Filiais from "./pages/cadastros/Filiais";
import AnaliseJornada from "./pages/AnaliseJornada";
import SaudeOcupacional from "./pages/SaudeOcupacional";
import NotFound from "./pages/NotFound";

// Lazy imports only for rarely accessed / public / admin pages
const PageLoader = () => (
  <div className="flex flex-col items-center justify-center min-h-screen bg-[#0a111f] gap-4">
    <Loader2 className="w-10 h-10 animate-spin text-primary" />
    <p className="text-slate-400 font-medium animate-pulse">Iniciando sistema...</p>
  </div>
);

const Login = lazy(() => import("./pages/auth/Login"));
const Register = lazy(() => import("./pages/auth/Register"));
const ForgotPassword = lazy(() => import("./pages/auth/ForgotPassword"));
const ResetPassword = lazy(() => import("./pages/auth/ResetPassword"));
const QuestionarioPsicossocial = lazy(() => import("./pages/QuestionarioPsicossocial"));
const EntrevistaGuiada = lazy(() => import("./pages/EntrevistaGuiada"));
const PdiAssinatura = lazy(() => import("./pages/PdiAssinatura"));
const PontoExterno = lazy(() => import("./pages/PontoExterno"));
const FeriasAssinatura = lazy(() => import("./pages/FeriasAssinatura"));
const TrilhaTerceiroPublica = lazy(() => import("./pages/TrilhaTerceiroPublica"));
const AssinaturaContrato = lazy(() => import("./pages/AssinaturaContrato"));
const ExperienciaAssinatura = lazy(() => import("./pages/ExperienciaAssinatura"));
const OrdemServicoAssinatura = lazy(() => import("./pages/OrdemServicoAssinatura"));
const ManualFuncaoAssinatura = lazy(() => import("./pages/ManualFuncaoAssinatura"));
const AceiteDocumento = lazy(() => import("./pages/AceiteDocumento"));
const OnboardingCliente = lazy(() => import("./pages/OnboardingCliente"));
const AtivarConta = lazy(() => import("./pages/AtivarConta"));
const OnboardingProtegido = lazy(() => import("./pages/OnboardingProtegido"));
const LandingPage = lazy(() => import("./pages/LandingPage"));
const Site = lazy(() => import("./pages/Site"));
const TermosDeUso = lazy(() => import("./pages/TermosDeUso"));
const PoliticaPrivacidade = lazy(() => import("./pages/PoliticaPrivacidade"));
const PlaceholderPage = lazy(() => import("./pages/PlaceholderPage"));
const CompletarCadastro = lazy(() => import("./pages/CompletarCadastro"));
const SuperAdminDashboard = lazy(() => import("./pages/admin/SuperAdminDashboard"));
const ManualSistema = lazy(() => import("./pages/admin/ManualSistema"));
const QADashboard = lazy(() => import("./pages/admin/QADashboard"));
const QADocs = lazy(() => import("./pages/admin/QADocs"));
const QARunner = lazy(() => import("./pages/admin/QARunner"));
const TenantAssinatura = lazy(() => import("./pages/admin/TenantAssinatura"));
const ControleClientesDashboard = lazy(() => import("./pages/admin/ControleClientesDashboard"));
const BlogAdmin = lazy(() => import("./pages/admin/BlogAdmin"));
const ContratosAceite = lazy(() => import("./pages/admin/ContratosAceite"));
const AssinarContrato = lazy(() => import("./pages/AssinarContrato"));
const TenantDetalhe = lazy(() => import("./pages/admin/TenantDetalhe"));

/**
 * Porta de entrada do domínio principal (https://youreyes.com.br/).
 *
 * Antes, quem digitava o endereço sem estar logado caía direto na tela de
 * login: o site institucional existia só em /site, endereço que visitante
 * nenhum adivinha. Agora a raiz mostra o site — é a vitrine — e o painel
 * continua exatamente em "/" para quem já tem sessão, de modo que nenhum
 * favorito, link interno ou redirecionamento de login precisou mudar.
 *
 * Este componente é o elemento do grupo de rotas protegidas: fora da raiz
 * ele se comporta como sempre (ProtectedRoute + MainLayout). Só na raiz, e
 * só para quem não tem sessão, ele entrega o site no lugar do painel.
 */
const RaizDoDominio = () => {
  const { user, loading } = useAuthContext();
  const { pathname } = useLocation();
  const naRaiz = pathname === "/";

  // Enquanto a sessão não é conhecida, não decidir: piscar o site
  // institucional na cara de quem já está logado seria pior que esperar.
  if (naRaiz && loading) return <PageLoader />;

  if (naRaiz && !user) {
    return (
      <Suspense fallback={<PageLoader />}>
        <Site />
      </Suspense>
    );
  }

  return (
    <ProtectedRoute>
      <MainLayout />
    </ProtectedRoute>
  );
};

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 2,
      gcTime: 1000 * 60 * 5,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

const App = () => (
  <ErrorBoundary>
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <VersionCheck />
      <ConfirmDialogProvider />
      <BrowserRouter basename={import.meta.env.BASE_URL}>
        <AuthProvider>
          <Suspense fallback={<PageLoader />}>
            <Routes>
              {/* Public Auth Routes */}
              <Route element={<AuthLayout />}>
                <Route path="/login" element={<Login />} />
                <Route path="/register" element={<Register />} />
                <Route path="/forgot-password" element={<ForgotPassword />} />
                <Route path="/reset-password" element={<ResetPassword />} />
                <Route path="/parceiros/entrar" element={<Login destino="/parceiro" variante="parceiro" />} />
                <Route path="/marketye/entrar" element={<Login destino="/marketye/portal" variante="especialista" />} />
              </Route>

              {/* Programa de Parceiros — seção pública do site e Área do Parceiro (fora do sistema) */}
              <Route path="/parceiros" element={<ParceirosPublico />} />
              <Route path="/parceiros/cadastro" element={<CadastroParceiro />} />
              <Route path="/parceiros/contrato" element={<ContratoParceria />} />
              {/* MarketYE: página pública de captação, cadastro do especialista (sem acesso ao sistema) e portal restrito */}
              <Route path="/marketye" element={<MarketYEPublico />} />
              <Route path="/marketye/cadastro" element={<CadastroEspecialista />} />
              <Route path="/marketye/portal" element={<EspecialistaRoute><PortalEspecialista /></EspecialistaRoute>} />
              <Route path="/parceiro" element={<ParceiroRoute><PortalParceiro /></ParceiroRoute>} />
              <Route path="/parceiro/perfil" element={<ParceiroRoute><PerfilParceiro /></ParceiroRoute>} />

              {/* Rota Pública - Questionário Psicossocial */}
              <Route path="/questionario/:token" element={<QuestionarioPsicossocial />} />
              <Route path="/p/:token" element={<QuestionarioPsicossocial tokenTipo="participacao" />} />
              <Route path="/entrevista/:token" element={<Suspense fallback={<PageLoader />}><EntrevistaGuiada /></Suspense>} />
              <Route path="/pdi-assinatura/:token" element={<PdiAssinatura />} />
              <Route path="/ferias-assinatura/:token" element={<FeriasAssinatura />} />
              <Route path="/trilha-terceiro/:token" element={<TrilhaTerceiroPublica />} />
              <Route path="/ponto-externo" element={<PontoExterno />} />
              <Route path="/ponto-externo/:token" element={<PontoExterno />} />
              <Route path="/contrato-assinatura/:token" element={<AssinaturaContrato />} />
              <Route path="/experiencia-assinatura/:token" element={<ExperienciaAssinatura />} />
              <Route path="/os/:token" element={<OrdemServicoAssinatura />} />
              <Route path="/manual-funcao/assinatura/:token" element={<ManualFuncaoAssinatura />} />
              <Route path="/aceite-documento/:token" element={<AceiteDocumento />} />
              <Route path="/completar-cadastro/:token" element={<CompletarCadastro />} />
              <Route path="/onboarding-cliente/:token" element={<OnboardingCliente />} />
              <Route path="/assinar-contrato/:token" element={<AssinarContrato />} />
              <Route path="/ativar-conta" element={<AtivarConta />} />
              <Route path="/marketplace" element={<div className="min-h-screen bg-background p-4 md:p-8"><Marketplace /></div>} />
              <Route path="/lp" element={<LandingPage />} />
              {/* O site institucional mudou de endereço: agora é a raiz do
                  domínio. /site continua atendendo — links antigos, anúncios e
                  perfis de rede social não podem quebrar — mas encaminha para
                  o endereço novo, para não existirem duas páginas iguais. */}
              <Route path="/site" element={<Navigate to="/" replace />} />
              <Route path="/termos-de-uso" element={<TermosDeUso />} />
              <Route path="/politica-de-privacidade" element={<PoliticaPrivacidade />} />

              {/* Super Admin — todas as rotas abrem dentro da casca com o menu
                  lateral agrupado por área (SuperAdminLayout). /admin e
                  /admin/:secao são as seções do painel; as demais são páginas
                  com componente próprio que ganharam o mesmo menu. */}
              <Route element={<SuperAdminRoute><SuperAdminLayout /></SuperAdminRoute>}>
                <Route path="/admin" element={<SuperAdminDashboard />} />
                <Route path="/admin/tenants/:id" element={<TenantDetalhe />} />
                <Route path="/admin/tenants/:id/assinatura" element={<TenantAssinatura />} />
                <Route path="/admin/manual" element={<ManualSistema />} />
                <Route path="/admin/qa" element={<QADashboard />} />
                <Route path="/admin/qa/docs" element={<QADocs />} />
                <Route path="/admin/qa/runner" element={<QARunner />} />
                <Route path="/admin/controle-clientes" element={<ControleClientesDashboard />} />
                {/* Endereço antigo da Central de Testes, hoje Central de Controle de Clientes. */}
                <Route path="/admin/youreyes" element={<Navigate to="/admin/controle-clientes" replace />} />
                <Route path="/admin/blog" element={<BlogAdmin />} />
                <Route path="/admin/contratos" element={<ContratosAceite />} />
                <Route path="/admin/:secao" element={<SuperAdminDashboard />} />
              </Route>

              {/* Protected Onboarding Route */}
              <Route path="/onboarding" element={<ProtectedRoute><OnboardingProtegido /></ProtectedRoute>} />

              {/* Protected App Routes */}
              <Route element={<RaizDoDominio />}>
                <Route path="/" element={<Dashboard />} />
                <Route path="/pendencias" element={<Pendencias />} />
                <Route path="/feed" element={<Feed />} />
                <Route path="/colaboradores" element={<Colaboradores />} />
                <Route path="/contratos-experiencia" element={<ContratosExperiencia />} />
                <Route path="/cadastros/departamentos" element={<Departamentos />} />
                <Route path="/cadastros/cargos" element={<Cargos />} />
                <Route path="/cadastros/filiais" element={<Filiais />} />
                <Route path="/financeiro" element={<Financeiro />} />
                <Route path="/financeiro/beneficios" element={<FinanceiroBeneficios />} />
                <Route path="/empresa" element={<Empresa />} />
                <Route path="/ponto" element={<Ponto />} />
                <Route path="/admissao" element={<Navigate to="/colaboradores" replace />} />
                <Route path="/ferias" element={<Ferias />} />
                <Route path="/avaliacoes" element={<Avaliacoes />} />
                <Route path="/metas" element={<MetasModule />} />
                <Route path="/atestados" element={<CentralGaf />} />
                <Route path="/saude-ocupacional" element={<SaudeOcupacional />} />
                <Route path="/plano-acao" element={<PlanoAcao />} />
                <Route path="/plano-acao/:id" element={<PlanoAcaoDetalhe />} />
                <Route path="/pdi" element={<Pdi />} />
                <Route path="/epis" element={<Epis />} />
                <Route path="/compliance-sst" element={<ComplianceSST />} />
                <Route path="/feedback-ocorrencias" element={<FeedbackOcorrencias />} />
                <Route path="/aprendizado-papeis" element={<AprendizadoPapeis />} />
                <Route path="/trilhas" element={<Trilhas />} />
                <Route path="/estrategia" element={<Estrategia />} />
                <Route path="/ouvidoria" element={<Ouvidoria />} />
                <Route path="/ergonomia" element={<Ergonomia />} />
                <Route path="/psicossocial" element={<Psicossocial />} />
                <Route path="/felicidade" element={<BemEstar />} />
                <Route path="/documentos" element={<Documentos />} />
                <Route path="/terceiros" element={<Terceiros />} />
                <Route path="/incidentes-acidentes" element={<IncidentesAcidentes />} />
                <Route path="/cultura-celebracoes" element={<CulturaCelebracoes />} />
                <Route path="/onboarding-rh" element={<Onboarding />} />
                <Route path="/hub-contabil" element={<HubContabil />} />
                <Route path="/academia" element={<SuperAdminRoute><Academia /></SuperAdminRoute>} />
                <Route path="/analise-jornada" element={<AnaliseJornada />} />
                <Route path="/usuarios" element={<Usuarios />} />
                <Route path="/configuracoes" element={<Configuracoes />} />
                <Route path="/suporte" element={<Suporte />} />
                <Route path="/sobre-sistema" element={<SobreSistema />} />
                <Route path="/meu-perfil" element={<MeuPerfil />} />
                <Route path="/meu-plano" element={<MeuPlano />} />
                <Route path="*" element={<NotFound />} />
              </Route>
            </Routes>
          </Suspense>
        </AuthProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
  </ErrorBoundary>
);

export default App;
