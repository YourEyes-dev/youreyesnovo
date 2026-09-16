import { useMemo, useState } from 'react';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { Loader2 } from 'lucide-react';
import {
  useClientesRadar, type ClienteNoRadar, type SituacaoCliente,
} from './useClientesRadar';

// Radar dos clientes: todos os clientes ativos em uma única imagem.
//
// Cor do ponto = situação do cliente:
//   verde    → nenhum erro registrado na janela
//   vermelho → há erro registrado
//   cinza    → ainda sem monitoramento
//
// Com a captura de erros ligada, o verde passou a significar algo: o cliente
// está sendo observado e não teve erro registrado nas últimas 24 horas. O
// cinza ficou para quando não há sinal nenhum daquele cliente.
//
// Distância do centro = porte do cliente (mais colaboradores, mais perto do
// meio): o que está no miolo do radar é o que dói mais quando quebra.

const CORES: Record<SituacaoCliente, { ponto: string; texto: string; rotulo: string }> = {
  ok:        { ponto: 'fill-emerald-500', texto: 'text-emerald-600', rotulo: 'Sem erro (24h)' },
  erro:      { ponto: 'fill-red-500',     texto: 'text-red-600',     rotulo: 'Com erro' },
  sem_sinal: { ponto: 'fill-muted-foreground/40', texto: 'text-muted-foreground', rotulo: 'Sem monitoramento' },
};

const TAMANHO = 520;
const CENTRO = TAMANHO / 2;
const RAIO_MAX = CENTRO - 40;

/** Posição do cliente no radar: ângulo espalhado, raio pelo porte. */
function posicionar(cliente: ClienteNoRadar, indice: number, maiorPorte: number) {
  // Ângulo dourado: espalha os pontos sem eles se empilharem em uma linha.
  const angulo = indice * 2.399963;
  const proporcao = maiorPorte > 0 ? cliente.colaboradores / maiorPorte : 0;
  // Porte grande → perto do centro. O piso de 0,18 evita ponto em cima do eixo.
  const raio = RAIO_MAX * (0.18 + 0.82 * (1 - proporcao));
  return { x: CENTRO + raio * Math.cos(angulo), y: CENTRO + raio * Math.sin(angulo) };
}

export function RadarClientes({ aberto, aoFechar }: { aberto: boolean; aoFechar: () => void }) {
  const { data: clientes = [], isLoading, error } = useClientesRadar(aberto);
  // Ponto sob o cursor: o nome da empresa precisa aparecer na hora, e não
  // depois do atraso do balãozinho do navegador.
  const [emFoco, setEmFoco] = useState<string | null>(null);

  const pontos = useMemo(() => {
    const maiorPorte = clientes.reduce((m, c) => Math.max(m, c.colaboradores), 0);
    return clientes.map((c, i) => ({ cliente: c, ...posicionar(c, i, maiorPorte) }));
  }, [clientes]);

  const contagem = useMemo(() => ({
    ok: clientes.filter((c) => c.situacao === 'ok').length,
    erro: clientes.filter((c) => c.situacao === 'erro').length,
    sem_sinal: clientes.filter((c) => c.situacao === 'sem_sinal').length,
  }), [clientes]);

  return (
    <Dialog open={aberto} onOpenChange={(v) => { if (!v) aoFechar(); }}>
      <DialogContent className="max-w-4xl max-h-[92vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Radar dos clientes</DialogTitle>
          <DialogDescription>
            Todos os clientes ativos em uma imagem só, atualizada a cada minuto. Verde é
            cliente sem nenhum erro nas últimas 24 horas; vermelho é cliente com erro no
            período. Quem está mais perto do centro tem mais colaboradores.
          </DialogDescription>
        </DialogHeader>

        {isLoading && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground py-10 justify-center">
            <Loader2 className="w-4 h-4 animate-spin" /> Carregando os clientes…
          </div>
        )}

        {error && (
          <p className="text-sm text-destructive py-6 text-center">
            Não foi possível carregar os clientes.
          </p>
        )}

        {!isLoading && !error && clientes.length === 0 && (
          <p className="text-sm text-muted-foreground py-10 text-center">
            Nenhum cliente ativo para mostrar.
          </p>
        )}

        {!isLoading && !error && clientes.length > 0 && (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-2 text-xs">
              <Badge variant="outline" className="text-emerald-600 border-emerald-500/30">
                Sem erro: {contagem.ok}
              </Badge>
              <Badge variant="outline" className="text-red-600 border-red-500/30">
                Com erro: {contagem.erro}
              </Badge>
              <Badge variant="outline" className="text-muted-foreground">
                Sem monitoramento: {contagem.sem_sinal}
              </Badge>
            </div>

            <svg
              viewBox={`0 0 ${TAMANHO} ${TAMANHO}`}
              className="w-full max-w-[520px] mx-auto"
              role="img"
              aria-label={`Radar com ${clientes.length} clientes ativos`}
            >
              {/* Anéis e eixos do radar */}
              {[1, 0.75, 0.5, 0.25].map((f) => (
                <circle
                  key={f}
                  cx={CENTRO} cy={CENTRO} r={RAIO_MAX * f}
                  className="fill-none stroke-border"
                  strokeWidth={1}
                />
              ))}
              <line x1={CENTRO - RAIO_MAX} y1={CENTRO} x2={CENTRO + RAIO_MAX} y2={CENTRO}
                    className="stroke-border" strokeWidth={1} />
              <line x1={CENTRO} y1={CENTRO - RAIO_MAX} x2={CENTRO} y2={CENTRO + RAIO_MAX}
                    className="stroke-border" strokeWidth={1} />

              {pontos.map(({ cliente, x, y }) => {
                const focado = emFoco === cliente.id;
                return (
                  <g
                    key={cliente.id}
                    onMouseEnter={() => setEmFoco(cliente.id)}
                    onMouseLeave={() => setEmFoco((atual) => (atual === cliente.id ? null : atual))}
                    style={{ cursor: 'default' }}
                  >
                    {/* alvo invisível: facilita acertar o ponto com o mouse */}
                    <circle cx={x} cy={y} r={20} className="fill-transparent" />
                    <circle
                      cx={x} cy={y} r={focado ? 12 : 9}
                      className={`${CORES[cliente.situacao].ponto} transition-all`}
                    >
                      <title>
                        {`${cliente.nome} · ${cliente.colaboradores} colaborador(es)`}
                      </title>
                    </circle>
                  </g>
                );
              })}

              {/* Etiqueta do ponto sob o cursor, desenhada por último para
                  ficar por cima de tudo. */}
              {pontos
                .filter(({ cliente }) => cliente.id === emFoco)
                .map(({ cliente, x, y }) => {
                  const texto = `${cliente.nome} · ${cliente.colaboradores} colab. · ${
                    cliente.situacao === 'erro'
                      ? `${cliente.erros24h} ${cliente.erros24h === 1 ? 'erro' : 'erros'} em 24h`
                      : 'sem erro em 24h'
                  }`;
                  const largura = Math.min(360, 8 * texto.length + 20);
                  // A etiqueta vira para dentro quando o ponto está na borda.
                  const paraEsquerda = x + largura + 18 > TAMANHO;
                  const ex = paraEsquerda ? x - largura - 16 : x + 16;
                  const ey = Math.min(Math.max(y - 14, 4), TAMANHO - 32);
                  return (
                    <g key={`etiqueta-${cliente.id}`} pointerEvents="none">
                      <rect
                        x={ex} y={ey} width={largura} height={28} rx={6}
                        className="fill-popover stroke-border"
                        strokeWidth={1}
                      />
                      <text
                        x={ex + 10} y={ey + 18}
                        className="fill-popover-foreground"
                        style={{ fontSize: 13 }}
                      >
                        {texto}
                      </text>
                    </g>
                  );
                })}
            </svg>

            {/* A mesma informação em lista — o radar mostra o conjunto, a lista dá o nome. */}
            <div className="grid sm:grid-cols-2 gap-x-6 gap-y-1">
              {clientes.map((c) => (
                <div
                  key={c.id}
                  onMouseEnter={() => setEmFoco(c.id)}
                  onMouseLeave={() => setEmFoco((atual) => (atual === c.id ? null : atual))}
                  className={`flex items-center gap-2 text-sm py-1 border-b border-border/50 rounded px-1 ${
                    emFoco === c.id ? 'bg-accent' : ''
                  }`}
                >
                  <span
                    className={`w-2.5 h-2.5 rounded-full shrink-0 ${
                      c.situacao === 'ok' ? 'bg-emerald-500'
                        : c.situacao === 'erro' ? 'bg-red-500'
                        : 'bg-muted-foreground/40'
                    }`}
                  />
                  <span className="truncate flex-1">{c.nome}</span>
                  <span className={`text-xs ${CORES[c.situacao].texto}`}>
                    {c.situacao === 'erro'
                      ? `${c.erros24h} ${c.erros24h === 1 ? 'erro' : 'erros'} em 24h`
                      : CORES[c.situacao].rotulo}
                  </span>
                </div>
              ))}
            </div>

            <p className="text-xs text-muted-foreground">
              O radar mostra o que foi capturado nas telas dos clientes nas últimas 24 horas.
              Um cliente recém-cadastrado, ou que não abriu o sistema no período, aparece verde
              por não ter erro — ausência de erro não é o mesmo que uso intenso. A leitura de
              uso e inatividade entra na próxima etapa.
            </p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
