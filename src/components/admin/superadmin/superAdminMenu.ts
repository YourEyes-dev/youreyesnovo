import type { LucideIcon } from "lucide-react";
import {
  LayoutDashboard, Activity, Building2, Users, FileSignature, Target, TrendingUp,
  CreditCard, Handshake, FileText, Brain, Store, Landmark, Bug, Radar, BookOpen,
} from "lucide-react";

// Menu lateral do Painel Super Admin, agrupado por área de trabalho.
// É a única fonte da verdade: a casca (SuperAdminLayout) desenha o menu a
// partir daqui e o painel (SuperAdminDashboard) usa o mesmo registro para
// escolher o que renderizar em cada rota interna. Para incluir uma seção
// nova: adicionar o item aqui e, se ela abrir dentro do painel, ligar o
// componente em SuperAdminDashboard (SECOES). Páginas com rota própria
// (QA, Blog, Manual…) só precisam do item.

export interface SuperAdminMenuItem {
  /** chave estável (nome do teste de tela, data-testid, atalhos) */
  id: string;
  label: string;
  /** subtítulo curto mostrado no cabeçalho da seção */
  descricao: string;
  icon: LucideIcon;
  /** rota absoluta (sem o basename) */
  path: string;
  /** prefixos extras que mantêm o item marcado como ativo (ex.: detalhe de empresa) */
  match?: string[];
}

export interface SuperAdminMenuArea {
  id: string;
  label: string;
  /** frase curta usada nos cartões de atalho da Visão geral */
  descricao: string;
  items: SuperAdminMenuItem[];
}

export const SUPER_ADMIN_MENU: SuperAdminMenuArea[] = [
  {
    id: "painel",
    label: "Painel",
    descricao: "Indicadores e situação geral da plataforma.",
    items: [
      { id: "visao-geral", label: "Visão geral", descricao: "Indicadores da plataforma, crescimento e captação nos últimos 30 dias.", icon: LayoutDashboard, path: "/admin" },
      { id: "situacao", label: "Situação das empresas", descricao: "Plano, usuários, colaboradores, campanhas e último acesso de cada empresa.", icon: Activity, path: "/admin/situacao" },
    ],
  },
  {
    id: "clientes",
    label: "Clientes",
    descricao: "Empresas atendidas, seus usuários e os contratos aceitos.",
    items: [
      { id: "empresas", label: "Empresas", descricao: "Cadastro das empresas (matrizes e filiais), assinatura, administradores e promoção a conta-raiz.", icon: Building2, path: "/admin/empresas", match: ["/admin/tenants/"] },
      { id: "usuarios", label: "Usuários", descricao: "Todos os usuários da plataforma, de todas as empresas, em uma só busca.", icon: Users, path: "/admin/usuarios" },
      { id: "contratos", label: "Contratos e termos", descricao: "Contratos, links de assinatura e aceites com validade jurídica.", icon: FileSignature, path: "/admin/contratos" },
    ],
  },
  {
    id: "comercial",
    label: "Comercial e marketing",
    descricao: "Captação, funil de vendas, preços, parceiros e conteúdo.",
    items: [
      { id: "leads", label: "Leads CRM", descricao: "Pipeline comercial em quadro Kanban, do primeiro contato ao fechamento.", icon: Target, path: "/admin/leads" },
      { id: "landing", label: "Leads da landing", descricao: "Contatos captados pela landing page, com diagnóstico quando houver.", icon: TrendingUp, path: "/admin/landing" },
      { id: "precos", label: "Preços e add-ons", descricao: "Valores dos módulos avulsos e da vida extra oferecidos às empresas.", icon: CreditCard, path: "/admin/precos" },
      { id: "parceiros", label: "Programa de Parceiros", descricao: "Indicadores, representantes, implantadores, comissões e parâmetros do programa.", icon: Handshake, path: "/admin/parceiros" },
      { id: "blog", label: "Blog", descricao: "Artigos publicados no site institucional.", icon: FileText, path: "/admin/blog" },
    ],
  },
  {
    id: "produtos",
    label: "Produtos",
    descricao: "Acompanhamento dos produtos que a casa opera para todos os clientes.",
    items: [
      { id: "psicossocial", label: "Psicossocial", descricao: "Campanhas, respostas e classificação de risco psicossocial em todas as empresas.", icon: Brain, path: "/admin/psicossocial" },
      { id: "marketye", label: "MarketYE", descricao: "Quem entra na vitrine, denúncias, pedidos de revisão, destaques e ajustes.", icon: Store, path: "/admin/marketye" },
    ],
  },
  {
    id: "casa",
    label: "A YourEyes",
    descricao: "Dados da própria casa e regras de entrada de empresa nova.",
    items: [
      { id: "dados-youreyes", label: "Dados da YourEyes", descricao: "Cadastro fiscal e contábil da casa e as portas de entrada de empresa nova.", icon: Landmark, path: "/admin/dados-youreyes" },
    ],
  },
  {
    id: "qualidade",
    label: "Qualidade e suporte",
    descricao: "Testes, acompanhamento dos clientes e o manual do sistema.",
    items: [
      { id: "qa", label: "QA e testes", descricao: "Bateria de testes, documentação de casos e varredura de integridade.", icon: Bug, path: "/admin/qa", match: ["/admin/qa/"] },
      { id: "controle-clientes", label: "Central de Controle de Clientes", descricao: "Erros, uso e saúde dos clientes em tempo real.", icon: Radar, path: "/admin/controle-clientes" },
      { id: "manual", label: "Manual do sistema", descricao: "Manual completo, pesquisável e imprimível.", icon: BookOpen, path: "/admin/manual" },
    ],
  },
];

export const SUPER_ADMIN_ITENS: SuperAdminMenuItem[] = SUPER_ADMIN_MENU.flatMap((a) => a.items);

/** Normaliza o pathname (remove barra final) para comparar com as rotas do menu. */
function normalizar(pathname: string): string {
  const semBarra = pathname.replace(/\/+$/, "");
  return semBarra === "" ? "/" : semBarra;
}

/** Item do menu (e sua área) correspondente à rota atual; undefined se nenhuma. */
export function localizarItemDoMenu(pathname: string): { area: SuperAdminMenuArea; item: SuperAdminMenuItem } | undefined {
  const rota = normalizar(pathname);
  for (const area of SUPER_ADMIN_MENU) {
    for (const item of area.items) {
      if (rota === item.path) return { area, item };
    }
  }
  for (const area of SUPER_ADMIN_MENU) {
    for (const item of area.items) {
      if (item.match?.some((prefixo) => rota.startsWith(prefixo))) return { area, item };
    }
  }
  return undefined;
}

/**
 * Endereços antigos: o painel era uma tela única com abas escolhidas por
 * `?aba=`. Links guardados (e o aviso na vitrine do MarketYE) continuam
 * valendo — o painel redireciona para a rota nova equivalente.
 */
const ABA_LEGADA_PARA_ROTA: Record<string, string> = {
  overview: "/admin",
  tenants: "/admin/empresas",
  usuarios: "/admin/usuarios",
  leads: "/admin/leads",
  landing: "/admin/landing",
  psicossocial: "/admin/psicossocial",
  situacao: "/admin/situacao",
  precos: "/admin/precos",
  parceiros: "/admin/parceiros",
  marketye: "/admin/marketye",
  empresa: "/admin/dados-youreyes",
};

export function rotaDaAbaLegada(aba: string | null): string | undefined {
  if (!aba) return undefined;
  return ABA_LEGADA_PARA_ROTA[aba];
}
