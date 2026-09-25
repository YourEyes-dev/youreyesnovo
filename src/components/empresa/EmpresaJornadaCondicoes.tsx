import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Badge } from '@/components/ui/badge';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Clock, HardHat, AlertTriangle, Lock } from 'lucide-react';
import type { EmpresaCadastro } from '@/types/empresa';
import { useTenantFeatures } from '@/hooks/useTenantFeatures';

const JORNADAS_PADRONIZADAS = [
  '44h semanais — 8h diárias (seg a sex) + 4h sábado',
  '40h semanais — 8h diárias (seg a sex)',
  '36h semanais — Escala 12x36',
  '36h semanais — Turno ininterrupto de revezamento (CF art. 7º XIV)',
  '30h semanais — 6h diárias (seg a sex)',
  '25h semanais — Tempo parcial (CLT art. 58-A)',
  '220h mensais — Jornada mensal padrão',
  '180h mensais — Jornada mensal reduzida',
  'Escala 5x1 (5 dias trabalhados x 1 folga)',
  'Escala 5x2 (5 dias trabalhados x 2 folgas)',
  'Escala 6x1 (6 dias trabalhados x 1 folga)',
  'Escala 4x2 (4 dias trabalhados x 2 folgas)',
  'Escala 12x36 (12h trabalhadas x 36h descanso)',
  'Escala 24x48 (24h trabalhadas x 48h descanso)',
  'Escala 24x72 (24h trabalhadas x 72h descanso)',
  'Jornada 4x3 (4 dias x 3 folgas)',
  'Banco de Horas (CLT art. 59 §2º)',
  'Jornada 12x36 (vigilância/saúde)',
  'Outro / Personalizada',
];

interface Props {
  data: Partial<EmpresaCadastro>;
  onChange: (updates: Partial<EmpresaCadastro>) => void;
}

const CONDICOES_ESPECIAIS = [
  { key: 'trabalho_altura' as const, label: 'Trabalho em Altura', nr: 'NR-35', icon: '🏗️' },
  { key: 'espaco_confinado' as const, label: 'Espaço Confinado', nr: 'NR-33', icon: '⚠️' },
  { key: 'insalubridade' as const, label: 'Insalubridade', nr: 'NR-15', icon: '☢️' },
  { key: 'periculosidade' as const, label: 'Periculosidade', nr: 'NR-16', icon: '⚡' },
  { key: 'aposentadoria_especial' as const, label: 'Aposentadoria Especial', nr: 'Lei 8.213/91', icon: '📋' },
];

export function EmpresaJornadaCondicoes({ data, onChange }: Props) {
  const condicoesAtivas = CONDICOES_ESPECIAIS.filter((c) => data[c.key]);

  // O módulo de Ponto é liberado pelo PLANO do cliente (feature mod.ponto).
  // Fail-open: quando o gating não está ativo (sem assinatura lida ou erro),
  // `features` fica vazio e liberamos a edição — nunca travamos um operador
  // real por não conseguir ler o plano. Só desabilitamos quando temos certeza
  // de que o plano NÃO inclui o Ponto.
  const { features, planGatingActive } = useTenantFeatures();
  const planoLiberaPonto = !planGatingActive || features.has('mod.ponto');
  const usaPonto = planoLiberaPonto && !!data.usa_controle_ponto;

  return (
    <div className="space-y-8">
      {/* Jornada e Turnos */}
      <section className="space-y-4">
        <div className="flex items-center gap-2">
          <Clock className="w-5 h-5 text-primary" />
          <h3 className="font-semibold">Jornada e Turnos</h3>
        </div>

        {/* Utiliza controle de ponto — chave que coloca a empresa no regime de
            Ponto (aparece no seletor do módulo e gera falta por dia sem
            marcação). Só editável quando o plano inclui o módulo. */}
        <div
          className={`flex items-start justify-between gap-4 p-4 rounded-lg border transition-colors ${
            usaPonto ? 'bg-primary/5 border-primary/30' : 'bg-card border-border'
          }`}
        >
          <div className="space-y-1">
            <div className="flex items-center gap-2 flex-wrap">
              <Label className="text-sm font-medium">Utiliza controle de ponto</Label>
              {data.controle_ponto_obrigatorio && (
                <Badge
                  variant="outline"
                  className="border-amber-400 text-amber-800 text-[10px] gap-1"
                  title="Mais de 20 empregados: o controle de jornada é obrigatório neste estabelecimento (CLT art. 74, §2º)."
                >
                  <Clock className="w-3 h-3" /> obrigatório
                </Badge>
              )}
              {!planoLiberaPonto && (
                <Badge variant="outline" className="text-[10px] gap-1 text-muted-foreground">
                  <Lock className="w-3 h-3" /> não incluído no plano
                </Badge>
              )}
            </div>
            <p className="text-xs text-muted-foreground max-w-prose">
              {planoLiberaPonto
                ? 'Ligado, a empresa entra no módulo de Ponto: aparece no seletor de empresas do Ponto e passa a gerar falta nos dias úteis sem marcação. Desligado, fica de fora — sem lançar falta indevida.'
                : 'O módulo de Ponto não faz parte do plano contratado por este cliente. Contrate o módulo para habilitar o controle de jornada por empresa.'}
            </p>
          </div>
          <Switch
            checked={usaPonto}
            disabled={!planoLiberaPonto}
            onCheckedChange={(v) => onChange({ usa_controle_ponto: v })}
            aria-label="Utiliza controle de ponto"
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label>Jornada Padrão</Label>
            <Select
              value={
                JORNADAS_PADRONIZADAS.includes(data.jornada_padrao || '')
                  ? data.jornada_padrao || ''
                  : data.jornada_padrao
                  ? 'Outro / Personalizada'
                  : ''
              }
              onValueChange={(v) =>
                onChange({ jornada_padrao: v === 'Outro / Personalizada' ? '' : v })
              }
            >
              <SelectTrigger>
                <SelectValue placeholder="Selecione a jornada/escala" />
              </SelectTrigger>
              <SelectContent className="max-h-80">
                {JORNADAS_PADRONIZADAS.map((j) => (
                  <SelectItem key={j} value={j}>
                    {j}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {(!JORNADAS_PADRONIZADAS.includes(data.jornada_padrao || '') ||
              data.jornada_padrao === '') && (
              <Input
                placeholder="Descreva a jornada personalizada (ex.: 6x2 com sábado alternado)"
                value={data.jornada_padrao || ''}
                onChange={(e) => onChange({ jornada_padrao: e.target.value })}
              />
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="flex items-center gap-2">
            <Switch
              checked={data.possui_terceiro_turno || false}
              onCheckedChange={(v) => onChange({ possui_terceiro_turno: v })}
            />
            <Label>Possui 3º Turno (Noturno)</Label>
          </div>
          <div className="flex items-center gap-2">
            <Switch
              checked={data.possui_escalas_especiais || false}
              onCheckedChange={(v) => onChange({ possui_escalas_especiais: v })}
            />
            <Label>Escalas Especiais</Label>
          </div>
        </div>

        {data.possui_terceiro_turno && (
          <div className="flex items-center gap-2 p-3 bg-warning/10 rounded-lg">
            <AlertTriangle className="w-4 h-4 text-warning" />
            <span className="text-sm font-medium">
              3º turno requer avaliações específicas de saúde e ergonomia (NR-17)
            </span>
          </div>
        )}
      </section>

      {/* Condições Especiais */}
      <section className="space-y-4 border-t pt-6">
        <div className="flex items-center gap-2">
          <HardHat className="w-5 h-5 text-primary" />
          <h3 className="font-semibold">Condições Especiais de Trabalho</h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {CONDICOES_ESPECIAIS.map((condicao) => (
            <div
              key={condicao.key}
              className={`flex items-center justify-between p-4 rounded-lg border transition-colors ${
                data[condicao.key]
                  ? 'bg-warning/5 border-warning/30'
                  : 'bg-card border-border'
              }`}
            >
              <div className="flex items-center gap-3">
                <span className="text-xl">{condicao.icon}</span>
                <div>
                  <span className="text-sm font-medium">{condicao.label}</span>
                  <p className="text-xs text-muted-foreground">{condicao.nr}</p>
                </div>
              </div>
              <Switch
                checked={data[condicao.key] || false}
                onCheckedChange={(v) => onChange({ [condicao.key]: v })}
              />
            </div>
          ))}
        </div>

        {condicoesAtivas.length > 0 && (
          <div className="flex flex-wrap gap-2 p-3 bg-muted rounded-lg">
            <span className="text-xs text-muted-foreground w-full mb-1">
              Condições ativas — podem gerar obrigações de treinamento e laudos:
            </span>
            {condicoesAtivas.map((c) => (
              <Badge key={c.key} variant="secondary" className="text-xs">
                {c.icon} {c.label}
              </Badge>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
