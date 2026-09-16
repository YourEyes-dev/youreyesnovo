import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";
import { fromTable } from "@/integrations/supabase/untypedClient";
import { useAuth } from "@/hooks/useAuth";
import { useTenant } from "@/hooks/useTenant";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Upload, FileText, CheckCircle, AlertTriangle, Clock, HardDrive, ShieldAlert } from "lucide-react";
import { lerArquivoAfd, hashDoArquivo } from "@/lib/ponto/afdImportacao";
import { toast } from "sonner";
import { format } from "date-fns";

export function PontoRepCTab() {
  const { profile } = useAuth();
  const { tenantId } = useTenant();
  const queryClient = useQueryClient();
  const [importando, setImportando] = useState(false);
  const [fabricante, setFabricante] = useState("");
  const [modelo, setModelo] = useState("");
  const [numeroSerie, setNumeroSerie] = useState("");
  // Veredito da última importação, para explicar a quarentena na hora.
  const [ultimoVerdito, setUltimoVerdito] = useState<any>(null);

  const { data: importacoes = [], isLoading } = useQuery({
    queryKey: ["ponto-repc-importacoes", tenantId],
    queryFn: async () => {
      if (!tenantId) return [];
      const { data } = await fromTable("ponto_repc_importacoes")
        .select("*")
        .eq("tenant_id", tenantId)
        .order("created_at", { ascending: false })
        .limit(50) as { data: any[] | null };
      return data || [];
    },
    enabled: !!tenantId,
  });

  const handleImportar = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !tenantId) return;

    setImportando(true);
    setUltimoVerdito(null);
    try {
      const conteudo = await file.text();
      const equipamento = [fabricante, modelo, numeroSerie].filter(Boolean).join(" ") || file.name;

      // 1) Leitura do arquivo: registros tipados, com a linha crua de cada um.
      //    Quem confere é o banco — aqui só se prepara o material.
      const leitura = lerArquivoAfd(conteudo, equipamento);
      const arquivoHash = await hashDoArquivo(conteudo);

      // 2) Abre a importação já com a identidade do arquivo (trava de
      //    reimportação: a mesma remessa não entra duas vezes).
      const { data: importacao, error: errImport } = await fromTable("ponto_repc_importacoes")
        .insert({
          tenant_id: tenantId,
          arquivo_nome: file.name,
          arquivo_hash: arquivoHash,
          tipo_equipamento: "REP-C",
          fabricante: fabricante || null,
          modelo: modelo || null,
          numero_serie: numeroSerie || null,
          total_registros: leitura.totalLinhas,
          registros_importados: 0,
          registros_rejeitados: 0,
          status: "processando",
          erros: leitura.avisos.length > 0 ? leitura.avisos : null,
          importado_por: profile?.nome_completo,
          importado_por_id: profile?.id,
        } as any)
        .select()
        .single() as { data: any; error: any };

      if (errImport) {
        // Violação da unicidade do hash: arquivo já importado antes.
        if (String(errImport.message || "").includes("ponto_repc_importacoes_arquivo_uk")) {
          setUltimoVerdito({ quarentena: true, duplicado: true, erros: [] });
          toast.error("Este mesmo arquivo já foi importado antes. Nada foi gravado.");
          return;
        }
        throw errImport;
      }

      // 3) CONFERÊNCIA NO BANCO (Portaria 671): CRC-16 por registro, assinatura
      //    das marcações, lacuna na sequência de NSR e reimportação. Arquivo
      //    reprovado vai para quarentena e NADA dele entra.
      const { data: verdito, error: errVal } = await (supabase.rpc as any)(
        "ponto_afd_validar_importacao",
        {
          p_tenant_id: tenantId,
          p_empresa_id: null,
          p_importacao_id: importacao.id,
          p_arquivo_hash: arquivoHash,
          p_registros: leitura.registros,
          p_assinatura_valida: true,
        },
      );
      if (errVal) throw errVal;
      setUltimoVerdito(verdito);

      if (verdito?.quarentena) {
        queryClient.invalidateQueries({ queryKey: ["ponto-repc-importacoes"] });
        toast.error(
          "Arquivo reprovado na conferência e posto em quarentena — nenhuma marcação foi gravada.",
        );
        return;
      }

      // 4) Arquivo aprovado: grava as marcações com a chave de origem
      //    (equipamento + NSR do AFD), que impede entrada em dobro.
      let importados = 0;
      let rejeitados = 0;
      for (const m of leitura.marcacoes) {
        const { data: existentes } = await fromTable("ponto_marcacoes")
          .select("tipo_marcacao")
          .eq("tenant_id", tenantId)
          .eq("colaborador_cpf", m.colaborador_cpf)
          .eq("data_marcacao", m.data_marcacao) as { data: any[] | null };

        const totalDia = (existentes || []).length;
        const tipoMarcacao = totalDia % 2 === 0 ? "entrada" : "saida";

        const { error: errMarcacao } = await fromTable("ponto_marcacoes")
          .insert({
            tenant_id: tenantId,
            colaborador_cpf: m.colaborador_cpf,
            colaborador_id: m.colaborador_cpf,
            colaborador_nome: `CPF ${m.colaborador_cpf}`,
            data_marcacao: m.data_marcacao,
            hora_marcacao: m.hora_marcacao,
            tipo_marcacao: tipoMarcacao,
            origem: "repc",
            ip_address: "REP-C Import",
            nsr_origem: Number(m.nsr_origem) || null,
            equipamento,
          } as any);

        if (errMarcacao) rejeitados++; else importados++;
      }

      await fromTable("ponto_repc_importacoes")
        .update({
          status: "concluido",
          registros_importados: importados,
          registros_rejeitados: rejeitados,
        } as any)
        .eq("id", importacao.id);

      queryClient.invalidateQueries({ queryKey: ["ponto-repc-importacoes"] });
      queryClient.invalidateQueries({ queryKey: ["ponto-diario"] });
      toast.success(
        `Arquivo aprovado na conferência: ${importados} marcações gravadas`
        + (rejeitados > 0 ? `, ${rejeitados} já existentes ou recusadas` : "")
        + ` (leiaute ${leitura.leiaute}).`,
      );
    } catch (err: any) {
      toast.error("Erro na importação: " + (err.message || "erro desconhecido"));
    } finally {
      setImportando(false);
      e.target.value = "";
    }
  };

  const statusBadge = (status: string) => {
    const map: Record<string, { label: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
      pendente: { label: "Pendente", variant: "outline" },
      processando: { label: "Processando", variant: "secondary" },
      concluido: { label: "Concluído", variant: "default" },
      erro: { label: "Erro", variant: "destructive" },
    };
    const cfg = map[status] || map.pendente;
    return <Badge variant={cfg.variant}>{cfg.label}</Badge>;
  };

  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-lg font-semibold flex items-center gap-2">
          <HardDrive className="w-5 h-5 text-primary" /> Importação REP-C (Relógios Físicos)
        </h3>
        <p className="text-sm text-muted-foreground">Importe arquivos AFD de registradores eletrônicos de ponto convencionais</p>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-base">Dados do Equipamento (opcional)</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="space-y-2">
              <Label>Fabricante</Label>
              <Input value={fabricante} onChange={e => setFabricante(e.target.value)} placeholder="Ex: Henry, Dimep..." />
            </div>
            <div className="space-y-2">
              <Label>Modelo</Label>
              <Input value={modelo} onChange={e => setModelo(e.target.value)} placeholder="Ex: Orion 6" />
            </div>
            <div className="space-y-2">
              <Label>Nº de Série</Label>
              <Input value={numeroSerie} onChange={e => setNumeroSerie(e.target.value)} placeholder="Número de série" />
            </div>
          </div>

          <div className="border-2 border-dashed rounded-lg p-8 text-center">
            <Upload className="w-10 h-10 text-muted-foreground mx-auto mb-3" />
            <p className="font-medium mb-1">Selecione o arquivo AFD (.txt)</p>
            <p className="text-sm text-muted-foreground mb-4">Formato padrão Portaria 671 exportado do REP-C</p>
            <label className="cursor-pointer">
              <Input
                type="file"
                accept=".txt,.afd"
                className="hidden"
                onChange={handleImportar}
                disabled={importando}
              />
              <Button asChild disabled={importando}>
                <span>{importando ? "Importando..." : "Selecionar Arquivo"}</span>
              </Button>
            </label>
          </div>
        </CardContent>
      </Card>

      {/* Veredito da conferência (Portaria 671) */}
      {ultimoVerdito && (
        <Card className={ultimoVerdito.quarentena ? "border-destructive" : "border-emerald-400"}>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              {ultimoVerdito.quarentena ? (
                <><ShieldAlert className="w-5 h-5 text-destructive" /> Arquivo em quarentena — nada foi gravado</>
              ) : (
                <><CheckCircle className="w-5 h-5 text-emerald-600" /> Arquivo aprovado na conferência</>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 text-sm">
            <div className="flex flex-wrap gap-2">
              <Badge variant={ultimoVerdito.crc_valido === false ? "destructive" : "outline"}>
                CRC por registro: {ultimoVerdito.crc_valido === false ? "falhou" : "ok"}
              </Badge>
              <Badge variant={ultimoVerdito.cadeia_valida === false ? "destructive" : "outline"}>
                Assinatura: {ultimoVerdito.cadeia_valida === false ? "não confere" : "ok"}
              </Badge>
              <Badge variant={ultimoVerdito.lacuna_nsr ? "destructive" : "outline"}>
                Sequência de NSR: {ultimoVerdito.lacuna_nsr ? "com lacuna" : "inteira"}
              </Badge>
              <Badge variant={ultimoVerdito.duplicado ? "destructive" : "outline"}>
                Reimportação: {ultimoVerdito.duplicado ? "arquivo já importado" : "arquivo novo"}
              </Badge>
            </div>
            {Array.isArray(ultimoVerdito.erros) && ultimoVerdito.erros.length > 0 && (
              <div className="rounded-md border bg-muted/40 p-3 max-h-48 overflow-y-auto">
                <p className="font-medium mb-1">O que a conferência apontou</p>
                <ul className="list-disc pl-5 space-y-0.5 text-xs">
                  {ultimoVerdito.erros.map((er: any, i: number) => (
                    <li key={i}>
                      {er?.erro === "crc_invalido" && `Registro com CRC inválido${er.nsr ? ` (NSR ${er.nsr})` : ""}.`}
                      {er?.erro === "cadeia_sha256_invalida" && "Assinatura do conteúdo não confere."}
                      {er?.erro === "lacuna_nsr" && (er.detalhe || "Sequência de NSR quebrada.")}
                      {er?.erro === "arquivo_duplicado" && (er.detalhe || "Este arquivo já foi importado.")}
                      {!["crc_invalido", "cadeia_sha256_invalida", "lacuna_nsr", "arquivo_duplicado"].includes(er?.erro) &&
                        (er?.detalhe || JSON.stringify(er))}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {ultimoVerdito.quarentena && (
              <p className="text-xs text-muted-foreground">
                A Portaria 671 não admite arquivo com prova quebrada: um registro removido ou
                alterado invalida a remessa inteira. Peça ao fornecedor do equipamento uma nova
                exportação e importe de novo — a base não foi tocada.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {/* Histórico de importações */}
      <Card>
        <CardHeader><CardTitle className="text-base">Histórico de Importações</CardTitle></CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Arquivo</TableHead>
                <TableHead>Equipamento</TableHead>
                <TableHead className="text-center">Registros</TableHead>
                <TableHead className="text-center">Importados</TableHead>
                <TableHead className="text-center">Rejeitados</TableHead>
                <TableHead className="text-center">Conferência</TableHead>
                <TableHead className="text-center">Status</TableHead>
                <TableHead>Data</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : importacoes.length === 0 ? (
                <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Nenhuma importação realizada.</TableCell></TableRow>
              ) : importacoes.map((imp: any) => (
                <TableRow key={imp.id}>
                  <TableCell className="font-medium flex items-center gap-2"><FileText className="w-4 h-4" />{imp.arquivo_nome}</TableCell>
                  <TableCell>{[imp.fabricante, imp.modelo].filter(Boolean).join(" ") || "N/I"}</TableCell>
                  <TableCell className="text-center">{imp.total_registros}</TableCell>
                  <TableCell className="text-center text-primary font-medium">{imp.registros_importados}</TableCell>
                  <TableCell className="text-center text-destructive font-medium">{imp.registros_rejeitados}</TableCell>
                  <TableCell className="text-center">
                    {imp.quarentena
                      ? <Badge variant="destructive">Quarentena</Badge>
                      : imp.crc_valido === null || imp.crc_valido === undefined
                        ? <span className="text-xs text-muted-foreground">—</span>
                        : <Badge variant="outline" className="border-emerald-400 text-emerald-700">Aprovado</Badge>}
                  </TableCell>
                  <TableCell className="text-center">{statusBadge(imp.status)}</TableCell>
                  <TableCell>{format(new Date(imp.created_at), "dd/MM/yyyy HH:mm")}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card className="bg-muted/30">
        <CardContent className="p-4">
          <h4 className="font-medium mb-2">📋 Sobre REP-C</h4>
          <ul className="text-sm text-muted-foreground space-y-1">
            <li>• <strong>REP-C</strong> — Registrador Eletrônico de Ponto Convencional (relógio físico)</li>
            <li>• O arquivo AFD (.txt) é exportado diretamente do equipamento</li>
            <li>• Os registros importados alimentam as mesmas tabelas do REP-P/REP-A</li>
            <li>• Marcações são atribuídas automaticamente (entrada → saída almoço → retorno → saída)</li>
            <li>• <strong>Toda importação passa por conferência</strong>: CRC de cada registro, assinatura,
              sequência de NSR sem lacuna e arquivo não repetido. Reprovou, vai para quarentena e
              nenhuma marcação é gravada (Portaria MTP 671/2021)</li>
          </ul>
        </CardContent>
      </Card>
    </div>
  );
}
