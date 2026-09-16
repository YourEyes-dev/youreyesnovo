import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { motion } from "framer-motion";
import {
  Warehouse,
  Search,
  MapPin,
  Package,
  AlertTriangle,
  ArrowUpDown,
} from "lucide-react";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Progress } from "@/components/ui/progress";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useEpiLocais, LOCAL_TIPO_LABELS, type LocalEstoqueTipo } from "@/hooks/useEpiLocais";

interface EstoqueLocalRow {
  id: string;
  epi_id: string;
  local_estoque_id: string;
  quantidade: number;
  quantidade_minima: number;
  tamanho: string;
  epi: {
    id: string;
    ca: string | null;
    quantidade_estoque: number;
    tipo: {
      nome: string;
      categoria: string | null;
      unidade_medida: string | null;
      controla_tamanho: boolean | null;
      // O CA vive em epi_tipos.ca_numero; epis.ca ficou vazio porque nenhuma
      // tela o escrevia. Sem declarar aqui, o campo chega undefined mesmo
      // vindo no select.
      ca_numero: string | null;
    } | null;
  } | null;
}

export function SaldoLocalDashboard() {
  const { tenantId } = useAuth();
  const { locais } = useEpiLocais();
  const [search, setSearch] = useState("");
  const [filtroLocal, setFiltroLocal] = useState("todos");

  const { data: estoqueLocal = [], isLoading } = useQuery({
    queryKey: ["epi-estoque-local", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data, error } = await supabase
        .from("epi_estoque_local")
        .select("*, epi:epis(id, ca, quantidade_estoque, tipo:epi_tipos(nome, categoria, unidade_medida, controla_tamanho, ca_numero))")
        .eq("tenant_id", tenantId)
        .order("quantidade", { ascending: false });
      if (error) throw error;
      return data as unknown as EstoqueLocalRow[];
    },
    enabled: !!tenantId,
  });

  // Enrich with local info
  const getLocal = (id: string) => locais.find((l) => l.id === id);

  // Filter
  const filtered = estoqueLocal.filter((row) => {
    if (filtroLocal !== "todos" && row.local_estoque_id !== filtroLocal) return false;
    if (search) {
      const s = search.toLowerCase();
      const localNome = getLocal(row.local_estoque_id)?.nome?.toLowerCase() || "";
      const epiNome = row.epi?.tipo?.nome?.toLowerCase() || "";
      return localNome.includes(s) || epiNome.includes(s);
    }
    return true;
  });

  // Stats
  const totalItens = estoqueLocal.reduce((sum, r) => sum + r.quantidade, 0);
  const locaisComEstoque = new Set(estoqueLocal.filter((r) => r.quantidade > 0).map((r) => r.local_estoque_id)).size;
  const alertasBaixo = estoqueLocal.filter((r) => r.quantidade_minima > 0 && r.quantidade <= r.quantidade_minima).length;
  const zerados = estoqueLocal.filter((r) => r.quantidade === 0).length;

  // Group by local for summary cards
  const saldoPorLocal = locais
    .filter((l) => l.ativo)
    .map((local) => {
      const itens = estoqueLocal.filter((r) => r.local_estoque_id === local.id);
      const totalQtd = itens.reduce((sum, r) => sum + r.quantidade, 0);
      const totalEpis = itens.filter((r) => r.quantidade > 0).length;
      const alertas = itens.filter((r) => r.quantidade_minima > 0 && r.quantidade <= r.quantidade_minima).length;
      return { ...local, totalQtd, totalEpis, alertas };
    })
    .sort((a, b) => b.totalQtd - a.totalQtd);

  return (
    <div className="space-y-6">
      {/* Stats */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="grid grid-cols-2 md:grid-cols-4 gap-4"
      >
        <div className="p-4 rounded-xl border bg-card">
          <div className="flex items-center gap-2 text-muted-foreground text-sm mb-1">
            <Package className="w-4 h-4" />
            Total de Itens
          </div>
          <p className="text-2xl font-bold">{totalItens}</p>
        </div>
        <div className="p-4 rounded-xl border bg-card">
          <div className="flex items-center gap-2 text-muted-foreground text-sm mb-1">
            <MapPin className="w-4 h-4" />
            Locais com Estoque
          </div>
          <p className="text-2xl font-bold">{locaisComEstoque}</p>
        </div>
        <div className="p-4 rounded-xl border bg-card">
          <div className="flex items-center gap-2 text-muted-foreground text-sm mb-1">
            <AlertTriangle className="w-4 h-4 text-amber-500" />
            Abaixo do Mínimo
          </div>
          <p className="text-2xl font-bold text-amber-600">{alertasBaixo}</p>
        </div>
        <div className="p-4 rounded-xl border bg-card">
          <div className="flex items-center gap-2 text-muted-foreground text-sm mb-1">
            <ArrowUpDown className="w-4 h-4 text-destructive" />
            Zerados
          </div>
          <p className="text-2xl font-bold text-destructive">{zerados}</p>
        </div>
      </motion.div>

      {/* Summary per location */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.1 }}
        className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
      >
        {saldoPorLocal.map((local) => (
          <Card
            key={local.id}
            className="cursor-pointer hover:border-primary/50 transition-colors"
            onClick={() => setFiltroLocal(filtroLocal === local.id ? "todos" : local.id)}
          >
            <CardContent className="pt-5 pb-4">
              <div className="flex items-start justify-between mb-3">
                <div>
                  <h3 className="font-semibold flex items-center gap-2">
                    <Warehouse className="w-4 h-4 text-primary" />
                    {local.nome}
                  </h3>
                  {local.tipo && (
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {LOCAL_TIPO_LABELS[local.tipo as LocalEstoqueTipo] || local.tipo}
                    </p>
                  )}
                </div>
                {local.alertas > 0 && (
                  <Badge variant="destructive" className="text-xs">
                    {local.alertas} alerta{local.alertas > 1 ? "s" : ""}
                  </Badge>
                )}
                {filtroLocal === local.id && (
                  <Badge className="text-xs">Filtrado</Badge>
                )}
              </div>
              <div className="flex items-end justify-between">
                <div>
                  <p className="text-3xl font-bold">{local.totalQtd}</p>
                  <p className="text-xs text-muted-foreground">{local.totalEpis} tipo{local.totalEpis !== 1 ? "s" : ""} de EPI</p>
                </div>
                {local.filial?.nome && (
                  <Badge variant="outline" className="text-xs">
                    {local.filial.nome}
                  </Badge>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
        {saldoPorLocal.length === 0 && (
          <div className="col-span-full text-center py-8 text-muted-foreground">
            <Warehouse className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p>Nenhum local de estoque cadastrado.</p>
            <p className="text-sm">Vá em Config para criar locais de estoque.</p>
          </div>
        )}
      </motion.div>

      {/* Detail table */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.2 }}
      >
        <Card>
          <CardHeader>
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Package className="w-5 h-5 text-primary" />
                  Saldo Detalhado por Local
                </CardTitle>
                <CardDescription>
                  Visualize o saldo de cada EPI em cada local de estoque
                </CardDescription>
              </div>
              <div className="flex flex-col sm:flex-row gap-3">
                <div className="relative w-full sm:w-[280px]">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                  <Input
                    placeholder="Pesquisar EPI ou local..."
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    className="pl-10 h-10 border-muted-foreground/20"
                  />
                </div>
                <Select value={filtroLocal} onValueChange={setFiltroLocal}>
                  <SelectTrigger className="w-full sm:w-[200px] h-10 border-muted-foreground/20">
                    <div className="flex items-center gap-2">
                      <Warehouse className="w-4 h-4 text-muted-foreground" />
                      <SelectValue placeholder="Filtrar local" />
                    </div>
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="todos">Todos os locais</SelectItem>
                    {locais.filter((l) => l.ativo).map((l) => (
                      <SelectItem key={l.id} value={l.id}>{l.nome}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className="flex items-center justify-center py-12">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
              </div>
            ) : filtered.length === 0 ? (
              <div className="text-center py-12 text-muted-foreground">
                <Package className="w-12 h-12 mx-auto mb-4 opacity-50" />
                <p>Nenhum saldo encontrado</p>
              </div>
            ) : (
              <div className="border rounded-lg overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>EPI</TableHead>
                      <TableHead>Tamanho</TableHead>
                      <TableHead>CA</TableHead>
                      <TableHead>Local</TableHead>
                      <TableHead>Quantidade</TableHead>
                      <TableHead>Mínimo</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filtered.map((row) => {
                      const local = getLocal(row.local_estoque_id);
                      const abaixoMin = row.quantidade_minima > 0 && row.quantidade <= row.quantidade_minima;
                      const zerado = row.quantidade === 0;
                      const pct = row.quantidade_minima > 0
                        ? Math.min(100, Math.round((row.quantidade / (row.quantidade_minima * 3)) * 100))
                        : 100;

                      return (
                        <TableRow key={row.id}>
                          <TableCell>
                            <div>
                              <span className="font-medium">{row.epi?.tipo?.nome || "—"}</span>
                              {row.epi?.tipo?.categoria && (
                                <p className="text-xs text-muted-foreground">{row.epi.tipo.categoria}</p>
                              )}
                            </div>
                          </TableCell>
                          <TableCell className="text-sm">
                            {row.tamanho || "—"}
                          </TableCell>
                          <TableCell className="text-sm">
                            {row.epi?.ca || row.epi?.tipo?.ca_numero || "—"}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-1 text-sm">
                              <MapPin className="w-3.5 h-3.5 text-muted-foreground" />
                              {local?.nome || "—"}
                            </div>
                          </TableCell>
                          <TableCell>
                            <span className={`font-bold ${zerado ? "text-destructive" : abaixoMin ? "text-amber-600" : ""}`}>
                              {row.quantidade}
                            </span>
                            {row.epi?.tipo?.unidade_medida && (
                              <span className="text-xs text-muted-foreground ml-1">
                                {row.epi.tipo.unidade_medida}
                              </span>
                            )}
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">
                            {row.quantidade_minima > 0 ? row.quantidade_minima : "—"}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2 min-w-[120px]">
                              {zerado ? (
                                <Badge variant="destructive" className="text-xs">Zerado</Badge>
                              ) : abaixoMin ? (
                                <Badge variant="outline" className="text-xs border-amber-500 text-amber-600">
                                  <AlertTriangle className="w-3 h-3 mr-1" />
                                  Baixo
                                </Badge>
                              ) : (
                                <Progress value={pct} className="h-2 w-20" />
                              )}
                            </div>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
          </CardContent>
        </Card>
      </motion.div>
    </div>
  );
}
