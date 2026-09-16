import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { 
  Search, 
  Plus, 
  Download, 
  Upload,
  MoreHorizontal,
  Mail,
  Phone,
  Building2,
  Calendar,
  ChevronLeft,
  ChevronRight,
  Loader2,
  User,
  Users,
  Briefcase,
  MapPin,
  X,
  LayoutGrid,
  List,
  FolderOpen,
  UserPlus,
  AlertCircle,
  Share2,
  Copy,
  ExternalLink,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";
import { ColaboradorForm, ColaboradorEditData } from "@/components/colaboradores/ColaboradorForm";
import { ImportPlanilhaModal } from "@/components/import/ImportPlanilhaModal";
import type { ResultadoImportacao } from "@/hooks/useImportacaoPlanilha";
import { DesligamentoForm } from "@/components/admissao/DesligamentoForm";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useAuthContext } from "@/contexts/AuthContext";
import { toast } from "sonner";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";

// Admissão imports
import { AdmissaoStats } from "@/components/admissao/AdmissaoStats";
import { AdmissaoList } from "@/components/admissao/AdmissaoList";
import { AdmissaoForm } from "@/components/admissao/AdmissaoForm";
import { AdmissaoDetail } from "@/components/admissao/AdmissaoDetail";
import { useAdmissoes } from "@/hooks/useAdmissoes";
import { AdmissaoFormData } from "@/types/database";
import { useEmpresaAtiva } from "@/contexts/EmpresaAtivaContext";
import { useAfastamentosAtivos } from "@/hooks/useAfastamentosAtivos";
import { AfastadoBadge } from "@/components/shared/AfastadoBadge";
import { usePerfilPermissions } from "@/hooks/usePerfilPermissions";
import { useStorageImageUrl } from "@/hooks/useStorageImageUrl";

function formatPhone(phone: string | null | undefined): string {
  if (!phone) return "-";
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 11) return `(${digits.slice(0,2)}) ${digits.slice(2,7)}-${digits.slice(7)}`;
  if (digits.length === 10) return `(${digits.slice(0,2)}) ${digits.slice(2,6)}-${digits.slice(6)}`;
  return phone;
}

/** Formata YYYY-MM-DD como DD/MM/YYYY sem aplicar timezone (evita off-by-one). */
function formatDateBR(value: string | null | undefined): string {
  if (!value) return "-";
  const m = String(value).match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[3]}/${m[2]}/${m[1]}`;
  const d = new Date(value);
  return isNaN(d.getTime()) ? "-" : d.toLocaleDateString("pt-BR");
}

interface ColaboradorExtendido {
  id: string;
  nome_completo: string;
  email: string;
  celular: string | null;
  cargo: string;
  departamento: string | null;
  data_admissao: string | null;
  status: string;
  cpf: string;
  filial: string | null;
  tipo_contrato: string | null;
  onboarding_token: string | null;
  onboarding_status: string | null;
  foto_url: string | null;
}

function ColaboradorAvatar({ fotoUrl, nome }: { fotoUrl: string | null; nome: string }) {
  const resolvedPhotoUrl = useStorageImageUrl(fotoUrl, "documentos");

  return (
    <Avatar className="h-12 w-12">
      <AvatarImage src={resolvedPhotoUrl || ""} />
      <AvatarFallback className="bg-primary/10 text-primary font-semibold">
        {nome.split(" ").map((n) => n[0]).join("").slice(0, 2)}
      </AvatarFallback>
    </Avatar>
  );
}

function ColaboradorAvatarSmall({ fotoUrl, nome }: { fotoUrl: string | null; nome: string }) {
  const resolvedPhotoUrl = useStorageImageUrl(fotoUrl, "documentos");

  return (
    <Avatar className="h-9 w-9">
      <AvatarImage src={resolvedPhotoUrl || ""} />
      <AvatarFallback className="bg-primary/10 text-primary text-sm font-semibold">
        {nome.split(" ").map((n) => n[0]).join("").slice(0, 2)}
      </AvatarFallback>
    </Avatar>
  );
}

const statusStyles: Record<string, string> = {
  concluido: "bg-success/10 text-success border-success/20",
  ativo: "bg-success/10 text-success border-success/20",
  ferias: "bg-info/10 text-info border-info/20",
  afastado: "bg-warning/10 text-warning border-warning/20",
  desligado: "bg-muted text-muted-foreground border-muted",
  inativo: "bg-muted text-muted-foreground border-muted",
};

const statusLabels: Record<string, string> = {
  concluido: "Ativo",
  ativo: "Ativo",
  ferias: "Férias",
  afastado: "Afastado",
  desligado: "Desligado",
  inativo: "Inativo",
};

// Resolve o status visível considerando a flag `inativo` (sobrescreve status base)
function resolveStatus(colab: { status: string; inativo?: boolean | null }): { key: string; label: string } {
  if ((colab as any).inativo) return { key: "inativo", label: "Inativo" };
  const key = colab.status || "concluido";
  return { key, label: statusLabels[key] || "Ativo" };
}

// ========== Ativos Tab Component ==========
function AtivosTab({ showImport, setShowImport }: { showImport: boolean; setShowImport: (v: boolean) => void }) {
  const navigate = useNavigate();
  const { tenantId } = useAuth();
  const { temPermissao, isOwner, podeExportar, podeExcluir } = usePerfilPermissions();

  const queryClient = useQueryClient();
  const { empresaAtivaId } = useEmpresaAtiva();
  const { getAfastamento } = useAfastamentosAtivos();
  const [searchTerm, setSearchTerm] = useState("");
  const [departmentFilter, setDepartmentFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [estabelecimentoFilter, setEstabelecimentoFilter] = useState<string>("todos");

  const [showForm, setShowForm] = useState(false);
  const [showNovoChoice, setShowNovoChoice] = useState(false);
  const [selectedColaborador, setSelectedColaborador] = useState<ColaboradorExtendido | null>(null);
  const [showDetail, setShowDetail] = useState(false);
  const [editingColaborador, setEditingColaborador] = useState<ColaboradorEditData | null>(null);
  const [viewMode, setViewMode] = useState<"cards" | "list">("cards");
  const [desligarColab, setDesligarColab] = useState<ColaboradorExtendido | null>(null);
  const [inativarColab, setInativarColab] = useState<ColaboradorExtendido | null>(null);
  const [inativarMotivo, setInativarMotivo] = useState("");
  const [excluirColab, setExcluirColab] = useState<ColaboradorExtendido | null>(null);
  const [excluirText, setExcluirText] = useState("");
  const [excluirVinculos, setExcluirVinculos] = useState<{ tem: boolean; detalhes: any } | null>(null);
  const [excluirChecking, setExcluirChecking] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const canEditColaborador = isOwner || temPermissao("colaboradores", "editar");

  const checkVinculosEAbrirExcluir = async (colab: ColaboradorExtendido) => {
    setExcluirColab(colab);
    setExcluirText("");
    setExcluirVinculos(null);
    setExcluirChecking(true);
    try {
      const { data, error } = await (supabase as any).rpc("colaborador_tem_vinculos", { _admissao_id: colab.id });
      if (error) throw error;
      setExcluirVinculos({ tem: !!data?.tem_vinculos, detalhes: data?.detalhes || {} });
    } catch (e: any) {
      toast.error("Erro ao verificar vínculos: " + (e.message || e));
      setExcluirColab(null);
    } finally {
      setExcluirChecking(false);
    }
  };

  const handleConfirmInativar = async () => {
    if (!inativarColab) return;
    setActionLoading(true);
    try {
      const reverter = !!(inativarColab as any).inativo;
      const { error } = await (supabase as any).rpc("inativar_colaborador", {
        _admissao_id: inativarColab.id,
        _motivo: inativarMotivo || null,
        _reverter: reverter,
      });
      if (error) throw error;
      toast.success(reverter ? "Colaborador reativado" : "Colaborador inativado");
      setInativarColab(null);
      setInativarMotivo("");
      refetch();
    } catch (e: any) {
      toast.error("Erro: " + (e.message || e));
    } finally {
      setActionLoading(false);
    }
  };

  const handleConfirmExcluir = async () => {
    if (!excluirColab) return;
    setActionLoading(true);
    try {
      const forcado = !!excluirVinculos?.tem;
      const { data, error } = await (supabase as any).rpc(
        forcado ? "excluir_colaborador_forcado" : "excluir_colaborador_seguro",
        { _admissao_id: excluirColab.id }
      );
      if (error) throw error;
      toast.success(forcado ? "Colaborador e todo o histórico excluídos" : "Colaborador excluído");
      setExcluirColab(null);
      setExcluirText("");
      refetch();
    } catch (e: any) {
      toast.error("Erro ao excluir: " + (e.message || e));
    } finally {
      setActionLoading(false);
    }
  };

  useEffect(() => {
    const handleNovoCadastro = () => setShowNovoChoice(true);
    window.addEventListener('novo-cadastro-colaborador', handleNovoCadastro);
    return () => window.removeEventListener('novo-cadastro-colaborador', handleNovoCadastro);
  }, []);

  const handleExportarColaboradores = () => {
    if (filteredColaboradores.length === 0) {
      toast.error("Nenhum colaborador para exportar.");
      return;
    }
    import("xlsx").then((XLSX) => {
      const dados = filteredColaboradores.map((c) => ({
        Nome: c.nome_completo,
        CPF: c.cpf,
        Email: c.email,
        Celular: c.celular || "",
        Cargo: c.cargo,
        Departamento: c.departamento || "",
        // Mesmo nome do campo no cadastro e do filtro novo — "Filial" era
        // um terceiro nome para a mesma coisa.
        "Estabelecimento / Obra": c.filial || "",
        "Tipo Contrato": c.tipo_contrato || "",
        "Data Admissão": c.data_admissao || "",
        Status: statusLabels[c.status] || c.status,
      }));
      const ws = XLSX.utils.json_to_sheet(dados);
      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, "Colaboradores");
      XLSX.writeFile(wb, `colaboradores_${new Date().toISOString().split("T")[0]}.xlsx`);
      toast.success("Planilha exportada com sucesso!");
    });
  };

  const handleEditColaborador = async (colab: ColaboradorExtendido) => {
    if (!canEditColaborador) {
      toast.error("Você não tem permissão para editar colaboradores.");
      return;
    }

    // Busca o registro completo para evitar perder campos não carregados na listagem
    // (centro_custo, gestor_imediato, matricula_esocial, cbo, etc.)
    const { data: full, error: fullErr } = await supabase
      .from("admissoes")
      .select("id, nome_completo, cpf, email, celular, tipo_contrato, cargo, departamento, filial, centro_custo, gestor_imediato, data_admissao, matricula_esocial, cbo, foto_url, bate_ponto, art62_inciso, art62_documento, teletrabalho_modalidade")
      .eq("id", colab.id)
      .maybeSingle();

    if (fullErr) {
      toast.error("Não foi possível carregar os dados completos do colaborador.");
      return;
    }

    const src: any = full || colab;
    setEditingColaborador({
      id: colab.id,
      nome_completo: src.nome_completo ?? colab.nome_completo,
      cpf: src.cpf ?? colab.cpf,
      email: src.email ?? colab.email,
      celular: src.celular ?? colab.celular,
      tipo_contrato: src.tipo_contrato ?? colab.tipo_contrato,
      cargo: src.cargo ?? colab.cargo,
      departamento: src.departamento ?? colab.departamento,
      filial: src.filial ?? colab.filial,
      centro_custo: src.centro_custo ?? null,
      gestor_imediato: src.gestor_imediato ?? null,
      data_admissao: src.data_admissao ?? colab.data_admissao,
      matricula_esocial: src.matricula_esocial ?? null,
      cbo: src.cbo ?? null,
      foto_url: src.foto_url ?? colab.foto_url,
      bate_ponto: src.bate_ponto,
      art62_inciso: src.art62_inciso,
      art62_documento: src.art62_documento,
      teletrabalho_modalidade: src.teletrabalho_modalidade,
    });
    setShowForm(true);
  };

  const handleCloseForm = (open: boolean) => {
    setShowForm(open);
    if (!open) setEditingColaborador(null);
  };

  const handleViewProfile = (colab: ColaboradorExtendido) => {
    setSelectedColaborador(colab);
    setShowDetail(true);
  };

  const handleImportSuccess = () => {
    queryClient.invalidateQueries({ queryKey: ["colaboradores-list"] });
    queryClient.invalidateQueries({ queryKey: ["colaboradores"] });
    queryClient.invalidateQueries({ queryKey: ["cargos"] });
    queryClient.invalidateQueries({ queryKey: ["departamentos"] });
  };

  const { data: colaboradores = [], isLoading, refetch } = useQuery({
    queryKey: ["colaboradores-list", tenantId, empresaAtivaId],
    queryFn: async (): Promise<ColaboradorExtendido[]> => {
      if (!tenantId) return [];
      // Paginate to bypass Supabase 1000-row default limit
      const PAGE = 1000;
      const acc: any[] = [];
      let from = 0;
      for (let i = 0; i < 100; i++) {
        let q = supabase
          .from("admissoes")
          .select("id, nome_completo, cpf, cargo, departamento, email, celular, filial, data_admissao, status, tipo_contrato, onboarding_token, onboarding_status, foto_url, inativo")
          .eq("tenant_id", tenantId)
          .eq("status", "concluido");
        if (empresaAtivaId) q = q.eq("empresa_id", empresaAtivaId);
        // Ordenação determinística: nome_completo pode ter homônimos (vários
        // "Tavares"), e sem desempate por uma coluna única o .range() entre
        // páginas pode repetir/pular linhas. Desempata por id.
        const { data, error } = await q
          .order("nome_completo")
          .order("id")
          .range(from, from + PAGE - 1);
        if (error) throw error;
        const chunk = data || [];
        acc.push(...chunk);
        if (chunk.length < PAGE) break;
        from += PAGE;
      }
      // Blindagem extra: remove eventuais ids repetidos antes de renderizar.
      const vistos = new Set<string>();
      return acc.filter((c) => (vistos.has(c.id) ? false : (vistos.add(c.id), true)));
    },
    enabled: !!tenantId,
  });

  // Tipos de vínculo considerados PJ/CNPJ
  const PJ_TIPOS = new Set(["pj", "prolabore", "pro_labore", "terceiro", "terceirizado", "autonomo"]);
  const isPJ = (tc: string | null | undefined) =>
    PJ_TIPOS.has((tc || "").toString().trim().toLowerCase());

  const filteredColaboradores = colaboradores.filter((colab) => {
    const matchesSearch = 
      colab.nome_completo.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (colab.email || "").toLowerCase().includes(searchTerm.toLowerCase()) ||
      colab.cargo.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesDepartment = departmentFilter === "all" || colab.departamento === departmentFilter;
    const matchesStatus = statusFilter === "all" || colab.status === statusFilter;
    // Vínculo: CLT (não-PJ) | PJ (somente ativos) | Todos (oculta PJ inativos)
    // O filtro CLT/PJ saiu (pedido dos usuários: dava menos resultado do que
    // ocupava espaço), mas a regra que morava no seu ramo "todos" FICA: PJ
    // inativo continua oculto. Apagar o Select sem trazer esta linha junto
    // faria prestadores desligados reaparecerem na lista de ativos — efeito
    // colateral silencioso de uma remoção que parecia inofensiva.
    const ehPJ = isPJ(colab.tipo_contrato);
    const inativo = !!(colab as any).inativo;
    const matchesVinculo = !ehPJ || !inativo;

    // No lugar dele, o filtro por Estabelecimento / Obra. O dado já vem na
    // consulta (admissoes.filial) e é o mesmo que o cadastro do colaborador
    // grava no campo "Estabelecimento / Obra" — que guarda o NOME, não o id.
    const matchesEstabelecimento =
      estabelecimentoFilter === "todos" ||
      (colab.filial || "").trim() === estabelecimentoFilter;

    return matchesSearch && matchesDepartment && matchesStatus
      && matchesVinculo && matchesEstabelecimento;
  });


  const estabelecimentos = [
    ...new Set(
      colaboradores
        .map((c) => c.filial)
        .filter((f): f is string => typeof f === "string" && f.trim().length > 0)
        .map((f) => f.trim()),
    ),
  ].sort((a, b) => a.localeCompare(b, "pt-BR"));

  const departments = [
    ...new Set(
      colaboradores
        .map((c) => c.departamento)
        .filter((d): d is string => typeof d === "string" && d.trim().length > 0)
        .map((d) => d.trim()),
    ),
  ];

  return (
    <div className="space-y-6">
      {/* Filters */}

      <div className="bg-card rounded-xl border border-border p-4 shadow-sm">
        <div className="flex flex-col md:flex-row gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Buscar por nome, email ou função..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10"
            />
          </div>
          <Select value={departmentFilter} onValueChange={setDepartmentFilter}>
            <SelectTrigger className="w-full md:w-[200px]">
              <SelectValue placeholder="Departamento" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos Departamentos</SelectItem>
              {departments
                .filter((dept) => dept != null && String(dept).trim() !== "")
                .map((dept) => (
                  <SelectItem key={dept} value={dept}>{dept}</SelectItem>
                ))}
            </SelectContent>
          </Select>
          <Select value={estabelecimentoFilter} onValueChange={setEstabelecimentoFilter}>
            <SelectTrigger className="w-full md:w-[200px]">
              <SelectValue placeholder="Estabelecimento / Obra" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="todos">Todos os estabelecimentos</SelectItem>
              {estabelecimentos.map((est) => (
                <SelectItem key={est} value={est}>{est}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          {podeExportar("colaboradores") && (
            <Button variant="outline" size="icon" onClick={handleExportarColaboradores} title="Exportar colaboradores">
              <Download className="w-4 h-4" />
            </Button>
          )}

        </div>
      </div>

      {/* Results Count & View Toggle */}
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          Mostrando <span className="font-medium text-foreground">{filteredColaboradores.length}</span> de{" "}
          <span className="font-medium text-foreground">{colaboradores.length}</span> colaboradores
        </p>
        <ToggleGroup type="single" value={viewMode} onValueChange={(value) => value && setViewMode(value as "cards" | "list")}>
          <ToggleGroupItem value="cards" aria-label="Visualização em cards" className="h-9 px-3">
            <LayoutGrid className="w-4 h-4" />
          </ToggleGroupItem>
          <ToggleGroupItem value="list" aria-label="Visualização em lista" className="h-9 px-3">
            <List className="w-4 h-4" />
          </ToggleGroupItem>
        </ToggleGroup>
      </div>

      {/* Content */}
      {isLoading ? (
        <div className="flex items-center justify-center py-12">
          <Loader2 className="w-8 h-8 animate-spin text-primary" />
        </div>
      ) : colaboradores.length === 0 ? (
        <div className="text-center py-12 bg-card rounded-xl border border-border">
          <p className="text-muted-foreground mb-4">Nenhum colaborador cadastrado ainda.</p>
          <Button onClick={() => setShowNovoChoice(true)}>
            <Plus className="w-4 h-4 mr-2" />
            Cadastrar Primeiro Colaborador
          </Button>
        </div>
      ) : filteredColaboradores.length === 0 ? (
        <div className="text-center py-12 bg-card rounded-xl border border-border">
          <p className="text-muted-foreground mb-1">
            Nenhum colaborador corresponde aos filtros atuais.
          </p>
          <p className="text-xs text-muted-foreground mb-4">
            {estabelecimentoFilter !== "todos"
              ? `O filtro "${estabelecimentoFilter}" pode estar ocultando colaboradores. Há ${colaboradores.length} cadastrado${colaboradores.length !== 1 ? "s" : ""} nesta empresa.`
              : `Há ${colaboradores.length} colaborador${colaboradores.length !== 1 ? "es" : ""} cadastrado${colaboradores.length !== 1 ? "s" : ""} nesta empresa.`}
          </p>
          <Button
            variant="outline"
            onClick={() => {
              setSearchTerm("");
              setDepartmentFilter("all");
              setStatusFilter("all");
              setEstabelecimentoFilter("todos");
            }}
          >
            Limpar filtros
          </Button>
        </div>
      ) : viewMode === "cards" ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {filteredColaboradores.map((colab, index) => (
            <motion.div
              key={colab.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3, delay: index * 0.05 }}
              className="bg-card rounded-xl border border-border p-5 shadow-sm hover:shadow-md hover:border-primary/30 transition-all group cursor-pointer"
              onClick={() => handleViewProfile(colab)}
            >
              <div className="flex items-start justify-between mb-4">
                <div className="flex items-center gap-3">
                  <ColaboradorAvatar fotoUrl={colab.foto_url} nome={colab.nome_completo} />
                  <div>
                    <h3 className="font-semibold text-foreground group-hover:text-primary transition-colors">
                      {colab.nome_completo}
                    </h3>
                    <p className="text-sm text-muted-foreground">{colab.cargo}</p>
                  </div>
                </div>
                <div onClick={(e) => e.stopPropagation()}>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button data-testid="colab-menu" variant="ghost" size="icon" className="h-8 w-8">
                        <MoreHorizontal className="w-4 h-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onClick={() => handleViewProfile(colab)}>Ver perfil</DropdownMenuItem>
                      <DropdownMenuItem onClick={() => handleEditColaborador(colab)}>Editar</DropdownMenuItem>
                      <DropdownMenuItem onClick={() => navigate(`/documentos?colaborador=${colab.id}`)}>
                        <FolderOpen className="w-4 h-4 mr-2" />
                        Documentos
                      </DropdownMenuItem>
                      <DropdownMenuItem onClick={() => {
                        const token = colab.onboarding_token;
                        if (!token) {
                          toast.error("Token de onboarding não encontrado.");
                          return;
                        }
                        const link = `${window.location.origin}/completar-cadastro/${token}`;
                        navigator.clipboard.writeText(link);
                        toast.success("Link copiado para a área de transferência!");
                      }}>
                        <Share2 className="w-4 h-4 mr-2" />
                        Compartilhar Link
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem onClick={() => { setInativarColab(colab); setInativarMotivo(""); }}>
                        {(colab as any).inativo ? "Reativar" : "Inativar"}
                      </DropdownMenuItem>
                      <DropdownMenuItem data-testid="colab-desligar" className="text-destructive" onClick={() => {
                        if (colab.status === "desligado") { toast.error("Colaborador já está desligado"); return; }
                        setDesligarColab(colab);
                      }}>
                        Desligar
                      </DropdownMenuItem>
                      {podeExcluir("colaboradores") && (
                        <DropdownMenuItem className="text-destructive" onClick={() => checkVinculosEAbrirExcluir(colab)}>
                          Excluir
                        </DropdownMenuItem>
                      )}

                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex items-center gap-2 text-muted-foreground">
                  <Mail className="w-4 h-4" />
                  {colab.email ? (
                    <span className="truncate">{colab.email}</span>
                  ) : (
                    <span className="truncate italic text-muted-foreground/70">E-mail não cadastrado</span>
                  )}
                </div>
                {colab.celular && (
                  <div className="flex items-center gap-2 text-muted-foreground">
                    <Phone className="w-4 h-4" />
                    <span>{formatPhone(colab.celular)}</span>
                  </div>
                )}
                {colab.departamento && (
                  <div className="flex items-center gap-2 text-muted-foreground">
                    <Building2 className="w-4 h-4" />
                    <span>{colab.departamento}</span>
                  </div>
                )}
                {/* Estabelecimento / Obra — ícone distinto do departamento para
                    que as duas linhas não se confundam quando aparecerem juntas. */}
                {colab.filial && (
                  <div className="flex items-center gap-2 text-muted-foreground">
                    <MapPin className="w-4 h-4" />
                    <span>{colab.filial}</span>
                  </div>
                )}
                {colab.data_admissao && (
                  <div className="flex items-center gap-2 text-muted-foreground">
                    <Calendar className="w-4 h-4" />
                    <span>Desde {formatDateBR(colab.data_admissao)}</span>
                  </div>
                )}
              </div>
              <div className="mt-4 pt-4 border-t border-border flex items-center gap-2 flex-wrap">
                {(() => { const s = resolveStatus(colab); return (
                  <Badge className={cn("text-xs", statusStyles[s.key] || statusStyles.concluido)}>{s.label}</Badge>
                ); })()}
                <AfastadoBadge afastamento={getAfastamento({ cpf: colab.cpf, nome: colab.nome_completo })} compact />
              </div>
            </motion.div>
          ))}
        </div>
      ) : (
        <div className="bg-card rounded-xl border border-border shadow-sm overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[300px]">Colaborador</TableHead>
                <TableHead>Cargo</TableHead>
                <TableHead className="hidden md:table-cell">Departamento</TableHead>
                <TableHead className="hidden lg:table-cell">Contato</TableHead>
                <TableHead className="hidden xl:table-cell">Admissão</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="w-[50px]"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredColaboradores.map((colab) => (
                <TableRow key={colab.id} className="cursor-pointer hover:bg-muted/50" onClick={() => handleViewProfile(colab)}>
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <ColaboradorAvatarSmall fotoUrl={colab.foto_url} nome={colab.nome_completo} />
                      <div>
                        <p className="font-medium text-foreground">{colab.nome_completo}</p>
                        <p className={cn("text-xs truncate max-w-[200px]", colab.email ? "text-muted-foreground" : "text-muted-foreground/60 italic")}>{colab.email || "E-mail não cadastrado"}</p>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell className="text-sm">{colab.cargo}</TableCell>
                  <TableCell className="hidden md:table-cell text-sm text-muted-foreground">{colab.departamento || "-"}</TableCell>
                  <TableCell className="hidden lg:table-cell text-sm text-muted-foreground">{formatPhone(colab.celular)}</TableCell>
                  <TableCell className="hidden xl:table-cell text-sm text-muted-foreground">
                    {colab.data_admissao ? formatDateBR(colab.data_admissao) : "-"}
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2 flex-wrap">
                      {(() => { const s = resolveStatus(colab); return (
                        <Badge className={cn("text-xs", statusStyles[s.key] || statusStyles.concluido)}>{s.label}</Badge>
                      ); })()}
                      <AfastadoBadge afastamento={getAfastamento({ cpf: colab.cpf, nome: colab.nome_completo })} compact />
                    </div>
                  </TableCell>
                  <TableCell onClick={(e) => e.stopPropagation()}>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button data-testid="colab-menu" variant="ghost" size="icon" className="h-8 w-8">
                          <MoreHorizontal className="w-4 h-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem onClick={() => handleViewProfile(colab)}>Ver perfil</DropdownMenuItem>
                        <DropdownMenuItem onClick={() => handleEditColaborador(colab)}>Editar</DropdownMenuItem>
                        <DropdownMenuItem onClick={() => navigate(`/documentos?colaborador=${colab.id}`)}>
                          <FolderOpen className="w-4 h-4 mr-2" />
                          Documentos
                        </DropdownMenuItem>
                        <DropdownMenuItem onClick={() => {
                          const link = `${window.location.origin}/completar-cadastro/${colab.onboarding_token}`;
                          navigator.clipboard.writeText(link);
                          toast.success("Link copiado para a área de transferência!");
                        }}>
                          <Copy className="w-4 h-4 mr-2" />
                          Copiar Link de Cadastro
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem onClick={() => { setInativarColab(colab); setInativarMotivo(""); }}>
                          {(colab as any).inativo ? "Reativar" : "Inativar"}
                        </DropdownMenuItem>
                        <DropdownMenuItem data-testid="colab-desligar" className="text-destructive" onClick={() => {
                          if (colab.status === "desligado") { toast.error("Colaborador já está desligado"); return; }
                          setDesligarColab(colab);
                        }}>
                          Desligar
                        </DropdownMenuItem>
                        {podeExcluir("colaboradores") && (
                          <DropdownMenuItem className="text-destructive" onClick={() => checkVinculosEAbrirExcluir(colab)}>
                            Excluir
                          </DropdownMenuItem>
                        )}

                      </DropdownMenuContent>
                    </DropdownMenu>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {/* Choice Dialog: Colaborador vs Terceiro */}
      <Dialog open={showNovoChoice} onOpenChange={setShowNovoChoice}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>O que deseja cadastrar?</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-1 gap-3 pt-2">
            <button
              onClick={() => {
                setShowNovoChoice(false);
                setShowForm(true);
              }}
              className="flex items-center gap-4 p-4 rounded-xl border border-border hover:border-primary/40 hover:bg-primary/5 transition-all text-left group"
            >
              <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                <UserPlus className="w-6 h-6 text-primary" />
              </div>
              <div>
                <p className="font-semibold text-foreground group-hover:text-primary transition-colors">Colaborador</p>
                <p className="text-xs text-muted-foreground">CLT, Estagiário, Temporário — vínculo direto</p>
              </div>
            </button>
            <button
              onClick={() => {
                setShowNovoChoice(false);
                navigate("/terceiros");
              }}
              className="flex items-center gap-4 p-4 rounded-xl border border-border hover:border-accent-foreground/40 hover:bg-accent/30 transition-all text-left group"
            >
              <div className="w-12 h-12 rounded-lg bg-accent/30 flex items-center justify-center shrink-0">
                <Building2 className="w-6 h-6 text-accent-foreground" />
              </div>
              <div>
                <p className="font-semibold text-foreground group-hover:text-accent-foreground transition-colors">Empresa Terceira (PJ / Prestador)</p>
                <p className="text-xs text-muted-foreground">Pessoa Jurídica, empresa prestadora de serviço — módulo Terceiros & SST</p>
              </div>
            </button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Form Modal */}
      <ColaboradorForm open={showForm} onOpenChange={handleCloseForm} onSuccess={() => refetch()} colaborador={editingColaborador} />

      {/* Import Modal moved to parent Colaboradores component to work across all tabs */}

      {/* Detail Modal */}
      <Dialog open={showDetail} onOpenChange={setShowDetail}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-3">
              <Avatar className="h-12 w-12">
                <AvatarFallback className="bg-primary/10 text-primary font-semibold">
                  {selectedColaborador?.nome_completo.split(" ").map(n => n[0]).join("").slice(0, 2)}
                </AvatarFallback>
              </Avatar>
              <div>
                <p className="text-lg font-semibold">{selectedColaborador?.nome_completo}</p>
                <p className="text-sm text-muted-foreground font-normal">{selectedColaborador?.cargo}</p>
              </div>
            </DialogTitle>
          </DialogHeader>
          {selectedColaborador && (
            <div className="space-y-4 mt-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground flex items-center gap-1"><User className="w-3 h-3" /> CPF</p>
                  <p className="text-sm font-medium">{selectedColaborador.cpf.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4")}</p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground flex items-center gap-1"><Mail className="w-3 h-3" /> Email</p>
                  <p className={cn("text-sm font-medium truncate", !selectedColaborador.email && "italic text-muted-foreground/70")}>{selectedColaborador.email || "Não cadastrado"}</p>
                </div>
                {selectedColaborador.celular && (
                  <div className="space-y-1">
                    <p className="text-xs text-muted-foreground flex items-center gap-1"><Phone className="w-3 h-3" /> Celular</p>
                    <p className="text-sm font-medium">{formatPhone(selectedColaborador.celular)}</p>
                  </div>
                )}
                {selectedColaborador.departamento && (
                  <div className="space-y-1">
                    <p className="text-xs text-muted-foreground flex items-center gap-1"><Building2 className="w-3 h-3" /> Departamento</p>
                    <p className="text-sm font-medium">{selectedColaborador.departamento}</p>
                  </div>
                )}
                {selectedColaborador.filial && (
                  <div className="space-y-1">
                    <p className="text-xs text-muted-foreground flex items-center gap-1"><MapPin className="w-3 h-3" /> Filial</p>
                    <p className="text-sm font-medium">{selectedColaborador.filial}</p>
                  </div>
                )}
                {selectedColaborador.data_admissao && (
                  <div className="space-y-1">
                    <p className="text-xs text-muted-foreground flex items-center gap-1"><Calendar className="w-3 h-3" /> Data de Admissão</p>
                    <p className="text-sm font-medium">{formatDateBR(selectedColaborador.data_admissao)}</p>
                  </div>
                )}
              </div>
              <AfastadoBadge afastamento={getAfastamento({ cpf: selectedColaborador.cpf, nome: selectedColaborador.nome_completo })} />
              <div className="pt-4 border-t flex justify-between items-center">
                {(() => { const s = resolveStatus(selectedColaborador); return (
                  <Badge className={cn("text-xs", statusStyles[s.key] || statusStyles.concluido)}>{s.label}</Badge>
                ); })()}
                <Button variant="outline" size="sm" onClick={() => setShowDetail(false)}>Fechar</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Desligamento Form */}
      {desligarColab && (
        <DesligamentoForm
          open={!!desligarColab}
          onOpenChange={(open) => { if (!open) setDesligarColab(null); }}
          admissao={{
            id: desligarColab.id,
            nome_completo: desligarColab.nome_completo,
            cargo: desligarColab.cargo,
            data_admissao: desligarColab.data_admissao,
            tipo_contrato: desligarColab.tipo_contrato,
            status: desligarColab.status,
            cpf: desligarColab.cpf,
          }}
          onConfirmar={async (id, dados) => {
            const { error } = await supabase
              .from("admissoes")
              .update({ ...dados, status: "desligado" } as any)
              .eq("id", id);
            if (error) throw error;
            toast.success("Desligamento registrado com sucesso");
            setDesligarColab(null);
            refetch();
          }}
        />
      )}

      {/* Dialog Inativar/Reativar */}
      <AlertDialog open={!!inativarColab} onOpenChange={(o) => { if (!o) { setInativarColab(null); setInativarMotivo(""); } }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {(inativarColab as any)?.inativo ? "Reativar colaborador" : "Inativar colaborador"}
            </AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-3">
                <p>
                  {(inativarColab as any)?.inativo
                    ? `O colaborador ${inativarColab?.nome_completo} voltará a aparecer nas listagens ativas.`
                    : `${inativarColab?.nome_completo} ficará marcado como inativo. Os registros e vínculos existentes serão preservados.`}
                </p>
                {!(inativarColab as any)?.inativo && (
                  <Input
                    placeholder="Motivo (opcional)"
                    value={inativarMotivo}
                    onChange={(e) => setInativarMotivo(e.target.value)}
                  />
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirmInativar} disabled={actionLoading}>
              {actionLoading ? "Salvando..." : ((inativarColab as any)?.inativo ? "Reativar" : "Inativar")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Dialog Excluir */}
      <AlertDialog open={!!excluirColab} onOpenChange={(o) => { if (!o) { setExcluirColab(null); setExcluirText(""); setExcluirVinculos(null); } }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="text-destructive">Excluir colaborador permanentemente</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-3">
                {excluirChecking && <p>Verificando vínculos no sistema...</p>}
                {!excluirChecking && excluirVinculos?.tem && (
                  <div className="rounded-md border border-destructive/30 bg-destructive/5 p-3 space-y-2">
                    <p className="font-medium text-destructive">⚠️ Colaborador com histórico no sistema</p>
                    <p className="text-sm">
                      <strong>{excluirColab?.nome_completo}</strong> possui registros vinculados nos módulos:
                    </p>
                    <ul className="text-xs list-disc pl-5 text-muted-foreground">
                      {Object.entries(excluirVinculos.detalhes || {}).map(([k, v]) => (
                        <li key={k}>{k.replace(/_/g, " ")}: {String(v)}</li>
                      ))}
                    </ul>
                    <p className="text-sm">
                      Para colaboradores reais, prefira <strong>Inativar</strong> (preserva o histórico).
                      A exclusão forçada apaga <strong>todos os registros acima permanentemente</strong> — use
                      apenas para cadastros de teste. Requer perfil de proprietário/administrador.
                    </p>
                    <p className="text-sm">Para confirmar a exclusão com histórico, digite <strong>EXCLUIR TUDO</strong>:</p>
                    <Input
                      autoFocus
                      value={excluirText}
                      onChange={(e) => setExcluirText(e.target.value)}
                      placeholder="Digite EXCLUIR TUDO"
                    />
                  </div>
                )}
                {!excluirChecking && excluirVinculos && !excluirVinculos.tem && (
                  <>
                    <p>
                      O colaborador <strong>{excluirColab?.nome_completo}</strong> não possui vínculos. Esta ação é
                      <strong> irreversível</strong>.
                    </p>
                    <p>Para confirmar, digite <strong>EXCLUIR</strong>:</p>
                    <Input
                      autoFocus
                      value={excluirText}
                      onChange={(e) => setExcluirText(e.target.value)}
                      placeholder="Digite EXCLUIR"
                    />
                  </>
                )}
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive hover:bg-destructive/90 text-destructive-foreground"
              disabled={
                actionLoading || excluirChecking || !excluirVinculos ||
                (excluirVinculos.tem
                  ? excluirText.trim() !== "EXCLUIR TUDO"
                  : excluirText.trim() !== "EXCLUIR")
              }
              onClick={handleConfirmExcluir}
            >
              {actionLoading
                ? "Excluindo..."
                : excluirVinculos?.tem
                ? "Excluir com todo o histórico"
                : "Excluir definitivamente"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

// ========== Admissões Tab Component ==========
function AdmissoesTab() {
  type ViewMode = "list" | "new" | "edit" | "detail";
  const [viewMode, setViewMode] = useState<ViewMode>("list");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [deleteId, setDeleteId] = useState<string | null>(null);

  const { hasMinimumRole, loading: authLoading } = useAuthContext();

  const {
    admissoes, isLoading, error, criarAdmissao, atualizarAdmissao, atualizarStatus,
    atualizarDocumento, atualizarWorkflow, excluirAdmissao, buscarAdmissao,
    uploadDocumento, isPending,
  } = useAdmissoes();

  const isAdmin = hasMinimumRole("admin");
  const canManage = hasMinimumRole("manager");

  useEffect(() => {
    const handleNovoCadastro = () => {
      setSelectedId(null);
      setViewMode("new");
    };
    window.addEventListener('novo-cadastro-colaborador', handleNovoCadastro);
    return () => window.removeEventListener('novo-cadastro-colaborador', handleNovoCadastro);
  }, []);

  const handleView = (id: string) => { setSelectedId(id); setViewMode("detail"); };

  const handleEdit = (id: string) => {
    if (!canManage) { toast.error("Você não tem permissão para editar admissões"); return; }
    setSelectedId(id); setViewMode("edit");
  };
  const handleDelete = (id: string) => {
    if (!isAdmin) { toast.error("Você não tem permissão para excluir admissões"); return; }
    setDeleteId(id);
  };
  const confirmDelete = async () => {
    if (deleteId) {
      try {
        await excluirAdmissao(deleteId);
        toast.success("Admissão excluída com sucesso");
        setDeleteId(null);
        if (selectedId === deleteId) { setSelectedId(null); setViewMode("list"); }
      } catch (error: any) { toast.error(error.message || "Erro ao excluir admissão"); }
    }
  };
  const handleNew = () => {
    if (!canManage) { toast.error("Você não tem permissão para criar admissões"); return; }
    setSelectedId(null); setViewMode("new");
  };
  const handleBack = () => { setSelectedId(null); setViewMode("list"); };

  // Auto-save handler for draft mode
  const handleAutoSave = async (dados: {
    dadosPessoais: any; dadosContato: any; dadosProfissionais: any; dadosBancarios: any; exameAdmissional?: any;
  }) => {
    // Build form data, only including non-empty values
    const raw: Record<string, any> = {
      nome_completo: dados.dadosPessoais.nomeCompleto,
      cpf: dados.dadosPessoais.cpf,
      rg: dados.dadosPessoais.rg,
      data_nascimento: dados.dadosPessoais.dataNascimento,
      estado_civil: dados.dadosPessoais.estadoCivil,
      genero: dados.dadosPessoais.genero,
      nacionalidade: dados.dadosPessoais.nacionalidade,
      naturalidade: dados.dadosPessoais.naturalidade,
      nome_mae: dados.dadosPessoais.nomeMae,
      nome_pai: dados.dadosPessoais.nomePai,
      email: dados.dadosContato.email,
      telefone: dados.dadosContato.telefone,
      celular: dados.dadosContato.celular,
      endereco: dados.dadosContato.endereco,
      numero: dados.dadosContato.numero,
      complemento: dados.dadosContato.complemento,
      bairro: dados.dadosContato.bairro,
      cidade: dados.dadosContato.cidade,
      estado: dados.dadosContato.estado,
      cep: dados.dadosContato.cep,
      cargo: dados.dadosProfissionais.cargo,
      departamento: dados.dadosProfissionais.departamento,
      filial: dados.dadosProfissionais.filial,
      data_admissao: dados.dadosProfissionais.dataAdmissao,
      tipo_contrato: dados.dadosProfissionais.tipoContrato,
      jornada_trabalho: dados.dadosProfissionais.jornadaTrabalho,
      salario: dados.dadosProfissionais.salario ? parseFloat(dados.dadosProfissionais.salario.replace(/[^\d,]/g, "").replace(",", ".")) : undefined,
      gestor_imediato: dados.dadosProfissionais.gestorImediato,
      centro_custo: dados.dadosProfissionais.centroCusto,
      cbo: dados.dadosProfissionais.cbo,
      banco: dados.dadosBancarios.banco,
      agencia: dados.dadosBancarios.agencia,
      conta: dados.dadosBancarios.conta,
      tipo_conta: dados.dadosBancarios.tipoConta,
      chave_pix: dados.dadosBancarios.chavePix,
      exame_admissional_data: dados.exameAdmissional?.dataExame,
      exame_admissional_validade: dados.exameAdmissional?.dataValidade,
      exame_admissional_resultado: dados.exameAdmissional?.resultado,
      exame_admissional_clinica: dados.exameAdmissional?.clinica,
      exame_admissional_medico: dados.exameAdmissional?.medico,
      exame_admissional_crm: dados.exameAdmissional?.crm,
      exame_admissional_observacoes: dados.exameAdmissional?.observacoes,
    };

    // Filter out empty/undefined values so we don't overwrite existing data with nulls
    const formData: Partial<AdmissaoFormData> = {};
    for (const [key, value] of Object.entries(raw)) {
      if (value !== undefined && value !== null && value !== '') {
        (formData as any)[key] = value;
      }
    }

    // Need at least one field to save
    if (Object.keys(formData).length === 0) return;

    try {
      if (viewMode === "edit" && selectedId) {
        await atualizarAdmissao({ id: selectedId, dados: formData });
      }
    } catch (err: any) {
      console.error('[AutoSave] Erro ao salvar:', err?.message || err, 'Dados:', JSON.stringify(formData));
      throw err;
    }
  };

  const handleSubmitForm = async (dados: {
    dadosPessoais: any; dadosContato: any; dadosProfissionais: any; dadosBancarios: any; exameAdmissional?: any;
    documentos?: { id: string; nome: string; tipo: string; obrigatorio: boolean; status: string }[];
    documentosComArquivo?: { documentoId: string; file: File; obrigatorio: boolean }[];
  }) => {
    try {
      const formData: AdmissaoFormData = {
        nome_completo: dados.dadosPessoais.nomeCompleto, cpf: dados.dadosPessoais.cpf,
        rg: dados.dadosPessoais.rg, data_nascimento: dados.dadosPessoais.dataNascimento,
        estado_civil: dados.dadosPessoais.estadoCivil, genero: dados.dadosPessoais.genero,
        nacionalidade: dados.dadosPessoais.nacionalidade, naturalidade: dados.dadosPessoais.naturalidade,
        nome_mae: dados.dadosPessoais.nomeMae, nome_pai: dados.dadosPessoais.nomePai,
        email: dados.dadosContato.email, telefone: dados.dadosContato.telefone,
        celular: dados.dadosContato.celular, endereco: dados.dadosContato.endereco,
        numero: dados.dadosContato.numero, complemento: dados.dadosContato.complemento,
        bairro: dados.dadosContato.bairro, cidade: dados.dadosContato.cidade,
        estado: dados.dadosContato.estado, cep: dados.dadosContato.cep,
        cargo: dados.dadosProfissionais.cargo, departamento: dados.dadosProfissionais.departamento,
        filial: dados.dadosProfissionais.filial, data_admissao: dados.dadosProfissionais.dataAdmissao,
        tipo_contrato: dados.dadosProfissionais.tipoContrato, jornada_trabalho: dados.dadosProfissionais.jornadaTrabalho,
        salario: dados.dadosProfissionais.salario ? parseFloat(dados.dadosProfissionais.salario.replace(/[^\d,]/g, "").replace(",", ".")) : undefined,
        gestor_imediato: dados.dadosProfissionais.gestorImediato, centro_custo: dados.dadosProfissionais.centroCusto,
        cbo: dados.dadosProfissionais.cbo || undefined,
        banco: dados.dadosBancarios.banco, agencia: dados.dadosBancarios.agencia,
        conta: dados.dadosBancarios.conta, tipo_conta: dados.dadosBancarios.tipoConta,
        chave_pix: dados.dadosBancarios.chavePix,
        exame_admissional_data: dados.exameAdmissional?.dataExame || undefined,
        exame_admissional_validade: dados.exameAdmissional?.dataValidade || undefined,
        exame_admissional_resultado: dados.exameAdmissional?.resultado || undefined,
        exame_admissional_clinica: dados.exameAdmissional?.clinica || undefined,
        exame_admissional_medico: dados.exameAdmissional?.medico || undefined,
        exame_admissional_crm: dados.exameAdmissional?.crm || undefined,
        exame_admissional_observacoes: dados.exameAdmissional?.observacoes || undefined,
      };
      if (viewMode === "new") {
        const novaAdmissao = await criarAdmissao(formData);
        toast.success("Admissão criada com sucesso!"); setSelectedId(novaAdmissao.id); setViewMode("detail");

        if (dados.documentos?.length) {
          const docsPadraoPorChave = new Map(
            (novaAdmissao.documentos || []).map((doc) => [`${doc.nome}::${doc.tipo}`, doc])
          );

          const docsParaInserir = dados.documentos
            .filter((doc) => !docsPadraoPorChave.has(`${doc.nome}::${doc.tipo}`))
            .map((doc) => ({
              admissao_id: novaAdmissao.id,
              tenant_id: novaAdmissao.tenant_id,
              nome: doc.nome,
              tipo: doc.tipo,
              obrigatorio: doc.obrigatorio,
              status: 'pendente' as const,
            }));

          if (docsParaInserir.length) {
            const { error: insertDocsError } = await supabase
              .from('admissao_documentos')
              .insert(docsParaInserir);

            if (insertDocsError) throw insertDocsError;
          }

          const { data: syncedDocs, error: syncedDocsError } = await supabase
            .from('admissao_documentos')
            .select('id, nome, tipo')
            .eq('admissao_id', novaAdmissao.id)
            .order('created_at', { ascending: true });

          if (syncedDocsError) throw syncedDocsError;

          // Upload documentos que foram anexados no formulário
          if (dados.documentosComArquivo?.length && syncedDocs) {
            const syncedDocsByKey = new Map(
              syncedDocs.map((doc) => [`${doc.nome}::${doc.tipo}`, doc.id])
            );

            for (const docLocal of dados.documentosComArquivo) {
              const docMeta = dados.documentos.find((doc) => doc.id === docLocal.documentoId);
              if (!docMeta) continue;

              const realDocId = syncedDocsByKey.get(`${docMeta.nome}::${docMeta.tipo}`);
              if (!realDocId) continue;

              try {
                await uploadDocumento(novaAdmissao.id, realDocId, docLocal.file);
              } catch (err) {
                console.error('Erro ao enviar documento:', err);
              }
            }
            toast.success("Documentos enviados com sucesso!");
          }
        }
      } else if (viewMode === "edit" && selectedId) {
        await atualizarAdmissao({ id: selectedId, dados: formData });

        let documentosReaisPorLocalId = new Map<string, string>();
        if (dados.documentos?.length) {
          const docsExistentesReais = dados.documentos.filter((doc) => !doc.id.startsWith('new-doc-'));
          docsExistentesReais.forEach((doc) => documentosReaisPorLocalId.set(doc.id, doc.id));

          const docsNovos = dados.documentos.filter((doc) => doc.id.startsWith('new-doc-'));
          if (docsNovos.length) {
            const { data: admissaoAtual, error: admissaoAtualError } = await supabase
              .from('admissoes')
              .select('tenant_id')
              .eq('id', selectedId)
              .single();

            if (admissaoAtualError) throw admissaoAtualError;

            const docsParaInserir = docsNovos.map((doc) => ({
              admissao_id: selectedId,
              tenant_id: admissaoAtual.tenant_id,
              nome: doc.nome,
              tipo: doc.tipo,
              obrigatorio: doc.obrigatorio,
              status: 'pendente' as const,
            }));

            const { data: insertedDocs, error: insertedDocsError } = await supabase
              .from('admissao_documentos')
              .insert(docsParaInserir)
              .select('id, nome, tipo');

            if (insertedDocsError) throw insertedDocsError;

            docsNovos.forEach((doc) => {
              const inserted = insertedDocs?.find((item) => item.nome === doc.nome && item.tipo === doc.tipo);
              if (inserted) documentosReaisPorLocalId.set(doc.id, inserted.id);
            });
          }
        }

        // Upload documentos anexados na edição
        if (dados.documentosComArquivo?.length) {
          for (const docLocal of dados.documentosComArquivo) {
            const realDocId = documentosReaisPorLocalId.get(docLocal.documentoId);
            if (!realDocId) continue;

            try {
              await uploadDocumento(selectedId, realDocId, docLocal.file);
            } catch (err) {
              console.error('Erro ao enviar documento:', err);
            }
          }
          toast.success("Documentos enviados com sucesso!");
        }

        toast.success("Admissão atualizada com sucesso!"); setViewMode("detail");
      }
    } catch (error: any) { toast.error(error.message || "Erro ao salvar admissão"); }
  };

  const handleDocumentUpload = async (documentoId: string, file: File) => {
    if (selectedId) {
      try { await uploadDocumento(selectedId, documentoId, file); toast.success("Documento enviado com sucesso!"); }
      catch (error: any) { toast.error(error.message || "Erro ao enviar documento"); throw error; }
    }
  };
  const handleDocumentRemove = async (documentoId: string) => {
    try {
      await atualizarDocumento({ documentoId, dados: { arquivo_url: null, arquivo_nome: null, arquivo_tamanho: null, status: "pendente", data_envio: null } });
      toast.info("Documento removido");
    } catch (error: any) { toast.error(error.message || "Erro ao remover documento"); throw error; }
  };
  const handleDocumentApprove = async (documentoId: string) => {
    try { await atualizarDocumento({ documentoId, dados: { status: "aprovado" } }); toast.success("Documento aprovado!"); }
    catch (error: any) { toast.error(error.message || "Erro ao aprovar documento"); }
  };
  const handleDocumentReplace = async (documentoId: string) => {
    try { await atualizarDocumento({ documentoId, dados: { status: "enviado", data_aprovacao: null, aprovado_por: null } }); toast.info("Documento reaberto — envie o novo arquivo e aprove novamente."); }
    catch (error: any) { toast.error(error.message || "Erro ao reabrir documento"); }
  };
  const handleDocumentReject = async (documentoId: string, motivo: string) => {
    try { await atualizarDocumento({ documentoId, dados: { status: "rejeitado", observacao: motivo } }); toast.error("Documento rejeitado"); }
    catch (error: any) { toast.error(error.message || "Erro ao rejeitar documento"); }
  };
  const handleAprovarEtapa = async (etapaId: string, observacao?: string) => {
    if (selectedId) {
      try { await atualizarWorkflow({ workflowId: etapaId, admissaoId: selectedId, aprovado: true, observacao }); toast.success("Etapa aprovada com sucesso!"); }
      catch (error: any) { toast.error(error.message || "Erro ao aprovar etapa"); }
    }
  };
  const handleRejeitarEtapa = async (etapaId: string, observacao: string) => {
    if (selectedId) {
      try { await atualizarWorkflow({ workflowId: etapaId, admissaoId: selectedId, aprovado: false, observacao }); toast.error("Etapa rejeitada"); }
      catch (error: any) { toast.error(error.message || "Erro ao rejeitar etapa"); }
    }
  };

  if (authLoading || isLoading) {
    return <div className="flex items-center justify-center min-h-[400px]"><Loader2 className="h-8 w-8 animate-spin text-primary" /></div>;
  }
  if (error) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
        <Alert variant="destructive" className="max-w-md">
          <AlertCircle className="h-4 w-4" />
          <AlertTitle>Erro ao carregar dados</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
        <Button onClick={() => window.location.reload()}>Tentar novamente</Button>
      </div>
    );
  }

  const admissoesFormatted = admissoes.filter(a => a.status !== 'desligado').map(a => ({
    id: a.id,
    dadosPessoais: {
      nomeCompleto: a.nome_completo, cpf: a.cpf, rg: a.rg || "", dataNascimento: a.data_nascimento || "",
      estadoCivil: a.estado_civil || "", genero: a.genero || "", nacionalidade: a.nacionalidade || "",
      naturalidade: a.naturalidade || "", nomeMae: a.nome_mae || "", nomePai: a.nome_pai || "",
    },
    dadosContato: {
      email: a.email, telefone: a.telefone || "", celular: a.celular || "", endereco: a.endereco || "",
      numero: a.numero || "", complemento: a.complemento || "", bairro: a.bairro || "",
      cidade: a.cidade || "", estado: a.estado || "", cep: a.cep || "",
    },
    dadosProfissionais: {
      cargo: a.cargo, departamento: a.departamento || "", filial: a.filial || "",
      dataAdmissao: a.data_admissao || "", tipoContrato: a.tipo_contrato || "",
      jornadaTrabalho: a.jornada_trabalho || "",
      salario: a.salario ? `R$ ${a.salario.toLocaleString("pt-BR", { minimumFractionDigits: 2 })}` : "",
      gestorImediato: a.gestor_imediato || "", centroCusto: a.centro_custo || "",
      cbo: (a as any).cbo || "",
    },
    dadosBancarios: {
      banco: a.banco || "", agencia: a.agencia || "", conta: a.conta || "",
      tipoConta: a.tipo_conta || "", chavePix: a.chave_pix || "",
    },
    exameAdmissional: {
      dataExame: (a as any).exame_admissional_data || "",
      dataValidade: (a as any).exame_admissional_validade || "",
      resultado: (a as any).exame_admissional_resultado || "",
      clinica: (a as any).exame_admissional_clinica || "",
      medico: (a as any).exame_admissional_medico || "",
      crm: (a as any).exame_admissional_crm || "",
      observacoes: (a as any).exame_admissional_observacoes || "",
    },
    documentos: (a.documentos || []).map(d => ({
      id: d.id, nome: d.nome, tipo: d.tipo, obrigatorio: d.obrigatorio, status: d.status,
      arquivo_url: d.arquivo_url || undefined, arquivo_nome: d.arquivo_nome || undefined,
      urlPreview: d.arquivo_url || undefined,
      dataEnvio: d.data_envio ? new Date(d.data_envio) : undefined, observacao: d.observacao || undefined,
    })),
    status: a.status,
    historicoAprovacao: (a.workflow || []).map(w => ({
      id: w.id, etapa: w.etapa, status: w.status, responsavel: w.responsavel_nome || "Pendente",
      dataAcao: w.data_acao ? new Date(w.data_acao) : undefined, observacao: w.observacao || undefined,
    })),
    dataCriacao: new Date(a.created_at), dataAtualizacao: new Date(a.updated_at), criadoPor: a.criado_por || "",
    fotoUrl: a.foto_url || undefined,
    onboarding_status: a.onboarding_status || undefined,
  }));

  const selectedAdmissaoFormatted = selectedId ? admissoesFormatted.find(a => a.id === selectedId) : null;

  return (
    <div className="space-y-6">
      {viewMode === "list" && (
        <>
          <AdmissaoStats admissoes={admissoesFormatted as any} />
          <AdmissaoList admissoes={admissoesFormatted as any} onView={handleView} onEdit={handleEdit} onDelete={handleDelete} onNew={handleNew} canApprove={isAdmin} onApprove={async (id) => { try { await atualizarStatus({ id, status: 'aprovado' }); toast.success('Admissão aprovada com sucesso!'); } catch (e: any) { toast.error(e.message || 'Erro ao aprovar admissão'); } }} />
        </>
      )}

      {(viewMode === "new" || viewMode === "edit") && (
        <div>
          <div className="flex items-center gap-3 mb-6">
            <div className="p-2 rounded-lg bg-primary/10"><UserPlus className="h-6 w-6 text-primary" /></div>
            <div>
              <h1 className="text-2xl font-bold text-foreground">{viewMode === "new" ? "Nova Admissão" : "Editar Admissão"}</h1>
              <p className="text-muted-foreground">{viewMode === "new" ? "Preencha os dados do novo colaborador" : "Atualize os dados do colaborador"}</p>
            </div>
          </div>
          <AdmissaoForm
            onSubmit={handleSubmitForm}
            onCancel={handleBack}
            onAutoSave={viewMode === "edit" && selectedId ? handleAutoSave : undefined}
            onDocumentUploadImmediate={viewMode === "edit" ? handleDocumentUpload : undefined}
            onDocumentRemoveImmediate={viewMode === "edit" ? handleDocumentRemove : undefined}
            initialData={selectedAdmissaoFormatted ? {
              dadosPessoais: selectedAdmissaoFormatted.dadosPessoais,
              dadosContato: selectedAdmissaoFormatted.dadosContato,
              dadosProfissionais: selectedAdmissaoFormatted.dadosProfissionais,
              dadosBancarios: selectedAdmissaoFormatted.dadosBancarios,
              exameAdmissional: (selectedAdmissaoFormatted as any).exameAdmissional,
              documentos: (selectedAdmissaoFormatted as any).documentos,
            } : undefined}
          />
        </div>
      )}

      {viewMode === "detail" && selectedAdmissaoFormatted && (
        <AdmissaoDetail
          admissao={selectedAdmissaoFormatted as any}
          onBack={handleBack} onEdit={() => setViewMode("edit")}
          onDelete={() => handleDelete(selectedAdmissaoFormatted.id)}
          onDocumentUpload={handleDocumentUpload} onDocumentRemove={handleDocumentRemove}
          onDocumentApprove={handleDocumentApprove} onDocumentReject={handleDocumentReject} onDocumentReplace={handleDocumentReplace}
          onAprovarEtapa={handleAprovarEtapa} onRejeitarEtapa={handleRejeitarEtapa}
          isAdmin={isAdmin}
        />
      )}

      <AlertDialog open={!!deleteId} onOpenChange={() => setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirmar exclusão</AlertDialogTitle>
            <AlertDialogDescription>Tem certeza que deseja excluir esta admissão? Esta ação não pode ser desfeita.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isPending}>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDelete} className="bg-destructive text-destructive-foreground hover:bg-destructive/90" disabled={isPending}>
              {isPending ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
              Excluir
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

// ========== Desligados Tab Component ==========
function DesligadosTab() {
  const { tenantId } = useAuth();
  const navigate = useNavigate();

  const { empresaAtivaId } = useEmpresaAtiva();
  const { data: desligados = [], isLoading } = useQuery({
    queryKey: ["colaboradores-desligados", tenantId, empresaAtivaId],
    queryFn: async (): Promise<ColaboradorExtendido[]> => {
      if (!tenantId) return [];
      let query = supabase
        .from("admissoes")
        .select("id, nome_completo, cpf, cargo, departamento, email, celular, filial, data_admissao, status, tipo_contrato, onboarding_token, onboarding_status, foto_url")
        .eq("tenant_id", tenantId)
        .eq("status", "desligado");

      if (empresaAtivaId) {
        query = query.eq("empresa_id", empresaAtivaId);
      }

      const { data, error } = await query.order("updated_at", { ascending: false });
      if (error) throw error;
      return data || [];
    },
    enabled: !!tenantId,
  });

  if (isLoading) {
    return <div className="flex items-center justify-center py-12"><Loader2 className="w-8 h-8 animate-spin text-primary" /></div>;
  }

  if (desligados.length === 0) {
    return (
      <div className="text-center py-12 bg-card rounded-xl border border-border">
        <p className="text-muted-foreground">Nenhum colaborador desligado.</p>
      </div>
    );
  }

  return (
    <div className="bg-card rounded-xl border border-border shadow-sm overflow-hidden">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-[300px]">Colaborador</TableHead>
            <TableHead>Cargo</TableHead>
            <TableHead className="hidden md:table-cell">Departamento</TableHead>
            <TableHead className="hidden lg:table-cell">Contato</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="w-[50px]"></TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {desligados.map((colab) => (
            <TableRow key={colab.id}>
              <TableCell>
                <div className="flex items-center gap-3">
                  <Avatar className="h-9 w-9">
                    <AvatarFallback className="bg-muted text-muted-foreground text-sm font-semibold">
                      {colab.nome_completo.split(" ").map(n => n[0]).join("").slice(0, 2)}
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <p className="font-medium text-foreground">{colab.nome_completo}</p>
                    <p className={cn("text-xs truncate max-w-[200px]", colab.email ? "text-muted-foreground" : "text-muted-foreground/60 italic")}>{colab.email || "E-mail não cadastrado"}</p>
                  </div>
                </div>
              </TableCell>
              <TableCell className="text-sm">{colab.cargo}</TableCell>
              <TableCell className="hidden md:table-cell text-sm text-muted-foreground">{colab.departamento || "-"}</TableCell>
              <TableCell className="hidden lg:table-cell text-sm text-muted-foreground">{formatPhone(colab.celular)}</TableCell>
              <TableCell>
                <Badge className={cn("text-xs", statusStyles.desligado)}>Desligado</Badge>
              </TableCell>
              <TableCell>
                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => navigate(`/documentos?colaborador=${colab.id}`)}>
                  <FolderOpen className="w-4 h-4" />
                </Button>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

// ========== Main Page ==========
const Colaboradores = () => {
  const [showImport, setShowImport] = useState(false);
  const queryClient = useQueryClient();
  const { temPermissao, isOwner } = usePerfilPermissions();
  const podeCriar = isOwner || temPermissao("colaboradores", "criar");

  const [activeTab, setActiveTab] = useState("ativos");

  useEffect(() => {
    const handleOpenImport = () => setShowImport(true);
    window.addEventListener('open-import-colaboradores', handleOpenImport);
    return () => window.removeEventListener('open-import-colaboradores', handleOpenImport);
  }, []);

  const handleImportSuccess = (resultado?: ResultadoImportacao) => {
    queryClient.invalidateQueries({ queryKey: ["colaboradores-list"] });
    queryClient.invalidateQueries({ queryKey: ["colaboradores"] });
    queryClient.invalidateQueries({ queryKey: ["cargos"] });
    queryClient.invalidateQueries({ queryKey: ["departamentos"] });
    queryClient.invalidateQueries({ queryKey: ["admissoes"] });
    if (resultado && resultado.colaboradoresInseridos + resultado.colaboradoresAtualizados > 0) {
      setActiveTab("ativos");
    }
  };

  const handleViewImportedEmpresa = () => {
    setActiveTab("ativos");
    setShowImport(false);
    queryClient.invalidateQueries({ queryKey: ["colaboradores-list"] });
    queryClient.invalidateQueries({ queryKey: ["admissoes"] });
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4 }}
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10">
              <Users className="h-6 w-6 text-primary" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-foreground">Colaboradores</h1>
              <p className="text-muted-foreground">Gerencie sua equipe — admissão, ativos e desligados</p>
            </div>
          </div>
        </motion.div>

        <div className="flex flex-wrap items-center gap-2">
          {podeCriar && (
            <>
              <Button 
                variant="outline" 
                onClick={() => setShowImport(true)}
                id="btn-importar-colaboradores"
              >
                <Upload className="w-4 h-4 mr-2" />
                Importar Colaboradores
              </Button>
              <Button 
                className="gradient-primary shadow-glow" 
                onClick={() => {
                  if (activeTab !== "ativos") {
                    setActiveTab("ativos");
                    setTimeout(() => {
                      window.dispatchEvent(new CustomEvent('novo-cadastro-colaborador'));
                    }, 60);
                  } else {
                    window.dispatchEvent(new CustomEvent('novo-cadastro-colaborador'));
                  }
                }}
              >
                <Plus className="w-4 h-4 mr-2" />
                Novo Cadastro
              </Button>
            </>
          )}
        </div>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full grid-cols-3 max-w-md">
          <TabsTrigger value="ativos">Ativos</TabsTrigger>
          <TabsTrigger value="admissoes">Admissões</TabsTrigger>
          <TabsTrigger value="desligados">Desligados</TabsTrigger>
        </TabsList>
        <TabsContent value="ativos" className="mt-6">
          <AtivosTab showImport={showImport} setShowImport={setShowImport} />
        </TabsContent>
        <TabsContent value="admissoes" className="mt-6">
          <AdmissoesTab />
        </TabsContent>
        <TabsContent value="desligados" className="mt-6">
          <DesligadosTab />
        </TabsContent>
      </Tabs>

      {/* Import Modal at parent level — works regardless of active tab */}
      <ImportPlanilhaModal
        open={showImport}
        onOpenChange={setShowImport}
        onSuccess={handleImportSuccess}
        onViewEmpresa={handleViewImportedEmpresa}
        titulo="Importar Colaboradores"
        descricao="Importe uma planilha para criar colaboradores, funções e departamentos automaticamente"
      />
    </div>
  );
};

export default Colaboradores;
