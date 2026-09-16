import { Loader2, Building2, Clock, MapPin, Footprints, Monitor } from 'lucide-react';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';
import { useDetalheIncidente } from './useClientesRadar';
import type { Incidente } from './useClientesRadar';

// Detalhe do incidente: o que a equipe precisa para corrigir sem pedir print
// ao cliente. Tudo o que aparece aqui já entrou mascarado no banco — esta tela
// não desmascara nada.

function quando(iso: string) {
  if (!iso) return '—';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '—' : format(d, "dd/MM/yyyy 'às' HH:mm:ss", { locale: ptBR });
}

export function DetalheIncidenteDialog({
  incidente, aoFechar,
}: { incidente: Incidente | null; aoFechar: () => void }) {
  const { data, isLoading, error } = useDetalheIncidente(incidente?.fingerprint ?? null);
  const eventos = data?.eventos ?? [];
  const ultimo = eventos[0];

  return (
    <Dialog open={Boolean(incidente)} onOpenChange={(v) => { if (!v) aoFechar(); }}>
      <DialogContent className="max-w-3xl max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-base leading-snug pr-6">
            {incidente?.titulo ?? 'Incidente'}
          </DialogTitle>
          <DialogDescription>
            {incidente
              ? `${incidente.ocorrencias} ${incidente.ocorrencias === 1 ? 'vez' : 'vezes'} · ` +
                `${incidente.clientesAfetados} ${incidente.clientesAfetados === 1 ? 'cliente' : 'clientes'} · ` +
                `última vez em ${quando(incidente.ultimoVisto)}`
              : null}
          </DialogDescription>
        </DialogHeader>

        {isLoading && (
          <div className="flex items-center justify-center gap-2 text-sm text-muted-foreground py-10">
            <Loader2 className="w-4 h-4 animate-spin" /> Carregando o detalhe…
          </div>
        )}

        {error && (
          <p className="text-sm text-destructive py-6 text-center">
            Não foi possível carregar o detalhe deste incidente.
          </p>
        )}

        {!isLoading && !error && data && (
          <div className="space-y-5">
            {/* Quem sentiu */}
            <section className="space-y-2">
              <h3 className="text-sm font-medium flex items-center gap-2">
                <Building2 className="w-4 h-4 text-muted-foreground" /> Clientes atingidos
              </h3>
              {data.clientes.length === 0 ? (
                <p className="text-sm text-muted-foreground">Nenhum cliente registrado.</p>
              ) : (
                <div className="space-y-1">
                  {data.clientes.map((c) => (
                    <div key={c.tenantId ?? c.nome} className="flex items-center gap-2 text-sm">
                      <span className="w-2.5 h-2.5 rounded-full bg-red-500 shrink-0" />
                      <span className="flex-1 truncate">{c.nome}</span>
                      <span className="text-xs text-muted-foreground">
                        {c.ocorrencias} {c.ocorrencias === 1 ? 'vez' : 'vezes'} · última {quando(c.ultimo)}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <Separator />

            {/* Onde e quando aconteceu a última vez */}
            {ultimo && (
              <section className="space-y-2">
                <h3 className="text-sm font-medium flex items-center gap-2">
                  <MapPin className="w-4 h-4 text-muted-foreground" /> Última ocorrência
                </h3>
                <div className="grid sm:grid-cols-2 gap-x-6 gap-y-1 text-sm">
                  <p><span className="text-muted-foreground">Empresa:</span> {ultimo.empresa}</p>
                  <p className="flex items-center gap-1">
                    <Clock className="w-3.5 h-3.5 text-muted-foreground" />
                    {quando(ultimo.ocorridoEm)}
                  </p>
                  <p><span className="text-muted-foreground">Tela:</span> {ultimo.rota ?? '—'}</p>
                  <p><span className="text-muted-foreground">Ação:</span> {ultimo.acao ?? '—'}</p>
                  <p><span className="text-muted-foreground">Área:</span> {ultimo.modulo ?? '—'}</p>
                  <p><span className="text-muted-foreground">Usuário:</span> {ultimo.usuarioPseudo ?? '—'}</p>
                  <p><span className="text-muted-foreground">Versão:</span> {ultimo.versaoApp ?? '—'}</p>
                  <p><span className="text-muted-foreground">Origem:</span> {ultimo.origem} ({ultimo.ambiente})</p>
                </div>
                {ultimo.navegadorOs && (
                  <p className="text-xs text-muted-foreground flex items-start gap-1">
                    <Monitor className="w-3.5 h-3.5 shrink-0 mt-0.5" />
                    <span className="break-all">{ultimo.navegadorOs}</span>
                  </p>
                )}
              </section>
            )}

            {/* O caminho do usuário até o erro */}
            {ultimo && ultimo.breadcrumbs.length > 0 && (
              <>
                <Separator />
                <section className="space-y-2">
                  <h3 className="text-sm font-medium flex items-center gap-2">
                    <Footprints className="w-4 h-4 text-muted-foreground" /> O que o usuário fez antes
                  </h3>
                  <ol className="text-sm text-muted-foreground space-y-1">
                    {ultimo.breadcrumbs.map((b, i) => (
                      <li key={`${b}-${i}`} className="flex gap-2">
                        <span className="text-xs tabular-nums opacity-60">{i + 1}.</span>
                        <span className="break-words">{b}</span>
                      </li>
                    ))}
                  </ol>
                </section>
              </>
            )}

            {/* Detalhe técnico */}
            {ultimo && (
              <>
                <Separator />
                <section className="space-y-2">
                  <h3 className="text-sm font-medium">Detalhe técnico</h3>
                  <pre className="text-xs bg-muted/50 rounded-md p-3 overflow-x-auto whitespace-pre-wrap break-words max-h-64">
{ultimo.mensagem}{ultimo.stack ? `\n\n${ultimo.stack}` : ''}
                  </pre>
                  <p className="text-xs text-muted-foreground">
                    CPF, e-mail, telefone e segredos já saíram do texto na entrada — o que aparece
                    como <code>[cpf]</code> ou <code>[email]</code> nunca foi gravado por extenso.
                  </p>
                </section>
              </>
            )}

            {/* Histórico curto */}
            {eventos.length > 1 && (
              <>
                <Separator />
                <section className="space-y-2">
                  <h3 className="text-sm font-medium">Ocorrências recentes</h3>
                  <div className="space-y-1">
                    {eventos.slice(0, 20).map((e) => (
                      <div key={e.id} className="flex items-center gap-2 text-xs text-muted-foreground">
                        <Badge variant="outline" className="shrink-0">{e.empresa}</Badge>
                        <span className="truncate flex-1">{e.rota ?? '—'}</span>
                        <span className="shrink-0">{quando(e.ocorridoEm)}</span>
                      </div>
                    ))}
                  </div>
                </section>
              </>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
