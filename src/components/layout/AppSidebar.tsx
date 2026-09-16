import { useState, useMemo, useRef, useEffect } from "react";
import { useAuthContext } from "@/contexts/AuthContext";
import { usePerfilPermissions } from "@/hooks/usePerfilPermissions";
import { getModuloForPath, ALWAYS_ALLOWED_PATHS, isAdminPath } from "@/lib/moduleAccess";
import { NavLink, useLocation, useNavigate } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import {
  Home,
  Users,
  MessageSquareHeart,
  ClipboardList,
  Clock,
  Calendar,
  Star,
  FileText,
  Target,
  Shield,
  Activity,
  Heart,
  FolderOpen,
  MessageCircle,
  DollarSign,
  UserPlus,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Settings,
  Stethoscope,
  Building2,
  BookOpen,
  Compass,
  Store,
  HardHat,
  ShieldAlert,
  HeartPulse,
  Sparkles,
  Newspaper,
  Route,
  Search,
  X,
  Brain,
  BarChart3,
  LifeBuoy,
  Info,
  Lock,
  Layers,
} from "lucide-react";
import { toast } from "sonner";
import { usePlanLock } from "@/hooks/useTenantFeatures";
import { cn } from "@/lib/utils";
import { Logo } from "@/components/ui/Logo";

interface MenuItem {
  title: string;
  icon: React.ElementType;
  path?: string;
  children?: { title: string; path: string; color?: string; dot?: string }[];
}

interface MenuSection {
  label: string;
  items: MenuItem[];
  color: string;
  sectionIcon: React.ElementType;
}

const normalizeSearchText = (value: string) =>
  value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim();

// Sinônimos / palavras-chave por rota para enriquecer a busca da sidebar
const SEARCH_KEYWORDS: Record<string, string[]> = {
  "/": ["inicio", "home", "painel", "dashboard"],
  "/estrategia": ["estrategia", "governanca", "pilares", "swot"],
  "/compliance-sst": ["compliance", "sst", "seguranca", "normas", "pgr", "pcmso", "ltcat"],
  "/incidentes-acidentes": ["incidente", "acidente", "cat", "ocorrencia"],
  "/ergonomia": ["ergonomia", "nr17", "aep", "aet", "postura"],
  "/psicossocial": ["psicossocial", "nr01", "saude mental", "burnout"],
  "/epis": ["epi", "equipamento", "protecao", "entrega", "estoque"],
  "/plano-acao": ["plano", "acao", "5w2h"],
  "/avaliacoes": ["avaliacao", "desempenho", "ciclo", "9box"],
  "/pdi": ["pdi", "desenvolvimento", "individual", "metas"],
  "/colaboradores": ["colaborador", "funcionario", "admissao", "pessoa"],
  "/contratos-experiencia": ["contrato", "experiencia", "periodo"],
  "/onboarding-rh": ["onboarding", "integracao", "novo colaborador"],
  "/ferias": ["ferias", "periodo aquisitivo", "programacao"],
  "/atestados": ["atestado", "medico", "afastamento", "saude", "licenca"],
  "/felicidade": ["bem-estar", "felicidade", "humor", "gratidao", "meu bem-estar"],
  "/feedback-ocorrencias": ["feedback", "desenvolvimento", "ocorrencia", "advertencia"],
  "/ouvidoria": ["ouvidoria", "denuncia", "canal", "etica"],
  "/aprendizado-papeis": ["aprendizado", "competencias", "papeis", "academia", "curso"],
  "/trilhas": ["trilha", "capacitacao", "treinamento"],
  "/cultura-celebracoes": ["cultura", "celebracao", "aniversario", "reconhecimento"],
  "/feed": ["mural", "feed", "comunicacao", "noticia", "mural interno"],
  "/ponto": ["ponto", "marcacao", "relogio", "jornada"],
  "/analise-jornada": ["jornada", "analise", "horas extras", "banco"],
  "/empresa": ["empresa", "cnpj", "dados"],
  "/cadastros/departamentos": ["departamento", "setor", "area"],
  "/cadastros/cargos": ["cargo", "cbo"],
  "/cadastros/filiais": ["filial", "obra", "estabelecimento", "unidade"],
  "/marketplace": ["marketye", "marketplace", "especialista", "profissional", "servicos", "rede de parceiros"],
  "/terceiros": ["terceiro", "terceirizado", "prestador"],
  "/documentos": ["documento", "arquivo", "pasta", "upload"],
  "/financeiro": ["financeiro", "guia", "pagamento", "certidao"],
  "/financeiro/beneficios": ["beneficio", "vale", "plano saude"],
  "/hub-contabil": ["contabil", "hub", "competencia", "folha"],
  "/configuracoes": ["configuracao", "usuario", "perfil", "acesso", "auditoria"],
  "/suporte": ["suporte", "ticket", "ajuda", "bug"],
  "/sobre-sistema": ["sobre", "versao", "versão", "ambiente", "publicacao", "publicação", "build"],
  "/meu-perfil": ["meu perfil", "conta", "avatar", "senha", "email"],
};

const checkIsActive = (path: string, pathname: string, search: string) => {
  if (!path) return false;
  const fullPath = pathname + search;
  if (path.includes("?")) {
    return fullPath === path;
  }
  if (path === "/estrategia") {
    const params = new URLSearchParams(search);
    const tab = params.get("tab");
    return pathname === "/estrategia" && (!tab || (tab !== "organograma" && tab !== "cultura"));
  }
  if (path === "/psicossocial") {
    const params = new URLSearchParams(search);
    return pathname === "/psicossocial" && !params.get("tab");
  }
  // Metodologia agrupa sub-abas (?tab=metodologia&sub=...) e os links legados
  // (?tab=riscos|instrumentos|indicadores) que para ela redirecionam.
  if (path === "/psicossocial?tab=metodologia") {
    const params = new URLSearchParams(search);
    const tab = params.get("tab");
    return pathname === "/psicossocial" &&
      (tab === "metodologia" || tab === "riscos" || tab === "instrumentos" || tab === "indicadores");
  }
  return pathname === path;
};

const menuSections: MenuSection[] = [
  {
    label: "Estrutura Organizacional",
    color: "text-cyan-400",
    sectionIcon: Building2,
    items: [
      { title: "Empresa", icon: Building2, path: "/empresa" },
      { title: "Estabelecimentos / Obras", icon: Building2, path: "/cadastros/filiais" },
      { title: "Departamentos", icon: Building2, path: "/cadastros/departamentos" },
      { title: "Cargos", icon: Users, path: "/cadastros/cargos" },
      { title: "Colaboradores", icon: Users, path: "/colaboradores" },
      { title: "Prestadores de Serviços", icon: HardHat, path: "/terceiros" },
      { title: "Organograma", icon: Users, path: "/estrategia?tab=organograma" },
    ],
  },
  {
    label: "Planejamento & Gestão",
    color: "text-emerald-400",
    sectionIcon: Compass,
    items: [
      { title: "Identidade Estratégica", icon: Heart, path: "/estrategia?tab=cultura" },
      { title: "Planejamento Estratégico", icon: Compass, path: "/estrategia" },
      { title: "Metas", icon: Target, path: "/metas" },
      { title: "Plano de Ação", icon: Target, path: "/plano-acao" },
    ],
  },
  {
    label: "Pessoas & Cultura",
    color: "text-violet-400",
    sectionIcon: Users,
    items: [
      { title: "Onboarding", icon: UserPlus, path: "/onboarding-rh" },
      { title: "Contratos de Experiência", icon: FileText, path: "/contratos-experiencia" },
      { title: "Cultura & Celebrações", icon: Sparkles, path: "/cultura-celebracoes" },
      { title: "Mural Interno", icon: Newspaper, path: "/feed" },
      { title: "Meu Bem-Estar", icon: Heart, path: "/felicidade" },
      { title: "Feedback & Desenvolvimento", icon: MessageCircle, path: "/feedback-ocorrencias" },
      { title: "Ouvidoria", icon: MessageSquareHeart, path: "/ouvidoria" },
    ],
  },
  {
    label: "Desenvolvimento & Performance",
    color: "text-emerald-400",
    sectionIcon: Target,
    items: [
      { title: "Aprendizado & Competências", icon: BookOpen, path: "/aprendizado-papeis" },
      { title: "Trilhas", icon: Route, path: "/trilhas" },
      { title: "Avaliações", icon: Star, path: "/avaliacoes" },
      { title: "PDI", icon: Target, path: "/pdi" },
    ],
  },
  {
    label: "Jornada & Rotina",
    color: "text-amber-400",
    sectionIcon: Clock,
    items: [
      { title: "Ponto", icon: Clock, path: "/ponto" },
      { title: "Análise de Jornada", icon: BarChart3, path: "/analise-jornada" },
      { title: "Férias", icon: Calendar, path: "/ferias" },
      { title: "Afastamentos", icon: Stethoscope, path: "/atestados" },
      { title: "Saúde Ocupacional (ASO)", icon: HeartPulse, path: "/saude-ocupacional" },
      { title: "Benefícios", icon: Heart, path: "/financeiro/beneficios" },
    ],
  },
  {
    label: "Saúde & Segurança",
    color: "text-amber-400",
    sectionIcon: HeartPulse,
    items: [
      { title: "Compliance SST", icon: FileText, path: "/compliance-sst" },
      {
        title: "Psicossocial",
        icon: Brain,
        path: "/psicossocial",
        children: [
          { title: "Visão Geral", path: "/psicossocial", color: "text-sky-300", dot: "bg-sky-400" },
          { title: "GHE", path: "/psicossocial?tab=ghe", color: "text-cyan-300", dot: "bg-cyan-400" },
          { title: "Campanhas", path: "/psicossocial?tab=campanhas", color: "text-violet-300", dot: "bg-violet-400" },
          { title: "Resultados", path: "/psicossocial?tab=resultados", color: "text-pink-300", dot: "bg-pink-400" },
          { title: "Inventário PGR", path: "/psicossocial?tab=pgr", color: "text-emerald-300", dot: "bg-emerald-400" },
          { title: "Plano de Ação PGR", path: "/psicossocial?tab=plano-acao-pgr", color: "text-teal-300", dot: "bg-teal-400" },
          { title: "Metodologia", path: "/psicossocial?tab=metodologia", color: "text-amber-300", dot: "bg-amber-400" },
        ],
      },
      { title: "Ergonomia", icon: Activity, path: "/ergonomia" },
      { title: "EPIs", icon: Shield, path: "/epis" },
      { title: "Incidentes & Acidentes", icon: ShieldAlert, path: "/incidentes-acidentes" },
    ],
  },
  {
    label: "Documentos & Governança",
    color: "text-rose-400",
    sectionIcon: FileText,
    items: [
      { title: "Documentos", icon: FileText, path: "/documentos" },
      { title: "Hub Contábil", icon: FileText, path: "/hub-contabil" },
    ],
  },
  {
    label: "Financeiro",
    color: "text-teal-400",
    sectionIcon: DollarSign,
    items: [
      { title: "Financeiro", icon: DollarSign, path: "/financeiro" },
    ],
  },
  {
    label: "Academia",
    color: "text-indigo-400",
    sectionIcon: BookOpen,
    items: [{ title: "Academia", icon: BookOpen, path: "/academia" }],
  },
  {
    label: "Sistema",
    color: "text-slate-400",
    sectionIcon: Settings,
    items: [
      { title: "Meu Plano", icon: Layers, path: "/meu-plano" },
      { title: "Suporte", icon: LifeBuoy, path: "/suporte" },
      { title: "Configurações", icon: Settings, path: "/configuracoes" },
      { title: "Sobre o Sistema", icon: Info, path: "/sobre-sistema" },
    ],
  },
];

const SidebarSubItem = ({ item, isCollapsed }: { item: MenuItem; isCollapsed: boolean }) => {
  const location = useLocation();
  const { isLocked, planNameForPath } = usePlanLock();
  const hasActiveChild = item.children?.some((c) =>
    checkIsActive(c.path, location.pathname, location.search)
  ) ?? false;
  const [isOpen, setIsOpen] = useState(hasActiveChild);
  const parentLocked = isLocked(item.path);

  // Grupo inteiro fora do plano: cadeia o próprio cabeçalho (com o aviso de
  // upgrade), sem precisar expandir para ver os subitens cadeados.
  if (parentLocked) {
    const plano = planNameForPath(item.path || "") ?? "superior";
    return (
      <button
        type="button"
        title={`Disponível no plano ${plano}`}
        onClick={() =>
          toast.info(`"${item.title}" faz parte do plano ${plano}.`, {
            description: "Fale com o suporte para liberar este módulo.",
          })
        }
        className={cn(
          "w-full flex items-center gap-3 rounded-lg transition-all duration-200 text-sidebar-foreground/40 hover:bg-white/[0.04]",
          isCollapsed ? "justify-center py-2.5 relative" : "px-3 py-2.5 text-left"
        )}
      >
        <item.icon className="w-[18px] h-[18px] flex-shrink-0 opacity-60" strokeWidth={1.75} />
        {!isCollapsed && <span className="flex-1 text-left text-[13px] font-medium">{item.title}</span>}
        {isCollapsed ? (
          <Lock className="absolute right-1.5 bottom-1.5 w-2.5 h-2.5 opacity-70" strokeWidth={2.5} />
        ) : (
          <Lock className="w-3.5 h-3.5 flex-shrink-0 opacity-60" strokeWidth={2} />
        )}
      </button>
    );
  }

  return (
    <div>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={cn(
          "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200",
          "hover:bg-white/[0.06] text-sidebar-foreground/70 hover:text-sidebar-foreground",
          isOpen && "bg-white/[0.06] text-sidebar-foreground"
        )}
      >
        <item.icon className="w-[18px] h-[18px] flex-shrink-0 opacity-75" strokeWidth={1.75} />
        {!isCollapsed && (
          <>
            <span className="flex-1 text-left text-[13px] font-medium">{item.title}</span>
            <ChevronDown
              className={cn(
                "w-3.5 h-3.5 opacity-40 transition-transform duration-200",
                isOpen && "rotate-180"
              )}
            />
          </>
        )}
      </button>
      <AnimatePresence>
        {isOpen && !isCollapsed && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="overflow-hidden"
          >
            <div className="ml-7 mt-1 space-y-0.5 border-l-2 border-white/[0.08] pl-3">
              {item.children?.map((child) => {
                const isActive = checkIsActive(child.path, location.pathname, location.search);
                if (isLocked(child.path)) {
                  const plano = planNameForPath(child.path) ?? "superior";
                  return (
                    <button
                      key={child.path}
                      type="button"
                      title={`Disponível no plano ${plano}`}
                      onClick={() =>
                        toast.info(`"${child.title}" faz parte do plano ${plano}.`, {
                          description: "Fale com o suporte para liberar este módulo.",
                        })
                      }
                      className="w-full text-left flex items-center gap-2 px-3 py-2 rounded-lg text-[13px] transition-all duration-200 text-sidebar-foreground/35 hover:bg-white/[0.04]"
                    >
                      <span className="w-1.5 h-1.5 rounded-full flex-shrink-0 bg-sidebar-foreground/25" />
                      <span className="flex-1">{child.title}</span>
                      <Lock className="w-3 h-3 flex-shrink-0 opacity-60" strokeWidth={2} />
                    </button>
                  );
                }
                return (
                  <NavLink
                    key={child.path}
                    to={child.path}
                    className={cn(
                      "flex items-center gap-2 px-3 py-2 rounded-lg text-[13px] transition-all duration-200",
                      isActive
                        ? "bg-sidebar-primary text-sidebar-primary-foreground font-medium shadow-md shadow-sidebar-primary/20"
                        : cn("hover:bg-white/[0.06]", child.color ?? "text-sidebar-foreground/55")
                    )}
                  >
                    <span
                      className={cn(
                        "w-1.5 h-1.5 rounded-full flex-shrink-0 transition-all",
                        isActive ? "bg-sidebar-primary-foreground" : (child.dot ?? "bg-sidebar-foreground/40")
                      )}
                    />
                    <span>{child.title}</span>
                  </NavLink>
                );
              })}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

const SidebarLink = ({ item, onNavigate }: { item: MenuItem; isCollapsed: boolean; onNavigate?: () => void }) => {
  const location = useLocation();
  const { isLocked, planNameForPath } = usePlanLock();
  const isActive = checkIsActive(item.path || "/", location.pathname, location.search);
  const locked = isLocked(item.path);

  if (locked) {
    const plano = planNameForPath(item.path || "") ?? "superior";
    return (
      <button
        type="button"
        title={`Disponível no plano ${plano}`}
        onClick={() =>
          toast.info(`"${item.title}" faz parte do plano ${plano}.`, {
            description: "Fale com o suporte para liberar este módulo.",
          })
        }
        className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 text-left text-sidebar-foreground/40 hover:bg-white/[0.04]"
      >
        <item.icon className="w-[18px] h-[18px] flex-shrink-0 opacity-60" strokeWidth={1.75} />
        <span className="text-[13px] flex-1">{item.title}</span>
        <Lock className="w-3.5 h-3.5 flex-shrink-0 opacity-60" strokeWidth={2} />
      </button>
    );
  }

  return (
    <NavLink
      to={item.path || "/"}
      onClick={onNavigate}
      className={cn(
        "relative flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 group/link",
        // (5) Barra lateral no ativo
        "before:absolute before:left-0 before:top-1/2 before:-translate-y-1/2 before:w-[3px] before:rounded-r-full before:transition-all before:duration-200",
        isActive
          ? "bg-sidebar-primary text-sidebar-primary-foreground font-medium shadow-md shadow-sidebar-primary/20 before:h-5 before:bg-sidebar-primary-foreground"
          : "text-sidebar-foreground/70 hover:bg-white/[0.06] hover:text-sidebar-foreground before:h-0 before:bg-transparent"
      )}
    >
      <item.icon
        className={cn("w-[18px] h-[18px] flex-shrink-0 transition-colors", !isActive && "opacity-75")}
        strokeWidth={1.75}
      />
      <span className="text-[13px]">{item.title}</span>
    </NavLink>
  );
};

const CollapsibleSection = ({
  section,
  isCollapsed,
  isOpen,
  onToggle,
  onNavigate,
}: {
  section: MenuSection;
  isCollapsed: boolean;
  isOpen: boolean;
  onToggle: () => void;
  onNavigate?: () => void;
}) => {
  const location = useLocation();
  const { isLocked, planNameForPath } = usePlanLock();

  const hasActiveChild = section.items.some(
    (item) =>
      checkIsActive(item.path || "/", location.pathname, location.search) ||
      item.children?.some((c) => checkIsActive(c.path, location.pathname, location.search))
  );

  if (isCollapsed) {
    return (
      <div className="mb-1">
        <div className="pt-1 flex items-center justify-center px-2 mb-1">
          <section.sectionIcon
            className={cn("w-4 h-4", section.color, "opacity-50")}
            strokeWidth={1.75}
          />
        </div>
        {section.items.map((item) => {
          const isActive = checkIsActive(item.path || "/", location.pathname, location.search);
          if (!item.children && isLocked(item.path)) {
            const plano = planNameForPath(item.path || "") ?? "superior";
            return (
              <button
                key={item.title}
                type="button"
                title={`${item.title} — disponível no plano ${plano}`}
                onClick={() =>
                  toast.info(`"${item.title}" faz parte do plano ${plano}.`, {
                    description: "Fale com o suporte para liberar este módulo.",
                  })
                }
                className="relative w-full flex items-center justify-center py-2.5 rounded-lg transition-all duration-200 my-0.5 text-sidebar-foreground/40 hover:bg-white/[0.04]"
              >
                <item.icon className="w-[18px] h-[18px] opacity-60" strokeWidth={1.75} />
                <Lock className="absolute right-1.5 bottom-1.5 w-2.5 h-2.5 opacity-70" strokeWidth={2.5} />
              </button>
            );
          }
          return item.children ? (
            <SidebarSubItem key={item.title} item={item} isCollapsed={isCollapsed} />
          ) : (
            <NavLink
              key={item.title}
              to={item.path || "/"}
              className={cn(
                "flex items-center justify-center py-2.5 rounded-lg transition-all duration-200 my-0.5",
                isActive
                  ? "bg-sidebar-primary text-sidebar-primary-foreground shadow-md shadow-sidebar-primary/20"
                  : "text-sidebar-foreground/70 hover:bg-white/[0.06] hover:text-sidebar-foreground"
              )}
            >
              <item.icon className="w-[18px] h-[18px]" strokeWidth={1.75} />
            </NavLink>
          );
        })}
      </div>
    );
  }

  return (
    <div
      className={cn(
        // (1) Container visual quando expandido
        "rounded-xl transition-all duration-200",
        isOpen
          ? "bg-white/[0.10] border border-white/[0.14] p-1 shadow-sm shadow-black/5"
          : "border border-transparent"
      )}
    >
      <button
        onClick={onToggle}
        className={cn(
          "w-full flex items-center gap-2.5 px-3 py-2 rounded-lg transition-all duration-200",
          "hover:bg-white/[0.04] group cursor-pointer",
          // (3) Pai destacado quando aberto ou com filho ativo
          isOpen && "bg-white/[0.06]",
          !isOpen && hasActiveChild && "bg-white/[0.04]"
        )}
      >
        <div
          className={cn(
            "w-6 h-6 rounded-md flex items-center justify-center flex-shrink-0 transition-colors",
            isOpen || hasActiveChild ? "bg-white/[0.12]" : "bg-white/[0.05]"
          )}
        >
          <section.sectionIcon className={cn("w-3.5 h-3.5", section.color)} strokeWidth={2} />
        </div>
        <p
          className={cn(
            "flex-1 text-left text-[13px] font-semibold tracking-[0.02em] transition-colors",
            isOpen || hasActiveChild
              ? "text-sidebar-foreground/90"
              : "text-sidebar-foreground/40 group-hover:text-sidebar-foreground/60"
          )}
        >
          {section.label}
        </p>
        <ChevronDown
          className={cn(
            "w-3.5 h-3.5 text-sidebar-foreground/25 group-hover:text-sidebar-foreground/45 transition-all duration-200",
            isOpen && "rotate-180 text-sidebar-foreground/60"
          )}
        />
      </button>
      <AnimatePresence initial={false}>
        {isOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.2, ease: "easeInOut" }}
            className="overflow-hidden"
          >
            {/* (2) Guia vertical conectando pai e subitens */}
            <div className="space-y-0.5 mt-1 ml-3 pl-3 border-l border-white/[0.08]">
              {section.items.map((item) =>
                item.children ? (
                  <SidebarSubItem key={item.title} item={item} isCollapsed={false} />
                ) : (
                  <SidebarLink key={item.title} item={item} isCollapsed={false} onNavigate={onNavigate} />
                )
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

interface AppSidebarProps {
  isCollapsed: boolean;
  onToggle: () => void;
  isMobile?: boolean;
  onClose?: () => void;
}


export const AppSidebar = ({ isCollapsed, onToggle, isMobile, onClose }: AppSidebarProps) => {
  const location = useLocation();
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState("");
  const searchInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        searchInputRef.current?.focus();
      } else if (e.key === "Escape" && document.activeElement === searchInputRef.current) {
        setSearchQuery("");
        searchInputRef.current?.blur();
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);
  const { isSuperAdmin } = useAuthContext();
  const { temAcessoModulo, temAcessoModuloAdmin, perfilVinculado, isOwner } = usePerfilPermissions();

  const isItemAllowed = useMemo(() => {
    return (path?: string) => {
      if (!path) return true;
      if (isSuperAdmin || isOwner || !perfilVinculado) return true;
      const cleanPath = path.split("?")[0].split("#")[0];
      if (ALWAYS_ALLOWED_PATHS.has(cleanPath)) return true;
      const modulo = getModuloForPath(path);
      if (!modulo) return false;
      // Rotas administrativas exigem escopo ≠ proprio_usuario
      if (isAdminPath(path)) return temAcessoModuloAdmin(modulo);
      return temAcessoModulo(modulo);
    };
  }, [isSuperAdmin, isOwner, perfilVinculado, temAcessoModulo, temAcessoModuloAdmin]);

  const filteredSections = useMemo(() => {
    const base = isSuperAdmin ? menuSections : menuSections.filter((s) => s.label !== "Academia");
    // Filtra itens (e seções vazias) por perfil de acesso
    return base
      .map((section) => ({
        ...section,
        items: section.items
          .map((item) => {
            if (item.children) {
              const allowedChildren = item.children.filter((c) => isItemAllowed(c.path));
              if (allowedChildren.length === 0 && !isItemAllowed(item.path)) return null;
              return { ...item, children: allowedChildren };
            }
            return isItemAllowed(item.path) ? item : null;
          })
          .filter(Boolean) as typeof section.items,
      }))
      .filter((section) => section.items.length > 0);
  }, [isSuperAdmin, isItemAllowed]);

  const allItems = useMemo(() => {
    const items: { title: string; path: string; icon: React.ElementType; sectionLabel: string }[] = [];
    
    // Add direct links
    items.push({ title: "Início", path: "/", icon: Home, sectionLabel: "Início" });


    filteredSections.forEach((section) => {
      section.items.forEach((item) => {
        if (item.path)
          items.push({ title: item.title, path: item.path, icon: item.icon, sectionLabel: section.label });
        item.children?.forEach((child) => {
          items.push({ title: child.title, path: child.path, icon: item.icon, sectionLabel: section.label });
        });
      });
      // Pendências removed from sidebar search as it's now only on dashboard
    });
    return items;
  }, [filteredSections]);

  const normalizedQuery = useMemo(() => normalizeSearchText(searchQuery), [searchQuery]);

  const searchResults = useMemo(() => {
    if (!normalizedQuery) return [];
    return allItems.filter((item) => {
      const normalizedTitle = normalizeSearchText(item.title);
      const normalizedSection = normalizeSearchText(item.sectionLabel);
      const keywords = SEARCH_KEYWORDS[item.path] || [];
      return (
        normalizedTitle.includes(normalizedQuery) ||
        normalizedSection.includes(normalizedQuery) ||
        keywords.some((k) => normalizeSearchText(k).includes(normalizedQuery))
      );
    });
  }, [normalizedQuery, allItems]);

  const isSearching = normalizedQuery.length > 0;

  const [openSections, setOpenSections] = useState<Record<string, boolean>>(() => {
    const initial: Record<string, boolean> = {};
    filteredSections.forEach((section) => {
      const hasActive = section.items.some(
        (item) =>
          checkIsActive(item.path || "/", location.pathname, location.search) ||
          item.children?.some((c) => checkIsActive(c.path, location.pathname, location.search))
      );
      initial[section.label] = hasActive;
    });
    return initial;
  });

  const toggleSection = (label: string) => {
    setOpenSections((prev) => ({ ...prev, [label]: !prev[label] }));
  };

  return (
    <motion.aside
      initial={false}
      animate={{ 
        width: isCollapsed ? 72 : 264,
        x: 0,
        opacity: 1
      }}
      transition={{ duration: 0.3, ease: "easeInOut" }}
      className={cn(
        "h-screen gradient-sidebar border-r border-white/[0.06] flex flex-col fixed left-0 top-0 z-40",
        isMobile && "shadow-2xl shadow-black/50"
      )}
    >
      {/* Logo */}
      <div className="p-4 flex items-center justify-between border-b border-white/[0.08] bg-white rounded-b-xl relative group/logo">
        <div className="flex-1 flex justify-center">
          <Logo size="md" showText={false} />
        </div>
        
        {!isMobile && (
          <button
            onClick={onToggle}
            className="absolute -right-3 top-1/2 -translate-y-1/2 w-6 h-6 rounded-full bg-sidebar-primary text-sidebar-primary-foreground flex items-center justify-center shadow-lg opacity-0 group-hover/logo:opacity-100 transition-opacity z-50 border border-white/10"
            title={isCollapsed ? "Expandir menu" : "Recolher menu"}
          >
            {isCollapsed ? <ChevronRight className="w-3.5 h-3.5" /> : <ChevronLeft className="w-3.5 h-3.5" />}
          </button>
        )}
      </div>


      {/* Search */}
      {!isCollapsed && (
        <div className="px-3 pt-4 pb-2">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-sidebar-foreground/35" />
            <input
              ref={searchInputRef}
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Buscar módulos, páginas... (Ctrl+K)"
              className="w-full pl-9 pr-16 py-2.5 rounded-xl bg-white/[0.07] border border-white/[0.08] text-[13px] text-sidebar-foreground placeholder:text-sidebar-foreground/40 focus:outline-none focus:ring-1 focus:ring-sidebar-primary/60 focus:bg-white/[0.1] focus:border-sidebar-primary/30 transition-all"
            />
            {isSearching ? (
              <button
                onClick={() => setSearchQuery("")}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-sidebar-foreground/35 hover:text-sidebar-foreground transition-colors"
                aria-label="Limpar busca"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            ) : (
              <kbd className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[10px] font-mono text-sidebar-foreground/40 border border-white/10 rounded px-1.5 py-0.5 pointer-events-none">
                ⌘K
              </kbd>
            )}
          </div>
        </div>
      )}

      {/* Navigation */}
      <nav className="flex-1 px-3 py-2 space-y-1 overflow-y-auto scrollbar-thin">
        {isSearching ? (
          <div className="space-y-0.5">
            {searchResults.length === 0 ? (
              <p className="text-[12px] text-sidebar-foreground/35 text-center py-6">
                Nenhum resultado encontrado
              </p>
            ) : (
              searchResults.map((item) => {
                const isActive = checkIsActive(item.path, location.pathname, location.search);
                return (
                  <button
                    key={item.path}
                    onClick={() => {
                      navigate(item.path);
                      setSearchQuery("");
                      if (isMobile && onClose) onClose();
                    }}
                    className={cn(
                      "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 text-left",
                      isActive
                        ? "bg-sidebar-primary text-sidebar-primary-foreground font-medium shadow-md shadow-sidebar-primary/20"
                        : "text-sidebar-foreground/70 hover:bg-white/[0.06] hover:text-sidebar-foreground"
                    )}
                  >
                    <item.icon className="w-[18px] h-[18px] flex-shrink-0 opacity-75" strokeWidth={1.75} />
                    <div className="flex flex-col min-w-0">
                      <span className="text-[13px] truncate">{item.title}</span>
                      <span className="text-[10px] text-sidebar-foreground/30 truncate">
                        {item.sectionLabel}
                      </span>
                    </div>
                  </button>
                );
              })
            )}
          </div>
        ) : (
          <div className="space-y-1">
            <NavLink
              to="/"
              onClick={isMobile ? onClose : undefined}
              className={({ isActive }) =>
                cn(
                  "flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all duration-200 mb-1",
                  "font-semibold",
                  isActive
                    ? "bg-sidebar-primary text-sidebar-primary-foreground shadow-md shadow-sidebar-primary/20"
                    : "text-sidebar-foreground/70 hover:bg-white/[0.06] hover:text-sidebar-foreground"
                )
              }
            >
              <Home className={cn("w-[18px] h-[18px] flex-shrink-0 transition-colors opacity-75")} strokeWidth={1.75} />
              {!isCollapsed && <span className="text-[13px]">Início</span>}
            </NavLink>


            {/* Estrutura Organizacional first */}
            {filteredSections.filter(s => s.label === "Estrutura Organizacional").map((section) => (
              <CollapsibleSection
                key={section.label}
                section={section}
                isCollapsed={isCollapsed}
                isOpen={!!openSections[section.label]}
                onToggle={() => toggleSection(section.label)}
                onNavigate={isMobile ? onClose : undefined}
              />
            ))}


            {filteredSections.filter(s => s.label !== "Estrutura Organizacional").map((section) => (
              <div key={section.label}>
                <CollapsibleSection
                  section={section}
                  isCollapsed={isCollapsed}
                  isOpen={!!openSections[section.label]}
                  onToggle={() => toggleSection(section.label)}
                  onNavigate={isMobile ? onClose : undefined}
                />
                {/* Pendências removed from sidebar */}
              </div>
            ))}
          </div>
        )}
      </nav>

    </motion.aside>
  );
};
