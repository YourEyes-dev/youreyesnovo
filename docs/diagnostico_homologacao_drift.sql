-- DIAGNOSTICO (read-only): por que estes casos falham na homologacao.
-- Roda cada rotina em transacao descartavel e devolve o erro/achado real,
-- agrupado por mensagem para revelar as causas comuns (objeto que falta,
-- funcao antiga, etc.). Nao altera nada.
WITH codes(codigo) AS (VALUES ('ADM-002'),('ADM-020'),('ADM-021'),('ADM-022'),('ADM-030'),('ADM-031'),('ADM-040'),('ADM-041'),('ADM-050'),('ADM-051'),('ADM-052'),('ADM-070'),('ADM-071'),('ADM-072'),('ADM-073'),('ADM-101'),('ADM-102'),('ADM-103'),('ADM-107'),('AFAST-010'),('AFAST-011'),('AFAST-020'),('AFAST-021'),('AFAST-030'),('AFAST-031'),('AFAST-032'),('AFAST-040'),('AFAST-050'),('AFAST-051'),('AFAST-060'),('AFAST-070'),('AFAST-080'),('BEN-001'),('BEN-010'),('BEN-011'),('BEN-012'),('BEN-020'),('BEN-030'),('BEN-040'),('BEN-042'),('BEN-050'),('BEN-051'),('BEN-060'),('BEN-070'),('BEN-071'),('CERT-010'),('CERT-011'),('COLAB-033'),('DADO-010'),('DESL-002'),('DESL-015'),('DESL-025'),('DESL-083'),('DESL-093'),('DESL-105'),('DESL-106'),('DOC-030'),('EMP-020'),('EMP-021'),('EMP-070'),('EMP-071'),('ENQ-010'),('ENQ-011'),('ENQ-013'),('EPI-010'),('EPI-011'),('EPI-021'),('EPI-022'),('EPI-030'),('EPI-040'),('EPI-041'),('EPI-042'),('EPI-044'),('EPI-050'),('EPI-051'),('EPI-052'),('FER-003'),('FER-004'),('FERIAS-001'),('FERIAS-003'),('FERIAS-004'),('FERIAS-008'),('FERIAS-010'),('FERIAS-011'),('FERIAS-012'),('FERIAS-013'),('FERIAS-014'),('FERIAS-015'),('FERIAS-016'),('FERIAS-024'),('FERIAS-030'),('FERIAS-031'),('FERIAS-040'),('FERIAS-041'),('FERIAS-042'),('FERIAS-051'),('FERIAS-052'),('FERIAS-054'),('FERIAS-056'),('FERIAS-070'),('FERIAS-071'),('FERIAS-090'),('FERIAS-091'),('FOLHA-001'),('FOLHA-002'),('FOLHA-030'),('FOLHA-070'),('FOLHA-071'),('FOLHA-081'),('FOLHA-090'),('HCAL-012'),('HCAT-010'),('HTPL-010'),('ISOL-005'),('MCHK-002'),('MCHK-010'),('MCHK-011'),('MEVD-010'),('MPAR-011'),('PCHK-010'),('PDOC-010'),('PLEV-010'),('PLTF-010'),('PLTF-011'),('PLTM-010'),('PLTP-010'),('PONTO-113'),('PONTO-270'),('PONTO-HOM-C1'),('PROC-010'),('PROC-011'),('REGRA-001'),('REGRA-002'),('REGRA-003'),('REGRA-004'),('REGRA-005'),('REGRA-006'),('SST-001'),('SST-002'),('SST-003'),('SST-010'),('SST-011'),('SST-020'),('SST-021'),('SST-030'),('SST-031'),('SST-040'),('SST-041'),('SST-050'),('SST-060'),('SST-070'),('SST-080'),('TAC-003'),('VIN-008'),('AFAST-001'),('DESL-003'),('DESL-065'),('FER-002'),('FERIAS-055'),('FERIAS-080'),('FERIAS-081'),('FERIAS-082'),('HIER-002'),('MKY-058'),('MKY-063'),('MKY-123'),('PONTO-001'),('PONTO-024'))
, exec AS (
  SELECT c.codigo, i.funcao_sql,
         CASE WHEN i.funcao_sql IS NULL THEN NULL ELSE public.qa_executar_descartavel(i.funcao_sql) END AS r
  FROM codes c LEFT JOIN public.qa_implementacoes i ON i.codigo=c.codigo AND i.ativo
)
SELECT codigo,
       COALESCE((r).situacao::text,'sem_rotina') AS situacao,
       left(COALESCE((r).erro_tecnico, (r).obtido, ''), 140) AS detalhe
FROM exec
ORDER BY situacao, detalhe, codigo;
