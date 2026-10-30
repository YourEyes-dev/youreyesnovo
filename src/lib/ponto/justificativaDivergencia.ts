// Aviso "nome × regra" das justificativas de ponto.
//
// MESMA regra da função SQL public.ponto_justificativa_divergencia
// (migration 20261029180255_ponto_fase2_f2_catalogo_natureza.sql).
// Se mudar uma, mude a outra — o caso PONTO-497 confere o lado do banco.

export type TipoAbonoRegra = "sim" | "nao" | "configuravel";

function normalizar(nome: string): string {
  return (nome || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();
}

const NEGA_ABONO = /(nao|sem)[\s-]*abon/;
const NAO_JUSTIFICADA = /nao[\s-]*justificad/;

/** Devolve o texto do aviso quando o nome contradiz a regra de abono; senão null. */
export function divergenciaNomeRegra(nome: string, tipo: TipoAbonoRegra | string | null | undefined): string | null {
  const s = normalizar(nome);
  if (NEGA_ABONO.test(s) && tipo === "sim") {
    return "O nome diz que NÃO abona, mas a regra é Abona";
  }
  if (NAO_JUSTIFICADA.test(s) && tipo === "sim") {
    return "O nome diz que a falta NÃO é justificada, mas a regra é Abona";
  }
  if (s.includes("abon") && !NEGA_ABONO.test(s) && tipo === "nao") {
    return "O nome diz que abona, mas a regra é Não abona";
  }
  return null;
}
