import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { Receipt, Download } from "lucide-react";
import { format } from "date-fns";
import { toast } from "sonner";

interface Comprovante {
  data_hora: string;
  nsr: number | null;
  empregador: string | null;
  conteudo: Record<string, unknown> | null;
  hash_comprovante: string | null;
}

/**
 * "Meus comprovantes de ponto" — direito do trabalhador no REP-P (Portaria MTP
 * 671/2021): extrair, por período, os recibos das próprias batidas.
 *
 * A extração roda em `ponto_comprovantes_extrair`, que só devolve linhas para o
 * dono do CPF ou para quem tem papel de gestão. Aqui sempre se passa o CPF do
 * próprio usuário, lido de usuarios_base pelo vínculo com a conta.
 */
export function MeusComprovantesPonto() {
  const { tenantId, user } = useAuth();
  const hoje = new Date();
  const primeiroDia = format(new Date(hoje.getFullYear(), hoje.getMonth(), 1), "yyyy-MM-dd");
  const [ini, setIni] = useState(primeiroDia);
  const [fim, setFim] = useState(format(hoje, "yyyy-MM-dd"));
  const [buscar, setBuscar] = useState(false);

  const { data: meuCpf } = useQuery({
    queryKey: ["meu-cpf", user?.id],
    queryFn: async () => {
      if (!user?.id) return null;
      const { data } = await supabase
        .from("usuarios_base" as any)
        .select("cpf")
        .eq("auth_user_id", user.id)
        .maybeSingle() as { data: any };
      return (data?.cpf || "").replace(/\D/g, "") || null;
    },
    enabled: !!user?.id,
  });

  const { data: comprovantes = [], isFetching } = useQuery({
    queryKey: ["meus-comprovantes", tenantId, meuCpf, ini, fim],
    queryFn: async (): Promise<Comprovante[]> => {
      if (!tenantId || !meuCpf) return [];
      const { data, error } = await (supabase.rpc as any)("ponto_comprovantes_extrair", {
        p_tenant_id: tenantId,
        p_colaborador_cpf: meuCpf,
        p_ini: ini,
        p_fim: fim,
      });
      if (error) throw error;
      return (data || []) as Comprovante[];
    },
    enabled: buscar && !!tenantId && !!meuCpf,
  });

  const baixar = () => {
    if (comprovantes.length === 0) return;
    const linhas = [
      ["Data e hora", "NSR", "Empregador", "Assinatura (hash)"].join(";"),
      ...comprovantes.map((c) =>
        [
          c.data_hora ? format(new Date(c.data_hora), "dd/MM/yyyy HH:mm:ss") : "",
          c.nsr ?? "",
          (c.empregador || "").replace(/;/g, ","),
          c.hash_comprovante || "",
        ].join(";"),
      ),
    ];
    const blob = new Blob(["﻿" + linhas.join("\n")], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `meus-comprovantes-ponto_${ini}_a_${fim}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    toast.success("Arquivo baixado.");
  };

  if (!meuCpf) return null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Receipt className="w-5 h-5 text-primary" /> Meus comprovantes de ponto
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Cada batida registrada gera um comprovante com data, hora e número de série do
          registro (NSR). Você pode consultar e guardar os seus por período — é um direito seu
          (Portaria MTP 671/2021).
        </p>

        <div className="flex flex-wrap items-end gap-3">
          <div className="space-y-1">
            <Label className="text-xs">De</Label>
            <Input type="date" value={ini} onChange={(e) => setIni(e.target.value)} className="w-[160px]" />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Até</Label>
            <Input type="date" value={fim} onChange={(e) => setFim(e.target.value)} className="w-[160px]" />
          </div>
          <Button onClick={() => setBuscar(true)} disabled={isFetching}>
            {isFetching ? "Buscando..." : "Buscar"}
          </Button>
          {comprovantes.length > 0 && (
            <Button variant="outline" onClick={baixar}>
              <Download className="w-4 h-4 mr-2" /> Baixar
            </Button>
          )}
        </div>

        {buscar && (
          <div className="rounded-md border max-h-80 overflow-y-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Data e hora</TableHead>
                  <TableHead className="text-center">NSR</TableHead>
                  <TableHead>Empregador</TableHead>
                  <TableHead>Assinatura</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {isFetching ? (
                  <TableRow><TableCell colSpan={4} className="text-center py-6">Buscando...</TableCell></TableRow>
                ) : comprovantes.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center py-6 text-muted-foreground">
                      Nenhum comprovante neste período.
                    </TableCell>
                  </TableRow>
                ) : comprovantes.map((c, i) => (
                  <TableRow key={`${c.nsr}-${i}`}>
                    <TableCell className="font-medium">
                      {c.data_hora ? format(new Date(c.data_hora), "dd/MM/yyyy 'às' HH:mm:ss") : "—"}
                    </TableCell>
                    <TableCell className="text-center font-mono text-xs">{c.nsr ?? "—"}</TableCell>
                    <TableCell className="text-sm">{c.empregador || "—"}</TableCell>
                    <TableCell className="font-mono text-[10px] break-all max-w-[220px]">
                      {c.hash_comprovante || "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
