import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function TermosDeUso() {
  return (
    <div className="min-h-screen bg-background py-12 px-4">
      <div className="max-w-3xl mx-auto">
        <Button variant="ghost" asChild className="mb-6">
          <Link to="/register">
            <ArrowLeft className="w-4 h-4 mr-2" />
            Voltar ao cadastro
          </Link>
        </Button>

        <h1 className="text-3xl font-bold mb-2">Termos de Uso</h1>
        <p className="text-muted-foreground mb-8">Última atualização: 3 de setembro de 2026</p>

        <div className="prose prose-sm max-w-none space-y-6 text-foreground">
          <section>
            <h2 className="text-xl font-semibold">1. Aceitação dos Termos</h2>
            <p>Ao acessar e utilizar a plataforma YourEyes, você concorda com estes Termos de Uso. Caso não concorde, não utilize nossos serviços.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">2. Descrição do Serviço</h2>
            <p>A YourEyes é uma plataforma de gestão de pessoas, saúde e segurança do trabalho que oferece funcionalidades como gestão de colaboradores, atestados, avaliações, treinamentos, entre outros módulos.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">3. Cadastro e Conta</h2>
            <p>Para utilizar a plataforma, é necessário criar uma conta fornecendo informações verdadeiras e atualizadas. Você é responsável por manter a confidencialidade de suas credenciais de acesso.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">4. Uso Adequado</h2>
            <p>O usuário compromete-se a utilizar a plataforma de forma ética e em conformidade com a legislação vigente, não sendo permitido:</p>
            <ul className="list-disc pl-6 space-y-1">
              <li>Inserir dados falsos ou fraudulentos</li>
              <li>Compartilhar credenciais de acesso com terceiros não autorizados</li>
              <li>Utilizar a plataforma para fins ilegais</li>
              <li>Tentar acessar dados de outros tenants/empresas</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold">5. Propriedade Intelectual</h2>
            <p>Todo o conteúdo, design, código e funcionalidades da plataforma são de propriedade da YourEyes, protegidos por leis de propriedade intelectual.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">5.1. Confidencialidade e segredos comerciais</h2>
            <p>Ao usar a plataforma, participar de demonstrações, implantações ou do Programa de Parceiros, o usuário pode ter acesso a informações confidenciais da YourEyes: modelo de negócios, tabela de preços e descontos não públicos, estrutura de comissões, roteiros comerciais, materiais de implantação, metodologias, roadmap de produto, métricas e relação de clientes. Essas informações são segredos de negócio protegidos pela Lei 9.279/1996 (art. 195) e só podem ser usadas para a finalidade a que foram disponibilizadas. É vedado copiá-las, divulgá-las, usá-las para desenvolver ou favorecer produto concorrente, ou empregá-las para aliciar clientes, colaboradores ou parceiros da YourEyes. A obrigação de sigilo vigora enquanto a informação mantiver natureza confidencial e, no mínimo, por cinco anos após o término da relação.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">5.2. Programa de Parceiros</h2>
            <p>A adesão ao Programa de Parceiros (indicador, representante, implantador, clínica de SST, contabilidade) é regida pelo <Link to="/parceiros/contrato" className="text-primary underline underline-offset-2">Contrato de Parceria Comercial</Link>, aceito eletronicamente no cadastro, que complementa estes Termos e prevalece sobre eles no que se refere ao programa. Ele detalha atribuição de clientes, remuneração e níveis, fechamento e pagamento, confidencialidade, não concorrência e não aliciamento pelo prazo de doze meses após o término, uso da marca e rescisão. O parceiro não tem acesso a dados de pessoas físicas dos clientes: a Área do Parceiro exibe apenas dados da empresa (nome, plano, estágio e valores).</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">6. Disponibilidade</h2>
            <p>A YourEyes se esforça para manter a plataforma disponível 24/7, mas não garante disponibilidade ininterrupta. Manutenções programadas serão comunicadas com antecedência.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">7. Limitação de Responsabilidade</h2>
            <p>A YourEyes não se responsabiliza por danos indiretos, incidentais ou consequentes decorrentes do uso ou impossibilidade de uso da plataforma.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">8. Alterações nos Termos</h2>
            <p>Reservamo-nos o direito de atualizar estes Termos a qualquer momento. Alterações significativas serão notificadas aos usuários por e-mail ou pela própria plataforma.</p>
          </section>

          <section>
            <h2 className="text-xl font-semibold">9. Contato</h2>
            <p>Em caso de dúvidas sobre estes Termos, entre em contato pelo e-mail: contato@youreyes.com.br</p>
          </section>
        </div>
      </div>
    </div>
  );
}
