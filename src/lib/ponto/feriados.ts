/** RN20-22 — tipos e regras do cadastro de feriados por localização.
 *
 * A abrangência 'filial' foi unificada no Calendário da unidade (feriado_tabela_*)
 * na unificação de feriados (Fases 1-2): o cadastro NÃO cria mais feriado 'filial'
 * aqui — feriado de uma unidade mora no calendário. O valor 'filial' permanece no
 * tipo apenas para LER/EXIBIR eventuais linhas legadas; o formulário não o oferece. */

export type FeriadoAbrangencia = "nacional" | "estadual" | "municipal" | "filial";
export type FeriadoTipo = "feriado" | "facultativo";

export interface Feriado {
  id: string;
  tenant_id: string | null;
  empresa_id: string | null;
  data: string | null;
  nome: string;
  abrangencia: FeriadoAbrangencia;
  uf: string | null;
  municipio: string | null;
  codigo_ibge: string | null;
  tipo: FeriadoTipo;
  recorrente: boolean;
  dia: number | null;
  mes: number | null;
  ativo: boolean;
}

export interface FeriadoForm {
  data: string;
  nome: string;
  abrangencia: "estadual" | "municipal";
  uf: string;
  municipio: string;
  codigo_ibge: string;
  empresa_id: string;
  tipo: FeriadoTipo;
  recorrente: boolean;
  dia: string;
  mes: string;
  ativo: boolean;
}

export const UFS = [
  "AC","AL","AP","AM","BA","CE","DF","ES","GO","MA","MT","MS","MG","PA","PB","PR",
  "PE","PI","RJ","RN","RS","RO","RR","SC","SP","SE","TO",
] as const;

export const MESES = [
  "Janeiro","Fevereiro","Março","Abril","Maio","Junho",
  "Julho","Agosto","Setembro","Outubro","Novembro","Dezembro",
] as const;

export const formVazioFeriado = (): FeriadoForm => ({
  data: "",
  nome: "",
  abrangencia: "estadual",
  uf: "",
  municipio: "",
  codigo_ibge: "",
  empresa_id: "",
  tipo: "feriado",
  recorrente: false,
  dia: "",
  mes: "",
  ativo: true,
});

/** Data efetiva do feriado no ano de referência (recorrente projeta dia/mês). */
export function dataEfetiva(f: Feriado, ano: number): string | null {
  if (f.recorrente) {
    if (!f.dia || !f.mes) return null;
    return `${ano}-${String(f.mes).padStart(2, "0")}-${String(f.dia).padStart(2, "0")}`;
  }
  return f.data;
}

/** Feriado incide no ano informado? */
export function incideNoAno(f: Feriado, ano: number): boolean {
  return f.recorrente ? !!(f.dia && f.mes) : !!f.data && f.data.startsWith(String(ano));
}

/** Validação do formulário — mesmas regras do trigger no banco. */
export function validarFeriado(form: FeriadoForm): string | null {
  if (!form.nome.trim()) return "Informe o nome do feriado.";
  if (form.recorrente) {
    const dia = Number(form.dia);
    const mes = Number(form.mes);
    if (!dia || !mes) return "Feriado recorrente exige dia e mês.";
    if (dia < 1 || dia > 31 || mes < 1 || mes > 12) return "Dia ou mês inválido.";
  } else if (!form.data) {
    return "Informe a data.";
  }
  if (!form.uf) return "Selecione a UF.";
  if (form.abrangencia === "municipal" && !form.municipio.trim()) {
    return "Informe o município para feriado municipal.";
  }
  return null;
}

/** Payload normalizado para gravação. */
export function payloadFeriado(form: FeriadoForm, tenantId: string) {
  const recorrente = form.recorrente;
  return {
    tenant_id: tenantId,
    data: recorrente ? null : form.data,
    nome: form.nome.trim(),
    abrangencia: form.abrangencia,
    uf: form.uf,
    municipio: form.abrangencia === "municipal" ? form.municipio.trim() : null,
    codigo_ibge: form.abrangencia === "municipal" ? form.codigo_ibge.trim() || null : null,
    empresa_id: null,
    tipo: form.tipo,
    recorrente,
    dia: recorrente ? Number(form.dia) : null,
    mes: recorrente ? Number(form.mes) : null,
    ativo: form.ativo,
  };
}

export const LABEL_ABRANGENCIA: Record<FeriadoAbrangencia, string> = {
  nacional: "Nacional",
  estadual: "Estadual",
  municipal: "Municipal",
  filial: "Filial",
};
