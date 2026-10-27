import { motion } from "framer-motion";
import { BeneficiosTab } from "./Financeiro";

/**
 * Rota dedicada para Benefícios (menu Jornada & Rotina) — mostra só a gestão de benefícios,
 * sem o cabeçalho e as abas do módulo Financeiro. A aba "Benefícios" dentro do Financeiro segue igual.
 */
const FinanceiroBeneficios = () => {
  return (
    <div className="space-y-6">
      <motion.div initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
        <h1 className="text-2xl font-bold text-foreground">Benefícios</h1>
        <p className="text-muted-foreground">Tipos de benefícios e vínculos com colaboradores</p>
      </motion.div>
      <BeneficiosTab />
    </div>
  );
};

export default FinanceiroBeneficios;
