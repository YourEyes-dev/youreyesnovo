import { useMemo, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { CalendarX2, Check, Gavel, UserCheck, Ban, ShieldCheck, Info } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { confirm as confirmDialog } from "@/components/ui/confirm-dialog";
import { useAuth } from "@/hooks/useAuth";
import { useCompensacaoFalta, type CompensacaoFalta, type CompensacaoFaltaStatus } from "@/hooks/useCompensacaoFalta";
import { formatarHoraMinuto } from "@/lib/ponto/formatoHoras";

const onlyDigits = (s: string) => (s || "").replace(/\D/g, "");
const hojeMes = () => new Date().toISOString().slice(0, 7);

const STATUS_META: Record<CompensacaoFaltaStatus, { label: string; variant: any }> = {
  pendente_autorizacao: { label: "Aguardando autorização", variant: "outline" },
  pendente_homologacao: { label: "Aguardando RH", variant: "secondary" },
  autorizada: { label: "Autorizada — aguardando ciência", variant: "secondary" },
  efetivada: { label: "Efetivada (debitada no banco)", variant: "default" },
  recusada: { label: "Recusada", variant: "outline" },
  cancelada: { label: "Cancelada", variant: "outline" },
};

/**
 * Compensação de falta (CLT art. 462 e 59 §2º): converte, de forma controlada,
 * uma falta injustificada em débito do banco de horas. Só é possível com regime
 * de banco vigente E acordo de compensação vigente; passa por autorização do
 * gestor (e homologação do RH acima do limite) e só vira débito na ciência do
 * colaborador. A falta continua registrada como ocorrência; o que muda é o
 * efeito financeiro (não desconta o dia nem derruba o DSR — o débito no banco
 * é a única cobrança).
 */
export function PontoCompensacaoFaltaTab() {
  const { profile } = useAuth();
  const nomeAtor = profile?.nome_completo || undefined;
  const [competencia, setCompetencia] = useState(hojeMes());

  const {
    useCompensacoes,
    useFaltasDaCompetencia,
    verificarCompensavel,
    registrar,
    autorizar,
    homologar,
    darCiencia,
    cancelar,
  } = useCompensacaoFalta();

  const { data: compensacoes = [], isLoading: loadingComp } = useCompensacoes(competencia);
  const { data: faltas = [], isLoading: loadingFaltas } = useFaltasDaCompetencia(competencia);

  // Mapa CPF -> nome, a partir das faltas do mês (para exibir nome nas compensações).
  const nomePorCpf = useMemo(() => {
    const m: Record<string, string> = {};
    for (const f of faltas) {
      const c = onlyDigits(f.colaborador_cpf || "");
      if (c && f.colaborador_nome) m[c] = f.colaborador_nome;
    }
    return m;
  }, [faltas]);

  // Faltas que já têm uma compensação viva (não recusada/cancelada) — não
  // oferecemos "Compensar" de novo nelas.
  const compensacaoVivaPorChave = useMemo(() => {
    const s = new Set<string>();
    for (const c of compensacoes) {
      if (c.status !== "recusada" && c.status !== "cancelada") {
        s.add(`${onlyDigits(c.colaborador_cpf)}|${c.data_falta}`);
      }
    }
    return s;
  }, [compensacoes]);

  const nome = (c: string) => nomePorCpf[onlyDigits(c)] || onlyDigits(c);

  const onCompensar = async (f: any) => {
    try {
      const gate = await verificarCompensavel(f.colaborador_cpf, f.data);
      if (!gate.compensavel) {
        toast.error("Falta não pode ser compensada", {
          description: (gate.motivos || []).join(" "),
        });
        return;
      }
      const ok = await confirmDialog({
        title: "Registrar compensação de falta",
        description:
          `Converter a falta de ${nome(f.colaborador_cpf)} em ${format(new Date(f.data + "T00:00:00"), "dd/MM/yyyy")} ` +
          `em débito de ${formatarHoraMinuto(gate.jornada_min)} no banco de horas? ` +
          `A solicitação ficará aguardando autorização.`,
      });
      if (!ok) return;
      await registrar.mutateAsync({ colaboradorCpf: f.colaborador_cpf, data: f.data });
    } catch (e: any) {
      toast.error(e?.message || "Erro ao registrar compensação.");
    }
  };

  const onCancelar = async (c: CompensacaoFalta) => {
    const ok = await confirmDialog({
      title: "Cancelar compensação",
      description: `Cancelar a compensação da falta de ${nome(c.colaborador_cpf)} em ${format(new Date(c.data_falta + "T00:00:00"), "dd/MM/yyyy")}?`,
      variant: "destructive",
    });
    if (!ok) return;
    await cancelar.mutateAsync({ id: c.id });
  };

  const acoes = (c: CompensacaoFalta) => {
    switch (c.status) {
      case "pendente_autorizacao":
        return (
          <>
            <Button size="sm" variant="outline" onClick={() => autorizar.mutate({ id: c.id, nome: nomeAtor })}>
              <Gavel className="w-3.5 h-3.5 mr-1" /> Autorizar
            </Button>
            <Button size="sm" variant="ghost" className="text-destructive" onClick={() => onCancelar(c)}>
              <Ban className="w-3.5 h-3.5" />
            </Button>
          </>
        );
      case "pendente_homologacao":
        return (
          <>
            <Button size="sm" variant="outline" onClick={() => homologar.mutate({ id: c.id, nome: nomeAtor })}>
              <ShieldCheck className="w-3.5 h-3.5 mr-1" /> Homologar (RH)
            </Button>
            <Button size="sm" variant="ghost" className="text-destructive" onClick={() => onCancelar(c)}>
              <Ban className="w-3.5 h-3.5" />
            </Button>
          </>
        );
      case "autorizada":
        return (
          <>
            <Button size="sm" onClick={() => darCiencia.mutate({ id: c.id, por: nomeAtor })}>
              <UserCheck className="w-3.5 h-3.5 mr-1" /> Registrar ciência
            </Button>
            <Button size="sm" variant="ghost" className="text-destructive" onClick={() => onCancelar(c)}>
              <Ban className="w-3.5 h-3.5" />
            </Button>
          </>
        );
      default:
        return <span className="text-muted-foreground text-xs">—</span>;
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
        <div>
          <h3 className="text-lg font-semibold flex items-center gap-2">
            <CalendarX2 className="w-5 h-5 text-primary" /> Compensação de faltas
          </h3>
          <p className="text-sm text-muted-foreground max-w-2xl">
            Converte uma falta injustificada em débito do banco de horas (CLT art. 462), com acordo
            vigente, autorização do gestor e ciência do colaborador. A falta segue registrada; o
            débito no banco é a única cobrança (sem desconto do dia nem perda do DSR).
          </p>
        </div>
        <div className="min-w-[10rem]">
          <Label className="text-xs">Competência</Label>
          <Input type="month" value={competencia} onChange={(e) => setCompetencia(e.target.value)} className="h-9" />
        </div>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Compensações do mês</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-center">Falta</TableHead>
                <TableHead className="text-center">Débito</TableHead>
                <TableHead className="text-center">Prazo</TableHead>
                <TableHead className="text-center">Situação</TableHead>
                <TableHead className="text-center">Ações</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingComp ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : compensacoes.length === 0 ? (
                <TableRow><TableCell colSpan={6} className="text-center py-8 text-muted-foreground">Nenhuma compensação nesta competência.</TableCell></TableRow>
              ) : compensacoes.map((c) => (
                <TableRow key={c.id}>
                  <TableCell className="font-medium">{nome(c.colaborador_cpf)}</TableCell>
                  <TableCell className="text-center text-sm">{format(new Date(c.data_falta + "T00:00:00"), "dd/MM/yyyy")}</TableCell>
                  <TableCell className="text-center text-sm">{formatarHoraMinuto(c.minutos)}</TableCell>
                  <TableCell className="text-center text-sm">
                    {c.prazo_ate ? format(new Date(c.prazo_ate + "T00:00:00"), "dd/MM/yyyy") : <span className="text-muted-foreground">—</span>}
                  </TableCell>
                  <TableCell className="text-center">
                    <Badge variant={STATUS_META[c.status].variant}>{STATUS_META[c.status].label}</Badge>
                  </TableCell>
                  <TableCell>
                    <div className="flex items-center justify-center gap-1">{acoes(c)}</div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Faltas do mês</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {faltas.length > 0 && (
            <Alert className="m-3 mb-0">
              <Info className="h-4 w-4" />
              <AlertDescription className="text-xs">
                "Compensar" só é oferecido quando há regime de banco e acordo de compensação vigentes
                para o colaborador. Sem instrumento, a falta segue como falta (com desconto na folha).
              </AlertDescription>
            </Alert>
          )}
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Colaborador</TableHead>
                <TableHead className="text-center">Dia</TableHead>
                <TableHead className="text-center">Ação</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {loadingFaltas ? (
                <TableRow><TableCell colSpan={3} className="text-center py-8">Carregando...</TableCell></TableRow>
              ) : faltas.length === 0 ? (
                <TableRow><TableCell colSpan={3} className="text-center py-8 text-muted-foreground">Nenhuma falta registrada nesta competência.</TableCell></TableRow>
              ) : faltas.map((f: any, i: number) => {
                const jaTem = compensacaoVivaPorChave.has(`${onlyDigits(f.colaborador_cpf)}|${f.data}`);
                return (
                  <TableRow key={`${f.colaborador_cpf}-${f.data}-${i}`}>
                    <TableCell className="font-medium">{f.colaborador_nome || onlyDigits(f.colaborador_cpf)}</TableCell>
                    <TableCell className="text-center text-sm">{format(new Date(f.data + "T00:00:00"), "dd/MM/yyyy")}</TableCell>
                    <TableCell className="text-center">
                      {jaTem ? (
                        <span className="text-xs text-muted-foreground inline-flex items-center gap-1">
                          <Check className="w-3.5 h-3.5" /> Em compensação
                        </span>
                      ) : (
                        <Button size="sm" variant="outline" onClick={() => onCompensar(f)}>Compensar</Button>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
