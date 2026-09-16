#!/usr/bin/env python3
"""
Gera o plano de SINCRONIA CIRÚRGICA de um cliente: traz da produção, sem
máscara, apenas as linhas de UM cliente, e atualiza só essas linhas na
homologação. O resto do ambiente fica intocado.

POR QUE ISTO EXISTE, EM VEZ DE SÓ REFAZER A CÓPIA
--------------------------------------------------
Refazer a cópia (o botão RECRIAR, modo completo) resolve o mesmo problema,
mas apaga a homologação inteira e leva ~40 minutos. Quem já tem ensaio em
andamento ou cadastro de teste lá dentro perde tudo. Esta rotina troca a
demolição por um reparo: mexe só nas linhas do cliente pedido.

O QUE TORNA ISSO POSSÍVEL
-------------------------
As CHAVES nunca são embaralhadas. A máscara só toca texto, json e listas;
uuid e inteiro passam intactos. Então cada linha da homologação sabe qual
linha da produção é a dela, e um UPDATE ... FROM casa as duas pontas sem
ambiguidade. Sem isso, não haveria como reparar — só refazer.

O QUE ELA NÃO FAZ, DE PROPÓSITO
-------------------------------
NÃO insere linhas novas. Se a produção ganhou registros depois da última
cópia, eles não existem na homologação e esta rotina não os cria. Inserir
exigiria respeitar a ordem das 627 chaves estrangeiras — o problema que a
cópia completa resolve derrubando e recriando todas elas, e que aqui
custaria mais do que vale. Em vez de inserir em silêncio ou quebrar, ela
CONTA quantas linhas da produção não acharam par e imprime o número: se
esse número for grande, o recado é "use o RECRIAR completo".

Uso:
  gerar_sincronia_cliente.py <catalogo.tsv> <chaves.tsv> <tenant-uuid>

Saída, uma linha por tabela, campos separados por TAB:
  tabela \t chave \t colunas \t condicao_do_cliente
"""

import re
import sys

# Tabelas que NÃO entram na sincronia, mesmo tendo vínculo com cliente.
#
# auth.users fica de fora por um motivo específico: mexer no e-mail de uma
# conta sem mexer, na mesma transação, na identidade correspondente
# (auth.identities, cujo identity_data guarda o e-mail) deixa o login num
# estado inconsistente que não dá erro claro — foi assim que a homologação
# passou uma corrida inteira aceitando a senha e devolvendo para a tela de
# entrada. O passo do workflow trata auth.users à parte, com a identidade
# junto e a senha em seguida.
FORA_DA_SINCRONIA = {"auth.users"}


def condicao_do_cliente(tabela: str, colunas: set, tenant: str):
    """Mesma regra da máscara (gerar_copia_mascarada.condicao_do_cliente).

    Duplicada de propósito e não importada: os dois scripts rodam em
    momentos diferentes e a sincronia precisa funcionar mesmo que a máscara
    mude. Se divergirem, a sincronia toca linha que a máscara não previu —
    então qualquer mudança aqui tem de ser espelhada lá, e vice-versa.
    """
    t = f"'{tenant}'::uuid"
    if tabela == "public.tenants":
        return f"id = {t}"
    if tabela == "auth.users":
        return f"id IN (SELECT user_id FROM public.profiles WHERE tenant_id = {t})"
    if "tenant_id" in colunas:
        return f"tenant_id = {t}"
    if "empresa_id" in colunas:
        return (f"empresa_id IN (SELECT id FROM public.empresa_cadastro "
                f"WHERE tenant_id = {t})")
    if "user_id" in colunas:
        return (f"user_id IN (SELECT user_id FROM public.profiles "
                f"WHERE tenant_id = {t})")
    return None


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2

    cat, chaves_path, tenant = sys.argv[1], sys.argv[2], sys.argv[3]
    # O uuid entra literalmente no SQL que roda com a credencial de leitura
    # da produção. Nada além de uuid passa.
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", tenant):
        print(f"erro: tenant nao parece um uuid: {tenant}", file=sys.stderr)
        return 2

    colunas_da_tabela: dict[str, list[str]] = {}
    with open(cat, encoding="utf-8") as f:
        for linha in f:
            partes = linha.rstrip("\n").split("|")
            if len(partes) < 4:
                continue
            colunas_da_tabela.setdefault(partes[0], []).append(partes[1])

    chave_da_tabela: dict[str, str] = {}
    with open(chaves_path, encoding="utf-8") as f:
        for linha in f:
            partes = linha.rstrip("\n").split("|")
            if len(partes) == 2:
                chave_da_tabela[partes[0]] = partes[1]

    com_plano = 0
    sem_chave = []
    sem_vinculo = 0
    for tabela in sorted(colunas_da_tabela):
        if tabela in FORA_DA_SINCRONIA:
            continue
        cols = colunas_da_tabela[tabela]
        cond = condicao_do_cliente(tabela, set(cols), tenant)
        if cond is None:
            # Catálogo público, motor de QA, configuração de plataforma:
            # não têm dado de cliente, então não há o que sincronizar.
            sem_vinculo += 1
            continue
        chave = chave_da_tabela.get(tabela)
        if not chave:
            sem_chave.append(tabela)
            continue
        # A chave sai da lista de colunas atualizadas: é por ela que as
        # linhas se casam, e reescrevê-la com o próprio valor é ruído.
        chave_nua = chave.strip('"')
        atualizaveis = [c for c in cols if c != chave_nua]
        if not atualizaveis:
            continue
        print("\t".join([
            tabela,
            chave,
            ", ".join(f'"{c}"' for c in atualizaveis),
            cond,
        ]))
        com_plano += 1

    print(f"-- sincronia do cliente {tenant}: {com_plano} tabelas",
          file=sys.stderr)
    print(f"--   sem vinculo com cliente (nada a sincronizar): {sem_vinculo}",
          file=sys.stderr)
    if sem_chave:
        print(f"--   SEM CHAVE PRIMARIA, ficam de fora: {', '.join(sem_chave)}",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
