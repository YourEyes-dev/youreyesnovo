import { useMemo, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Layers, Plus, Pencil, Trash2, Copy, ListChecks, Building2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from "@/components/ui/card";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import { confirm } from "@/components/ui/confirm-dialog";
import { useAuth } from "@/hooks/useAuth";
import { useEmpresaCadastro } from "@/hooks/useEmpresaCadastro";
import { useFeriadoTabelas } from "@/hooks/useFeriadoTabelas";
import { payloadItem, payloadTabela, type FeriadoTabela } from "@/lib/ponto/feriadoTabelas";
import { FeriadoTabelaFormDialog } from "./FeriadoTabelaFormDialog";
import { FeriadoTabelaItensDialog } from "./FeriadoTabelaItensDialog";

/** RN20-22 — tabelas numeradas de feriados reaproveitáveis por várias filiais. */
export function FeriadoTabelasPanel() {
  const { tenantId } = useAuth();
  const { empresas } = useEmpresaCadastro();
  const qc = useQueryClient();
  const {
    tabelas, isLoading, itensPorTabela, empresasPorTabela,
    salvarTabela, excluirTabela, duplicarTabela, salvarItem, excluirItem, definirVinculos,
  } = useFeriadoTabelas();

  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<FeriadoTabela | null>(null);
  const [itensDe, setItensDe] = useState<FeriadoTabela | null>(null);

  const unidades = useMemo(
    () => (empresas || []).map((e) => ({
      id: e.id as string,
      nome: (e.nome_fantasia || e.razao_social || "Unidade") as string,
      cidade: (e as { cidade?: string | null }).cidade ?? null,
      uf: (e as { estado?: string | null }).estado ?? null,
    })),
    [empresas],
  );
  const nomeUnidade = (id: string) => unidades.find((u) => u.id === id)?.nome || "Unidade";

  const reconsolidar = () => qc.invalidateQueries({ queryKey: ["ponto-diario"] });

  return (
    <Card>
      <CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <CardTitle className="flex items-center gap-2 text-lg">
            <Layers className="h-5 w-5 text-primary" />
            Calendário da unidade (tabelas de feriados)
          </CardTitle>
          <CardDescription>
            É aqui que mora o feriado específico de uma unidade. Monte tabelas numeradas
            (Tabela 1, Tabela 2…) por município e reaproveite a mesma tabela em várias
            unidades. Prevalecem sobre os feriados por localização (estaduais e nacionais).
          </CardDescription>
        </div>
        <Button size="sm" onClick={() => { setEditing(null); setShowForm(true); }}>
          <Plus className="h-4 w-4 mr-1" /> Nova tabela
        </Button>
      </CardHeader>

      <CardContent>
        <div className="rounded-md border overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-[80px]">Nº</TableHead>
                <TableHead>Nome</TableHead>
                <TableHead className="w-[160px]">Município/UF</TableHead>
                <TableHead className="w-[110px]">Vigência</TableHead>
                <TableHead className="w-[90px]">Feriados</TableHead>
                <TableHead>Filiais vinculadas</TableHead>
                <TableHead className="w-[170px] text-right">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow>
                  <TableCell colSpan={7} className="text-center py-6 text-sm text-muted-foreground">
                    Carregando…
                  </TableCell>
                </TableRow>
              ) : tabelas.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={7} className="text-center py-6 text-sm text-muted-foreground">
                    Nenhuma tabela criada. Crie a Tabela 1 do município e vincule as filiais.
                  </TableCell>
                </TableRow>
              ) : tabelas.map((t) => {
                const vinculadas = empresasPorTabela.get(t.id) || [];
                const itens = itensPorTabela.get(t.id) || [];
                return (
                  <TableRow key={t.id} className={t.ativo ? "" : "opacity-60"}>
                    <TableCell className="font-semibold">#{t.numero ?? "—"}</TableCell>
                    <TableCell>
                      {t.nome}
                      {!t.ativo && <Badge variant="outline" className="ml-2 text-[10px]">inativa</Badge>}
                    </TableCell>
                    <TableCell className="text-sm">
                      {t.municipio ? `${t.municipio}${t.uf ? `/${t.uf}` : ""}` : t.uf || "—"}
                    </TableCell>
                    <TableCell className="text-sm">{t.ano ?? "Permanente"}</TableCell>
                    <TableCell>
                      <Badge variant="secondary">{itens.length}</Badge>
                    </TableCell>
                    <TableCell>
                      {vinculadas.length === 0 ? (
                        <span className="text-xs text-muted-foreground">Nenhuma</span>
                      ) : (
                        <div className="flex flex-wrap gap-1">
                          {vinculadas.map((id) => (
                            <Badge key={id} variant="outline" className="text-[10px] gap-1">
                              <Building2 className="h-3 w-3" />{nomeUnidade(id)}
                            </Badge>
                          ))}
                        </div>
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center justify-end gap-1">
                        <Button
                          size="icon" variant="ghost" aria-label="Gerenciar feriados"
                          onClick={() => setItensDe(t)}
                        >
                          <ListChecks className="h-4 w-4" />
                        </Button>
                        <Button
                          size="icon" variant="ghost" aria-label="Duplicar para o próximo ano"
                          onClick={async () => {
                            const proximo = (t.ano ?? new Date().getFullYear()) + 1;
                            const ok = await confirm({
                              title: `Duplicar para ${proximo}?`,
                              description: "Cria uma nova tabela com os mesmos feriados, vigente no ano seguinte.",
                              confirmLabel: "Duplicar",
                            });
                            if (ok) duplicarTabela.mutate({ id: t.id, ano: proximo });
                          }}
                        >
                          <Copy className="h-4 w-4" />
                        </Button>
                        <Button
                          size="icon" variant="ghost" aria-label="Editar"
                          onClick={() => { setEditing(t); setShowForm(true); }}
                        >
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button
                          size="icon" variant="ghost" aria-label="Excluir"
                          onClick={async () => {
                            const ok = await confirm({
                              title: "Excluir tabela de feriados?",
                              description: `"${t.nome}" e seus feriados serão removidos das filiais vinculadas.`,
                              confirmLabel: "Excluir",
                              variant: "destructive",
                            });
                            if (ok) { excluirTabela.mutate(t.id); reconsolidar(); }
                          }}
                        >
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      </CardContent>

      <FeriadoTabelaFormDialog
        open={showForm}
        onOpenChange={(v) => { setShowForm(v); if (!v) setEditing(null); }}
        editing={editing}
        unidades={unidades}
        vinculadas={editing ? (empresasPorTabela.get(editing.id) || []) : []}
        salvando={salvarTabela.isPending || definirVinculos.isPending}
        onSubmit={async (form, empresaIds) => {
          if (!tenantId) return;
          const id = await salvarTabela.mutateAsync({
            id: editing?.id, payload: payloadTabela(form, tenantId),
          });
          await definirVinculos.mutateAsync({ tabelaId: id, empresaIds });
          setShowForm(false);
          setEditing(null);
          reconsolidar();
        }}
      />

      <FeriadoTabelaItensDialog
        open={!!itensDe}
        onOpenChange={(v) => { if (!v) setItensDe(null); }}
        tabela={itensDe}
        itens={itensDe ? (itensPorTabela.get(itensDe.id) || []) : []}
        salvando={salvarItem.isPending}
        onAdicionar={(form) => {
          if (!itensDe || !tenantId) return;
          salvarItem.mutate({ payload: payloadItem(form, itensDe.id, tenantId) });
          reconsolidar();
        }}
        onExcluir={(id) => { excluirItem.mutate(id); reconsolidar(); }}
      />
    </Card>
  );
}
