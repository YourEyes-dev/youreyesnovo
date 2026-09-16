import { useState, useRef, useEffect, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { Search, X, ArrowRight } from "lucide-react";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { motion, AnimatePresence } from "framer-motion";

interface SearchItem {
  title: string;
  path: string;
  section: string;
  keywords: string[];
}

const searchItems: SearchItem[] = [
  { title: "Dashboard", path: "/", section: "Visão Geral", keywords: ["início", "home", "painel", "dashboard"] },
  { title: "Estratégia & Governança", path: "/estrategia", section: "Visão Geral", keywords: ["estratégia", "governança", "pilares"] },
  { title: "Compliance SST", path: "/compliance-sst", section: "Saúde & Segurança", keywords: ["compliance", "sst", "segurança", "normas", "documentos técnicos"] },
  { title: "Incidentes & Acidentes", path: "/incidentes-acidentes", section: "Saúde & Segurança", keywords: ["incidente", "acidente", "cat", "ocorrência"] },
  { title: "Ergonomia", path: "/ergonomia", section: "Saúde & Segurança", keywords: ["ergonomia", "nr17", "aep", "aet", "postura"] },
  { title: "Psicossocial NR-01", path: "/psicossocial", section: "Saúde & Segurança", keywords: ["psicossocial", "nr01", "saúde mental", "burnout"] },
  { title: "EPIs", path: "/epis", section: "Saúde & Segurança", keywords: ["epi", "equipamento", "proteção", "entrega", "estoque"] },
  { title: "Plano de Ação", path: "/plano-acao", section: "Planos", keywords: ["plano", "ação", "5w2h", "aco"] },
  { title: "Avaliações", path: "/avaliacoes", section: "Planos", keywords: ["avaliação", "desempenho", "ciclo", "template", "9box"] },
  { title: "PDI", path: "/pdi", section: "Planos", keywords: ["pdi", "desenvolvimento", "individual", "metas"] },
  { title: "Colaboradores", path: "/colaboradores", section: "Pessoas", keywords: ["colaborador", "funcionário", "admissão", "pessoa"] },
  { title: "Contratos de Experiência", path: "/contratos-experiencia", section: "Pessoas", keywords: ["contrato", "experiência", "período"] },
  { title: "Onboarding", path: "/onboarding-rh", section: "Pessoas", keywords: ["onboarding", "integração", "novo colaborador"] },
  { title: "Férias", path: "/ferias", section: "Pessoas", keywords: ["férias", "período aquisitivo", "programação"] },
  { title: "Atestados", path: "/atestados", section: "Pessoas", keywords: ["atestado", "médico", "afastamento", "saúde"] },
  { title: "Bem-Estar", path: "/felicidade", section: "Pessoas", keywords: ["bem-estar", "felicidade", "humor", "gratidão"] },
  { title: "Feedback & Ocorrências", path: "/feedback-ocorrencias", section: "Pessoas", keywords: ["feedback", "ocorrência", "advertência"] },
  { title: "Ouvidoria", path: "/ouvidoria", section: "Pessoas", keywords: ["ouvidoria", "denúncia", "canal", "ética"] },
  { title: "Aprendizado & Papéis", path: "/aprendizado-papeis", section: "Pessoas", keywords: ["aprendizado", "papéis", "academia", "curso"] },
  { title: "Trilhas", path: "/trilhas", section: "Pessoas", keywords: ["trilha", "capacitação", "treinamento", "módulo"] },
  { title: "Cultura & Celebrações", path: "/cultura-celebracoes", section: "Pessoas", keywords: ["cultura", "celebração", "aniversário", "reconhecimento"] },
  { title: "Mural Interno", path: "/feed", section: "Pessoas", keywords: ["mural", "feed", "comunicação", "notícia"] },
  { title: "Ponto", path: "/ponto", section: "Pessoas", keywords: ["ponto", "marcação", "relógio", "jornada"] },
  { title: "Análise de Jornada", path: "/analise-jornada", section: "Pessoas", keywords: ["jornada", "análise", "horas extras", "banco"] },
  { title: "Empresa", path: "/empresa", section: "Estrutura", keywords: ["empresa", "cnpj", "dados"] },
  { title: "Departamentos", path: "/cadastros/departamentos", section: "Cadastros", keywords: ["departamento", "setor", "área"] },
  { title: "Cargos", path: "/cadastros/cargos", section: "Cadastros", keywords: ["cargo", "cargo", "cbo"] },
  { title: "Estabelecimento ou Obra", path: "/cadastros/filiais", section: "Cadastros", keywords: ["filial", "obra", "estabelecimento", "unidade"] },
  { title: "MarketYE — marketplace de serviços", path: "/marketplace", section: "Estrutura", keywords: ["marketye", "marketplace", "especialista", "profissional", "servicos", "rede de parceiros"] },
  { title: "Terceiros & SST", path: "/terceiros", section: "Estrutura", keywords: ["terceiro", "terceirizado", "prestador"] },
  { title: "Documentos", path: "/documentos", section: "Documentos", keywords: ["documento", "arquivo", "pasta", "upload"] },
  { title: "Financeiro", path: "/financeiro", section: "Financeiro", keywords: ["financeiro", "guia", "pagamento", "certidão"] },
  { title: "Benefícios", path: "/financeiro/beneficios", section: "Financeiro", keywords: ["benefício", "vale", "plano saúde"] },
  { title: "Hub Contábil", path: "/hub-contabil", section: "Financeiro", keywords: ["contábil", "hub", "competência", "folha"] },
  { title: "Configurações", path: "/configuracoes", section: "Sistema", keywords: ["configuração", "usuário", "perfil", "acesso", "auditoria"] },
  { title: "Suporte", path: "/suporte", section: "Sistema", keywords: ["suporte", "ticket", "ajuda", "bug"] },
  { title: "Meu Perfil", path: "/meu-perfil", section: "Sistema", keywords: ["meu perfil", "conta", "avatar", "senha"] },
];

export function GlobalSearch() {
  const [query, setQuery] = useState("");
  const [isOpen, setIsOpen] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  const results = useMemo(() => {
    if (!query.trim()) return [];
    const normalize = (s: string) => s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const q = normalize(query.trim());

    return searchItems.filter((item) => {
      return (
        normalize(item.title).includes(q) ||
        normalize(item.section).includes(q) ||
        item.keywords.some((k) => normalize(k).includes(q))
      );
    }).slice(0, 8);
  }, [query]);

  useEffect(() => {
    setSelectedIndex(0);
  }, [results]);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Keyboard shortcut: Ctrl+K
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "k") {
        e.preventDefault();
        inputRef.current?.focus();
        setIsOpen(true);
      }
      if (e.key === "Escape") {
        setIsOpen(false);
        inputRef.current?.blur();
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);

  const handleSelect = (path: string) => {
    navigate(path);
    setQuery("");
    setIsOpen(false);
    inputRef.current?.blur();
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter" && results[selectedIndex]) {
      handleSelect(results[selectedIndex].path);
    }
  };

  return (
    <div ref={containerRef} className="relative max-w-md flex-1">
      <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
      <Input
        ref={inputRef}
        placeholder="Buscar módulos, páginas... (Ctrl+K)"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setIsOpen(true);
        }}
        onFocus={() => setIsOpen(true)}
        onKeyDown={handleKeyDown}
        className="pl-10 pr-8 bg-muted border border-border text-foreground placeholder:text-muted-foreground focus-visible:ring-primary"
      />
      {query && (
        <button
          onClick={() => { setQuery(""); setIsOpen(false); }}
          className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
        >
          <X className="w-3.5 h-3.5" />
        </button>
      )}

      <AnimatePresence>
        {isOpen && query.trim() && (
          <motion.div
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            transition={{ duration: 0.15 }}
            className="absolute top-full left-0 right-0 mt-1.5 bg-popover border border-border rounded-lg shadow-xl z-50 overflow-hidden"
          >
            {results.length > 0 ? (
              <div className="py-1">
                {results.map((item, i) => (
                  <button
                    key={item.path}
                    onClick={() => handleSelect(item.path)}
                    onMouseEnter={() => setSelectedIndex(i)}
                    className={cn(
                      "w-full flex items-center justify-between px-3 py-2.5 text-sm transition-colors",
                      i === selectedIndex
                        ? "bg-primary/10 text-primary"
                        : "text-foreground hover:bg-muted"
                    )}
                  >
                    <div className="flex items-center gap-2.5">
                      <Search className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                      <div className="text-left">
                        <span className="font-medium">{item.title}</span>
                        <span className="text-xs text-muted-foreground ml-2">{item.section}</span>
                      </div>
                    </div>
                    {i === selectedIndex && <ArrowRight className="w-3.5 h-3.5" />}
                  </button>
                ))}
              </div>
            ) : (
              <div className="px-4 py-6 text-center text-sm text-muted-foreground">
                Nenhum resultado para "<span className="font-medium text-foreground">{query}</span>"
              </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
