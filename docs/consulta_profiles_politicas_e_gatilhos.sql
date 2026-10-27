-- SOMENTE LEITURA — como a tabela profiles esta protegida de verdade (producao pode diferir das migrations).
-- Mostra as politicas (quem pode inserir/atualizar a propria linha) e os gatilhos da tabela.
-- O que procuramos: politica de UPDATE/INSERT que exija apenas user_id = auth.uid() (sem travar tenant_id)
-- e ausencia de gatilho que impeca a troca de tenant_id.
SELECT 'politica' AS tipo, policyname AS nome, cmd AS comando, permissive AS modo,
       COALESCE(qual, '') AS using_expr, COALESCE(with_check, '') AS check_expr
FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles'
UNION ALL
SELECT 'gatilho', tgname, CASE WHEN tgtype & 2 = 2 THEN 'BEFORE' ELSE 'AFTER' END, '',
       pg_get_triggerdef(oid), ''
FROM pg_trigger WHERE tgrelid = 'public.profiles'::regclass AND NOT tgisinternal
ORDER BY 1, 2;
