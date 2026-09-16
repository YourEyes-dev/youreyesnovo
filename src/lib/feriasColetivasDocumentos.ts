/**
 * Comunicados de ferias coletivas em HTML, para arquivar no modulo
 * Documentos (RF-007 / arts. 139-141). Tres destinos: orgao do MTE,
 * sindicato e empregados (afixacao). O prazo legal e de 15 dias antes do
 * inicio (art. 139, §2º).
 */
export interface ColetivaDocData {
  empresaNome?: string;
  departamento: string;
  ano: number;
  p1Inicio: string;
  p1Fim: string;
  p2Inicio?: string | null;
  p2Fim?: string | null;
  totalColaboradores?: number;
}

const fmtData = (s: string) => new Date(s + "T12:00:00").toLocaleDateString("pt-BR");

function periodos(d: ColetivaDocData): string {
  const linhas = [`<li>${fmtData(d.p1Inicio)} a ${fmtData(d.p1Fim)}</li>`];
  if (d.p2Inicio && d.p2Fim) linhas.push(`<li>${fmtData(d.p2Inicio)} a ${fmtData(d.p2Fim)}</li>`);
  return `<ul>${linhas.join("")}</ul>`;
}

const CSS = `body{font-family:Arial,Helvetica,sans-serif;max-width:780px;margin:24px auto;padding:24px;color:#1f2937;}
h1{text-align:center;font-size:18px;margin:0 0 4px;}
.sub{text-align:center;color:#666;font-size:12px;margin-bottom:24px;}
p{font-size:13px;line-height:1.6;}
ul{font-size:13px;}
.sig{margin-top:56px;display:flex;justify-content:space-around;font-size:12px;text-align:center;}
.sig div{width:45%;border-top:1px solid #000;padding-top:4px;}
.foot{margin-top:40px;text-align:center;font-size:10px;color:#888;}`;

/** destino: 'mte' | 'sindicato' | 'empregados' */
export function gerarComunicadoColetivasHTML(destino: string, d: ColetivaDocData): string {
  const empresa = d.empresaNome || "A empresa";
  const abre: Record<string, { titulo: string; corpo: string }> = {
    mte: {
      titulo: "COMUNICAÇÃO DE FÉRIAS COLETIVAS — ÓRGÃO LOCAL DO MINISTÉRIO DO TRABALHO",
      corpo: `${empresa} comunica, nos termos do art. 139, §2º da CLT, a concessão de férias coletivas aos empregados do setor <strong>${d.departamento}</strong>, com no mínimo 15 dias de antecedência, nos seguintes períodos:`,
    },
    sindicato: {
      titulo: "COMUNICAÇÃO DE FÉRIAS COLETIVAS — SINDICATO DA CATEGORIA",
      corpo: `${empresa} comunica ao sindicato representativo da categoria, nos termos do art. 139, §2º da CLT, a concessão de férias coletivas aos empregados do setor <strong>${d.departamento}</strong> nos seguintes períodos:`,
    },
    empregados: {
      titulo: "AVISO DE FÉRIAS COLETIVAS — EMPREGADOS",
      corpo: `${empresa} informa aos empregados do setor <strong>${d.departamento}</strong> a concessão de férias coletivas (art. 139 da CLT). Afixe este aviso em local visível. Períodos:`,
    },
  };
  const c = abre[destino] || abre.empregados;

  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><title>${c.titulo} — ${d.departamento}</title>
<style>${CSS}</style></head><body>
<h1>${c.titulo}</h1>
<p class="sub">Férias coletivas ${d.ano} — CLT arts. 139 a 141</p>
<p>${c.corpo}</p>
${periodos(d)}
${d.totalColaboradores ? `<p>Colaboradores abrangidos: <strong>${d.totalColaboradores}</strong>.</p>` : ""}
<p>Empregados com menos de 12 meses de casa terão férias proporcionais e novo período aquisitivo, na forma do art. 140 da CLT.</p>
<div class="sig"><div>Data</div><div>Responsável — ${empresa}</div></div>
<p class="foot">Documento gerado automaticamente pelo sistema YourEyes</p>
</body></html>`;
}
