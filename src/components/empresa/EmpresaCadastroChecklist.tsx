import { useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Badge } from '@/components/ui/badge';
import { CheckCircle2, Circle, AlertCircle, ChevronRight } from 'lucide-react';
import type { EmpresaCadastro } from '@/types/empresa';

type FieldStatus = {
  label: string;
  required: boolean;
  filled: boolean;
};

type TabBlock = {
  id: string;
  title: string;
  fields: FieldStatus[];
};

interface Props {
  data: Partial<EmpresaCadastro>;
  onGoToTab: (tab: string) => void;
}

const notEmpty = (v: any): boolean => {
  if (v === null || v === undefined) return false;
  if (typeof v === 'string') return v.trim().length > 0;
  if (typeof v === 'number') return true;
  if (typeof v === 'boolean') return true;
  if (Array.isArray(v)) return v.length > 0;
  if (typeof v === 'object') return Object.keys(v).length > 0;
  return false;
};

export function EmpresaCadastroChecklist({ data, onGoToTab }: Props) {
  const blocks: TabBlock[] = useMemo(() => {
    const tipo = data.tipo_pessoa || 'pj';
    return [
      {
        id: 'dados',
        title: 'Dados Básicos',
        fields: [
          { label: 'Razão Social / Nome', required: true, filled: notEmpty(data.razao_social) },
          { label: tipo === 'pj' ? 'CNPJ' : 'CPF', required: true, filled: notEmpty(tipo === 'pj' ? data.cnpj : data.cpf) },
          { label: 'Nome Fantasia', required: false, filled: notEmpty(data.nome_fantasia) },
          { label: 'E-mail', required: true, filled: notEmpty(data.email) },
          { label: 'Telefone', required: false, filled: notEmpty(data.telefone) },
          { label: 'CEP', required: true, filled: notEmpty(data.cep) },
          { label: 'Endereço', required: true, filled: notEmpty(data.endereco) },
          { label: 'Cidade', required: true, filled: notEmpty(data.cidade) },
          { label: 'Estado', required: true, filled: notEmpty(data.estado) },
          { label: 'Inscrição Estadual', required: false, filled: notEmpty(data.inscricao_estadual) },
          { label: 'Inscrição Municipal', required: false, filled: notEmpty(data.inscricao_municipal) },
        ],
      },
      {
        id: 'enquadramento',
        title: 'Enquadramento Legal',
        fields: [
          { label: 'CNAE Principal', required: true, filled: notEmpty(data.cnae_principal) },
          { label: 'Grau de Risco', required: true, filled: notEmpty(data.grau_risco) },
          { label: 'Situação do SESMT', required: true, filled: notEmpty(data.sesmt_situacao) },
          { label: 'Profissionais do SESMT', required: !!data.sesmt_obrigatorio, filled: notEmpty(data.sesmt_profissionais) },
          { label: 'Situação da CIPA', required: true, filled: notEmpty(data.cipa_situacao) },
          { label: 'Mandato da CIPA', required: data.cipa_situacao === 'ativa', filled: notEmpty(data.cipa_data_mandato_inicio) && notEmpty(data.cipa_data_mandato_fim) },
          { label: 'Membros da CIPA', required: data.cipa_situacao === 'ativa', filled: notEmpty(data.cipa_membros) },
        ],
      },
      {
        id: 'inclusao',
        title: 'Obrigações de Inclusão',
        fields: [
          { label: 'Cota PCD exigida', required: !!data.pcd_obrigatoria, filled: notEmpty(data.pcd_quantidade_exigida) },
          { label: 'PCDs contratados atualmente', required: !!data.pcd_obrigatoria, filled: data.pcd_quantidade_atual !== undefined && data.pcd_quantidade_atual !== null },
          { label: 'Cota mínima de Aprendizes', required: !!data.aprendiz_obrigatorio, filled: notEmpty(data.aprendiz_quantidade_minima) },
          { label: 'Aprendizes contratados atualmente', required: !!data.aprendiz_obrigatorio, filled: data.aprendiz_quantidade_atual !== undefined && data.aprendiz_quantidade_atual !== null },
        ],
      },
      {
        id: 'indicadores',
        title: 'Indicadores Previdenciários',
        fields: [
          { label: 'FAP atual', required: false, filled: notEmpty(data.fap_atual) },
          { label: 'Histórico do FAP', required: false, filled: notEmpty(data.fap_historico) },
          { label: 'Detalhes do TAC', required: !!data.tac_possui, filled: notEmpty(data.tac_detalhes) },
        ],
      },
      {
        id: 'jornada',
        title: 'Jornada e Condições',
        fields: [
          { label: 'Jornada padrão', required: true, filled: notEmpty(data.jornada_padrao) },
          { label: 'Turnos cadastrados', required: false, filled: notEmpty(data.turnos) },
          { label: 'Total de colaboradores', required: true, filled: notEmpty(data.total_colaboradores) },
        ],
      },
      {
        id: 'ai',
        title: 'Contexto I.A.',
        fields: [
          { label: 'Contexto para I.A.', required: false, filled: notEmpty(data.ai_context) },
        ],
      },
      {
        id: 'logo',
        title: 'Logo',
        fields: [
          { label: 'Logo da empresa', required: false, filled: notEmpty(data.logo_url) },
        ],
      },
    ];
  }, [data]);

  const stats = useMemo(() => {
    let reqTotal = 0, reqFilled = 0, optTotal = 0, optFilled = 0;
    blocks.forEach(b => b.fields.forEach(f => {
      if (f.required) { reqTotal++; if (f.filled) reqFilled++; }
      else { optTotal++; if (f.filled) optFilled++; }
    }));
    const totalAll = reqTotal + optTotal;
    const filledAll = reqFilled + optFilled;
    return {
      reqTotal, reqFilled, optTotal, optFilled,
      reqPct: reqTotal ? Math.round((reqFilled / reqTotal) * 100) : 100,
      overallPct: totalAll ? Math.round((filledAll / totalAll) * 100) : 0,
    };
  }, [blocks]);

  const completo = stats.reqFilled === stats.reqTotal;

  const pendentesObrigatorios = useMemo(
    () => blocks.flatMap(b => b.fields
      .filter(f => f.required && !f.filled)
      .map(f => ({ blockId: b.id, blockTitle: b.title, label: f.label }))
    ),
    [blocks]
  );

  return (
    <div className="space-y-4">
      {!completo && pendentesObrigatorios.length > 0 && (
        <Card className="border-destructive/40 bg-destructive/5">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2 text-destructive">
              <AlertCircle className="w-5 h-5" />
              {pendentesObrigatorios.length} campo(s) obrigatório(s) pendente(s)
            </CardTitle>
            <CardDescription>
              Clique em um item para ir direto ao campo correspondente.
            </CardDescription>
          </CardHeader>
          <CardContent className="pt-0">
            <ul className="grid grid-cols-1 md:grid-cols-2 gap-2" data-testid="checklist-pendencias">
              {pendentesObrigatorios.map((p, i) => (
                <li key={i}>
                  <button
                    type="button"
                    onClick={() => onGoToTab(p.blockId)}
                    className="w-full text-left flex items-center gap-2 rounded-md border border-destructive/30 bg-background hover:bg-destructive/10 transition-colors px-3 py-2"
                  >
                    <AlertCircle className="w-4 h-4 text-destructive shrink-0" />
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium truncate">{p.label}</div>
                      <div className="text-[11px] text-muted-foreground">{p.blockTitle}</div>
                    </div>
                    <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
                  </button>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}

      <Card className="border-primary/20">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              {completo ? (
                <CheckCircle2 className="w-5 h-5 text-emerald-500" />
              ) : (
                <AlertCircle className="w-5 h-5 text-amber-500" />
              )}
              Checklist do Cadastro
            </CardTitle>
            <CardDescription>
              Acompanhe o que ainda falta preencher — campos obrigatórios e opcionais.
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant={completo ? 'default' : 'secondary'} className={completo ? 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-400 border-emerald-500/30' : ''}>
              Obrigatórios: {stats.reqFilled}/{stats.reqTotal}
            </Badge>
            <Badge variant="outline">
              Opcionais: {stats.optFilled}/{stats.optTotal}
            </Badge>
          </div>
        </div>
        <div className="mt-3 space-y-2">
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted-foreground">Obrigatórios preenchidos</span>
            <span className="font-medium">{stats.reqPct}%</span>
          </div>
          <Progress value={stats.reqPct} className="h-2" />
          <div className="flex items-center justify-between text-xs mt-1">
            <span className="text-muted-foreground">Completude geral (com opcionais)</span>
            <span className="font-medium">{stats.overallPct}%</span>
          </div>
          <Progress value={stats.overallPct} className="h-1.5 opacity-70" />
        </div>
      </CardHeader>
      <CardContent className="pt-0">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {blocks.map(block => {
            const reqTotal = block.fields.filter(f => f.required).length;
            const reqFilled = block.fields.filter(f => f.required && f.filled).length;
            const pendentesObr = block.fields.filter(f => f.required && !f.filled);
            const pendentesOpc = block.fields.filter(f => !f.required && !f.filled);
            const blockOk = reqFilled === reqTotal;
            return (
              <button
                key={block.id}
                type="button"
                onClick={() => onGoToTab(block.id)}
                className="text-left rounded-lg border bg-card hover:bg-accent/40 transition-colors p-3 group"
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    {blockOk ? (
                      <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                    ) : (
                      <Circle className="w-4 h-4 text-amber-500" />
                    )}
                    <span className="text-sm font-medium">{block.title}</span>
                  </div>
                  <ChevronRight className="w-4 h-4 text-muted-foreground group-hover:translate-x-0.5 transition-transform" />
                </div>
                <div className="flex items-center gap-2 mb-2">
                  <Badge variant="outline" className="text-[10px] px-1.5 py-0">
                    Obr. {reqFilled}/{reqTotal}
                  </Badge>
                  {pendentesOpc.length > 0 && (
                    <Badge variant="outline" className="text-[10px] px-1.5 py-0 text-muted-foreground">
                      {pendentesOpc.length} opc.
                    </Badge>
                  )}
                </div>
                <ul className="space-y-1">
                  {block.fields.slice(0, 6).map((f, i) => (
                    <li key={i} className="flex items-center gap-1.5 text-xs">
                      {f.filled ? (
                        <CheckCircle2 className="w-3 h-3 text-emerald-500 shrink-0" />
                      ) : f.required ? (
                        <AlertCircle className="w-3 h-3 text-amber-500 shrink-0" />
                      ) : (
                        <Circle className="w-3 h-3 text-muted-foreground/60 shrink-0" />
                      )}
                      <span className={f.filled ? 'text-muted-foreground line-through' : 'text-foreground'}>
                        {f.label}
                      </span>
                      {!f.filled && f.required && (
                        <span className="text-[10px] text-amber-600 dark:text-amber-400 ml-auto">obrigatório</span>
                      )}
                      {!f.filled && !f.required && (
                        <span className="text-[10px] text-muted-foreground ml-auto">opcional</span>
                      )}
                    </li>
                  ))}
                  {block.fields.length > 6 && (
                    <li className="text-[10px] text-muted-foreground pl-4.5">
                      +{block.fields.length - 6} campo(s)…
                    </li>
                  )}
                </ul>
              </button>
            );
          })}
        </div>
      </CardContent>
    </Card>
    </div>
  );
}
