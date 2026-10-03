// Dados fictícios fixos da empresa de demonstração (só ambiente de TESTE).
// Nada aqui é dado real: nomes inventados, CPFs da faixa fictícia da casa
// (900.000.0XX, com dígito verificador calculado), CNPJ com DV válido.

// IDs fixos: tornam a semeadura idempotente e fácil de achar/apagar.
export const DEMO_TENANT_ID = "d3e00000-0000-4000-8000-000000000001";
export const DEMO_EMPRESA_ID = "d3e00000-0000-4000-8000-000000000002";

export const DEMO_EMAIL = "ana.demonstracao@youreyes.demo";
export const DEMO_SENHA_PADRAO = "DemoYourEyes2026";
export const DEMO_NOME = "Ana Demonstração";

/** Dígitos verificadores de CPF (algoritmo oficial). */
export function cpfComDv(base9: string): string {
  const d = base9.split("").map(Number);
  const dv = (arr: number[], pesoIni: number) => {
    const soma = arr.reduce((s, n, i) => s + n * (pesoIni - i), 0);
    const r = (soma * 10) % 11;
    return r === 10 ? 0 : r;
  };
  const d1 = dv(d, 10);
  const d2 = dv([...d, d1], 11);
  return base9 + d1 + d2;
}

/** Dígitos verificadores de CNPJ (algoritmo oficial). */
export function cnpjComDv(base12: string): string {
  const d = base12.split("").map(Number);
  const calc = (arr: number[]) => {
    const pesos = arr.length === 12 ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const soma = arr.reduce((s, n, i) => s + n * pesos[i], 0);
    const r = soma % 11;
    return r < 2 ? 0 : 11 - r;
  };
  const d1 = calc(d);
  const d2 = calc([...d, d1]);
  return base12 + d1 + d2;
}

export function formatarCnpj(c: string): string {
  return `${c.slice(0, 2)}.${c.slice(2, 5)}.${c.slice(5, 8)}/${c.slice(8, 12)}-${c.slice(12)}`;
}

// CNPJ fictício: raiz sequencial 98.765.432, filial 0001, DV calculado.
export const DEMO_CNPJ = formatarCnpj(cnpjComDv("987654320001"));

// CPF da Ana: base 900.000.000 (início da faixa fictícia).
export const DEMO_CPF_ANA = cpfComDv("900000000");

export interface SetorDemo {
  nome: string;
  descricao: string;
  ghe: { codigo: string; nome: string; descricao: string };
  cargos: { nome: string; nivel: string; qtd: number }[];
}

// 4 setores = 4 GHE. Total de colaboradores: 77 (CPFs de base 900.000.021 a 900.000.097).
export const SETORES: SetorDemo[] = [
  {
    nome: "Produção",
    descricao: "Usinagem, solda e montagem de estruturas metálicas",
    ghe: { codigo: "DEMO-GHE-PROD", nome: "Produção", descricao: "Operadores de usinagem, soldadores e montadores — turnos A e B." },
    cargos: [
      { nome: "Operador de Usinagem CNC", nivel: "pleno", qtd: 14 },
      { nome: "Soldador", nivel: "pleno", qtd: 12 },
      { nome: "Montador de Estruturas Metálicas", nivel: "junior", qtd: 7 },
      { nome: "Líder de Produção", nivel: "senior", qtd: 2 },
    ],
  },
  {
    nome: "Manutenção",
    descricao: "Manutenção mecânica e elétrica de máquinas e utilidades",
    ghe: { codigo: "DEMO-GHE-MANUT", nome: "Manutenção", descricao: "Mecânicos e eletricistas de manutenção — plantão e sobreaviso." },
    cargos: [
      { nome: "Mecânico de Manutenção", nivel: "pleno", qtd: 7 },
      { nome: "Eletricista de Manutenção", nivel: "pleno", qtd: 5 },
      { nome: "Supervisor de Manutenção", nivel: "senior", qtd: 1 },
    ],
  },
  {
    nome: "Logística",
    descricao: "Recebimento, armazenagem e expedição",
    ghe: { codigo: "DEMO-GHE-LOG", nome: "Logística", descricao: "Operadores de empilhadeira e auxiliares de expedição." },
    cargos: [
      { nome: "Operador de Empilhadeira", nivel: "pleno", qtd: 6 },
      { nome: "Auxiliar de Logística", nivel: "junior", qtd: 8 },
      { nome: "Coordenador de Logística", nivel: "senior", qtd: 1 },
    ],
  },
  {
    nome: "Administrativo",
    descricao: "RH, financeiro, compras e qualidade",
    ghe: { codigo: "DEMO-GHE-ADM", nome: "Administrativo", descricao: "Equipes de escritório: RH, financeiro, compras e qualidade." },
    cargos: [
      { nome: "Analista de RH", nivel: "pleno", qtd: 3 },
      { nome: "Analista Financeiro", nivel: "pleno", qtd: 3 },
      { nome: "Comprador", nivel: "pleno", qtd: 2 },
      { nome: "Analista da Qualidade", nivel: "pleno", qtd: 3 },
      { nome: "Gerente Administrativo", nivel: "senior", qtd: 1 },
      { nome: "Assistente Administrativo", nivel: "junior", qtd: 2 },
    ],
  },
];

const PRENOMES_M = ["Carlos", "José", "Marcos", "Rafael", "Diego", "Paulo", "André", "Lucas", "Thiago", "Fábio",
  "Rodrigo", "Eduardo", "Gustavo", "Leandro", "Márcio", "Renato", "Sérgio", "Vinícius", "Wagner", "Bruno"];
const PRENOMES_F = ["Mariana", "Juliana", "Patrícia", "Fernanda", "Camila", "Aline", "Tatiane", "Renata", "Larissa", "Priscila",
  "Simone", "Débora", "Vanessa", "Cristiane", "Luciana", "Bianca", "Daniela", "Eliane", "Gabriela", "Helena"];
const SOBRENOMES = ["Albuquerque Teles", "Barreto Nunes", "Campos Lacerda", "Dantas Moreira", "Esteves Prado", "Falcão Brito",
  "Gouveia Leme", "Holanda Pires", "Imbassahy Costa", "Jardim Siqueira", "Leal Fontes", "Macedo Arruda", "Nogueira Paes",
  "Ornelas Vidal", "Peixoto Rangel", "Queiroz Bastos", "Rezende Matos", "Sampaio Valente", "Toledo Quintana", "Uchôa Ferraz"];

export interface ColaboradorDemo {
  nome: string;
  cpf: string;
  genero: "masculino" | "feminino";
  setor: string;
  cargo: string;
  dataNascimento: string;
  dataAdmissao: string;
  email: string;
}

/** 77 colaboradores determinísticos (mesma lista em toda execução). */
export function gerarColaboradores(): ColaboradorDemo[] {
  const lista: ColaboradorDemo[] = [];
  let i = 0;
  for (const s of SETORES) {
    for (const c of s.cargos) {
      for (let k = 0; k < c.qtd; k++) {
        const base = String(900000021 + i);
        // Produção/Manutenção/Logística majoritariamente masculinas; Administrativo misto.
        const feminino = s.nome === "Administrativo" ? i % 3 !== 0 : i % 6 === 0;
        const prenome = feminino ? PRENOMES_F[(i * 7) % 20] : PRENOMES_M[(i * 7) % 20];
        const sobrenome = SOBRENOMES[(i * 3 + Math.floor(i / 20) * 7 + 5) % 20];
        const ano = 1968 + ((i * 11) % 34);
        const mes = String(1 + ((i * 5) % 12)).padStart(2, "0");
        const dia = String(1 + ((i * 13) % 27)).padStart(2, "0");
        const anoAdm = 2014 + ((i * 7) % 11);
        const mesAdm = String(1 + ((i * 3) % 12)).padStart(2, "0");
        const slug = `${prenome}.${sobrenome.split(" ")[0]}`.toLowerCase()
          .normalize("NFD").replace(/[̀-ͯ]/g, "");
        lista.push({
          nome: `${prenome} ${sobrenome}`,
          cpf: cpfComDv(base),
          genero: feminino ? "feminino" : "masculino",
          setor: s.nome,
          cargo: c.nome,
          dataNascimento: `${ano}-${mes}-${dia}`,
          dataAdmissao: `${anoAdm}-${mesAdm}-10`,
          email: `${slug}.${i + 1}@metalurgica-exemplo.demo`,
        });
        i++;
      }
    }
  }
  return lista;
}
