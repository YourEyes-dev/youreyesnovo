import { AlertTriangle, Loader2, ShieldCheck } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { useIncidentes, type Incidente } from './useClientesRadar';

// Fila de trabalho do eixo técnico: erros iguais já agrupados em um incidente,
// do mais grave para o menos grave. Nada de dado pessoal aparece aqui — o
// mascaramento acontece antes de o erro ser gravado.

const SEVERIDADE: Record<Incidente['severidade'], { rotulo: string; classe: string }> = {
  critica: { rotulo: 'Crítica', classe: 'bg-red-500/10 text-red-600 border-red-500/20' },
  alta:    { rotulo: 'Alta',    classe: 'bg-orange-500/10 text-orange-600 border-orange-500/20' },
  media:   { rotulo: 'Média',   classe: 'bg-amber-500/10 text-amber-600 border-amber-500/20' },
  baixa:   { rotulo: 'Baixa',   classe: 'bg-muted text-muted-foreground border-border' },
};

function quando(iso: string) {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : format(d, "dd/MM 'às' HH:mm", { locale: ptBR });
}

export function PainelIncidentes() {
  const { data: incidentes = [], isLoading, error } = useIncidentes();

  if (isLoading) {
    return (
      <Card><CardContent className="p-10 flex items-center justify-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="w-4 h-4 animate-spin" /> Carregando incidentes…
      </CardContent></Card>
    );
  }

  if (error) {
    return (
      <Card><CardContent className="p-10 text-center text-sm text-destructive">
        Não foi possível carregar os incidentes.
      </CardContent></Card>
    );
  }

  if (incidentes.length === 0) {
    return (
      <Card><CardContent className="p-10 text-center space-y-2">
        <ShieldCheck className="w-8 h-8 text-emerald-500 mx-auto" />
        <p className="text-sm font-medium">Nenhum incidente aberto.</p>
        <p className="text-sm text-muted-foreground">
          A captura está ligada: se algo quebrar na tela de um cliente, aparece aqui em segundos.
        </p>
      </CardContent></Card>
    );
  }

  return (
    <Card>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[45%]">O que aconteceu</TableHead>
              <TableHead>Área</TableHead>
              <TableHead>Gravidade</TableHead>
              <TableHead className="text-right">Vezes</TableHead>
              <TableHead className="text-right">Clientes</TableHead>
              <TableHead>Última vez</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {incidentes.map((i) => (
              <TableRow key={i.fingerprint}>
                <TableCell className="font-medium">
                  <div className="flex items-start gap-2">
                    <AlertTriangle className="w-4 h-4 text-muted-foreground shrink-0 mt-0.5" />
                    <span className="line-clamp-2">{i.titulo}</span>
                  </div>
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">{i.modulo ?? '—'}</TableCell>
                <TableCell>
                  <Badge variant="outline" className={SEVERIDADE[i.severidade].classe}>
                    {SEVERIDADE[i.severidade].rotulo}
                  </Badge>
                </TableCell>
                <TableCell className="text-right tabular-nums">{i.ocorrencias}</TableCell>
                <TableCell className="text-right tabular-nums">{i.clientesAfetados}</TableCell>
                <TableCell className="text-sm text-muted-foreground">{quando(i.ultimoVisto)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
