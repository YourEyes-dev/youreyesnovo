# Manuais dos módulos — YourEyes

Manuais de cada módulo do sistema, escritos para servir de **roteiro de vídeos**
(comercial + tutorial de operação): como o módulo funciona, passo a passo,
benefícios, marcadores de onde entra cada **print** (com dados fictícios) e dois
roteiros de vídeo por módulo.

- **Molde reutilizável:** [`00_MODELO_manual-de-modulo.md`](./00_MODELO_manual-de-modulo.md)
  (estrutura padrão, marcadores de print, personas fictícias e regras de LGPD).
- **Referência de profundidade (piloto):**
  [`ponto_controle-de-ponto-eletronico.md`](./ponto_controle-de-ponto-eletronico.md).
- **Ambiente de captura dos prints:** site de teste
  (https://youreyes-dev.github.io/youreyesnovo/teste/), logado como a persona
  **Marina Alves** (Analista de RH), empresa **Empresa Staging LTDA**.

> Todos os manuais são **documentação** — nenhum altera o sistema. A produção
> segue intacta.

## Índice por seção do menu

### Estrutura Organizacional
- [Empresa](./empresa_cadastro-da-empresa.md)
- [Estabelecimentos/Obras, Departamentos e Cargos](./cadastros-estrutura_filiais-departamentos-cargos.md) *(cobre 3 itens de menu)*
- [Colaboradores](./colaboradores_gestao-de-colaboradores.md)
- [Prestadores de Serviços (Terceiros)](./terceiros_prestadores-de-servicos.md)

### Planejamento & Gestão
- [Estratégia — Planejamento, Identidade e Organograma](./estrategia_planejamento-identidade-organograma.md) *(cobre 3 itens de menu)*
- [Metas](./metas_gestao-de-metas.md)
- [Plano de Ação (5W2H)](./plano-acao_planos-de-acao-5w2h.md)

### Pessoas & Cultura
- [Onboarding (admissão e integração)](./onboarding_admissao-e-integracao.md)
- [Contratos de Experiência](./contratos-experiencia_periodo-de-experiencia.md)
- [Cultura & Celebrações](./cultura-celebracoes_cultura-e-reconhecimento.md)
- [Mural Interno](./mural-interno_comunicacao-interna.md)
- [Meu Bem-Estar](./bem-estar_meu-bem-estar.md)
- [Feedback & Desenvolvimento](./feedback-desenvolvimento_feedback-e-ocorrencias.md)
- [Ouvidoria (canal de ética)](./ouvidoria_canal-de-etica.md)

### Desenvolvimento & Performance
- [Aprendizado & Papéis](./aprendizado-papeis_competencias-e-papeis.md)
- [Trilhas](./trilhas_trilhas-de-capacitacao.md)
- [Avaliações](./avaliacoes_avaliacao-de-desempenho.md)
- [PDI](./pdi_plano-de-desenvolvimento-individual.md)
- [Mapa Comportamental](./mapa-comportamental_perfil-comportamental.md)

### Jornada & Rotina
- [Ponto (piloto)](./ponto_controle-de-ponto-eletronico.md)
- [Análise de Jornada](./analise-jornada_analise-de-jornada.md)
- [Férias](./ferias_gestao-de-ferias.md)
- [Afastamentos (atestados)](./afastamentos_atestados-e-afastamentos.md)
- [Saúde Ocupacional (ASO)](./saude-ocupacional_aso-e-exames.md)
- Benefícios → coberto no manual do [Financeiro](./financeiro_gestao-financeira.md)

### Saúde & Segurança
- [Compliance SST](./compliance-sst_conformidade-sst.md)
- [Psicossocial (NR-01)](./psicossocial_riscos-psicossociais-nr1.md)
- [Ergonomia (NR-17)](./ergonomia_analise-ergonomica-nr17.md)
- [EPIs](./epis_gestao-de-epis.md)
- [Incidentes & Acidentes](./incidentes-acidentes_incidentes-e-cat.md)

### Documentos & Governança
- [Documentos](./documentos_gestao-de-documentos.md)
- [Hub Contábil](./hub-contabil_ponte-com-a-contabilidade.md)

### Financeiro
- [Financeiro](./financeiro_gestao-financeira.md)

### Sistema
- [Meu Plano](./meu-plano_plano-e-assinatura.md)
- [Suporte](./suporte_central-de-suporte.md)
- [Configurações (usuários, perfis, auditoria)](./configuracoes_usuarios-perfis-e-auditoria.md)
- [Sobre o Sistema](./sobre-sistema_versao-e-ambiente.md)

## Observações de fidelidade (levantadas durante a escrita)

- **Afastamentos:** o menu → Afastamentos (`/atestados`) abre a tela
  **CentralGaf (MOD-GAF)**; a página `Atestados.tsx` está sem rota (possível
  legado). O manual foi escrito sobre a tela real.
- **Onboarding/Admissão:** `/admissao` redireciona para `/colaboradores` — a
  admissão é operada de dentro de Colaboradores; não há item de menu próprio.
- **Cargos:** a tela de Cargos não tem campo de CBO; o CBO fica na ficha do
  colaborador/admissão.
- **Hub Contábil:** a tela ativa é o "Hub de Comunicação Contábil" (fluxo de
  solicitações RH↔contabilidade); componentes de competências/certidões/guias
  existem no código mas não estão ligados à tela atual.
