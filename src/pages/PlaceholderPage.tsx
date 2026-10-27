import { motion } from "framer-motion";
import { Construction } from "lucide-react";
import { useLocation } from "react-router-dom";

const pageTitles: Record<string, string> = {
  "/feed": "Feed Social",
  "/cadastros/departamentos": "Departamentos",
  "/cadastros/cargos": "Cargos",
  "/cadastros/filiais": "Estabelecimento ou Obra",
  "/financeiro/folha": "Folha de Pagamento",
  "/financeiro/beneficios": "Benefícios",
  "/admissao": "Admissão",
  "/avaliacoes": "Avaliações",
  "/pdi": "PDI - Plano de Desenvolvimento Individual",
  "/epis": "EPIs - Equipamentos de Proteção",
  "/felicidade": "Gestão da Felicidade",
  "/usuarios": "Usuários",
};

const PlaceholderPage = () => {
  const location = useLocation();
  const title = pageTitles[location.pathname] || "Página";

  return (
    <div className="min-h-[60vh] flex items-center justify-center">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="text-center"
      >
        <div className="inline-flex p-4 rounded-2xl bg-primary/10 mb-6">
          <Construction className="w-12 h-12 text-primary" />
        </div>
        <h1 className="text-2xl font-bold text-foreground mb-2">{title}</h1>
        <p className="text-muted-foreground max-w-md">
          Esta seção está em desenvolvimento e será disponibilizada em breve.
        </p>
      </motion.div>
    </div>
  );
};

export default PlaceholderPage;
