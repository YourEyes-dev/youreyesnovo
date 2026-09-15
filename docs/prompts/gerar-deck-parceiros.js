const pptxgen = require("pptxgenjs");
const p = new pptxgen();
p.layout = "LAYOUT_WIDE";                 // 13.3 x 7.5
const W = 13.3, H = 7.5;

// ---- Paleta YourEyes ----
const NAVY = "0E2038";
const BLUE = "0A6DBC";
const ORANGE = "FF8C00";
const GREEN = "22A06B";
const INK  = "15242F";
const LIGHT = "F5F8F9";
const WHITE = "FFFFFF";
const MUTE  = "9FB0BF";     // texto secundario sobre navy
const MUTE2 = "5C6E7B";     // texto secundario sobre claro
const CARD  = "16304F";     // card sobre navy

const SANS = "Calibri";
const SERIF = "Cambria";

p.defineSlideMaster({ title: "NAVY", background: { color: NAVY } });
p.defineSlideMaster({ title: "LIGHT", background: { color: LIGHT } });

// ---------- helpers ----------
function txt(s, str, o){ s.addText(str, Object.assign({ isTextBox:true, margin:0 }, o)); }

// rodape discreto (sem barras)
function foot(s, dark){
  txt(s, "YourEyes", { x:0.6, y:H-0.55, w:3, h:0.3, fontFace:SANS, fontSize:10, bold:true,
    color: dark?WHITE:NAVY, align:"left" });
  txt(s, "Enxergue o que sua gestão ainda não vê.", { x:W-6.6, y:H-0.55, w:6, h:0.3,
    fontFace:SANS, fontSize:10, italic:true, color: dark?MUTE:MUTE2, align:"right" });
}

// moldura de imagem (placeholder para os prints reais)
function frame(s, x, y, w, h, label, sub){
  s.addShape(p.ShapeType.roundRect, { x, y, w, h, rectRadius:0.08,
    fill:{ color:CARD }, line:{ color:BLUE, width:1.5, dashType:"dash" } });
  s.addText([
    { text:"🖼  ", options:{ fontSize:16 } },
    { text:label, options:{ fontFace:SANS, fontSize:13, bold:true, color:WHITE } },
    { text: sub? "\n"+sub : "", options:{ fontFace:SANS, fontSize:10, color:MUTE, breakLine:true } }
  ], { isTextBox:true, x:x+0.15, y:y, w:w-0.3, h:h, align:"center", valign:"middle", margin:0 });
}

// numero de pilula / etiqueta
function kicker(s, str, color, x, y){
  txt(s, str.toUpperCase(), { x, y, w:8, h:0.35, fontFace:SANS, fontSize:12, bold:true,
    color:color, charSpacing:3, align:"left" });
}

// ============================================================
// SLIDE 1 — CAPA
// ============================================================
let s = p.addSlide({ masterName:"NAVY" });
// bloco de destaque lateral (sem stripe: usa um retangulo de cartao)
s.addShape(p.ShapeType.rect, { x:0, y:0, w:W, h:H, fill:{ color:NAVY } });
kicker(s, "Programa de Parceiros YourEyes", ORANGE, 0.9, 1.1);
txt(s, "Seu método já entrega resultado.", { x:0.9, y:1.7, w:9.2, h:1.0,
  fontFace:SERIF, fontSize:40, bold:true, color:WHITE, align:"left", lineSpacingMultiple:1.0 });
txt(s, "Falta ele virar plataforma.", { x:0.9, y:2.7, w:9.5, h:1.0,
  fontFace:SERIF, fontSize:40, bold:true, color:BLUE, align:"left" });
txt(s, "Como consultores de pessoas e processos transformam entrega em recorrência — com evidência que o cliente vê rodar todo dia.",
  { x:0.9, y:3.95, w:8.6, h:1.2, fontFace:SANS, fontSize:17, color:MUTE, align:"left", lineSpacingMultiple:1.15 });
// selo Iris (placeholder)
frame(s, 10.0, 1.6, 2.6, 2.6, "Íris + mockup", "arte da marca");
txt(s, "Enxergue o que sua gestão ainda não vê.", { x:0.9, y:H-0.9, w:8, h:0.4,
  fontFace:SANS, fontSize:13, italic:true, color:MUTE, align:"left" });

// ============================================================
// SLIDE 2 — O MUNDO MUDOU
// ============================================================
s = p.addSlide({ masterName:"LIGHT" });
kicker(s, "O contexto", BLUE, 0.9, 0.7);
txt(s, "O mercado de gente e gestão mudou de exigência", { x:0.9, y:1.15, w:11.5, h:1.0,
  fontFace:SERIF, fontSize:32, bold:true, color:NAVY });
txt(s, "A NR-1 psicossocial abriu a porta. Mas quem decide não quer mais um laudo na gaveta — quer ver a gestão do trabalho humano acontecendo, com prova.",
  { x:0.9, y:2.25, w:11.4, h:0.9, fontFace:SANS, fontSize:16, color:MUTE2, lineSpacingMultiple:1.15 });

const cards2 = [
  ["Da norma…", "Cumprir a lei virou o mínimo. Todo mundo promete conformidade."],
  ["…à evidência", "O diferencial agora é provar: cada ação com rastro, documento e painel."],
  ["Da entrega pontual…", "Diagnóstico, treinamento, laudo — some quando o projeto acaba."],
  ["…à governança contínua", "O cliente quer acompanhar o ano inteiro, não só no fechamento."],
];
let cx = 0.9, cy = 3.5, cw = 5.7, ch = 1.5, gap = 0.35;
cards2.forEach((c,i)=>{
  const col = i%2, row = Math.floor(i/2);
  const x = cx + col*(cw+gap), y = cy + row*(ch+0.3);
  s.addShape(p.ShapeType.roundRect, { x, y, w:cw, h:ch, rectRadius:0.06, fill:{color:WHITE},
    line:{color:"E1E8EC", width:1}, shadow:{type:"outer", color:"C9D4DA", blur:6, offset:2, angle:90, opacity:0.5} });
  txt(s, c[0], { x:x+0.3, y:y+0.18, w:cw-0.6, h:0.4, fontFace:SANS, fontSize:16, bold:true, color: i%2? BLUE:ORANGE });
  txt(s, c[1], { x:x+0.3, y:y+0.62, w:cw-0.6, h:0.8, fontFace:SANS, fontSize:13, color:MUTE2, lineSpacingMultiple:1.1 });
});
foot(s, false);

// ============================================================
// SLIDE 3 — O PROBLEMA (PDF morre)
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
kicker(s, "O problema · 1 de 2", ORANGE, 0.9, 0.7);
txt(s, "Seu melhor trabalho morre num PDF", { x:0.9, y:1.15, w:11, h:1.0,
  fontFace:SERIF, fontSize:34, bold:true, color:WHITE });
txt(s, "Você faz um diagnóstico impecável. Entrega o relatório. Três meses depois, ninguém abriu de novo. O valor que você criou virou arquivo parado — e o cliente esquece que foi você quem entregou.",
  { x:0.9, y:2.3, w:7.3, h:1.6, fontFace:SANS, fontSize:18, color:MUTE, lineSpacingMultiple:1.25 });
// estat callouts
const st3 = [["PDF","o destino de quase todo diagnóstico"],["3 meses","e o material já está esquecido"],["0","acompanhamento entre um projeto e o próximo"]];
let yy=2.4;
st3.forEach(a=>{
  txt(s, a[0], { x:9.0, y:yy, w:3.4, h:0.6, fontFace:SERIF, fontSize:30, bold:true, color:ORANGE, align:"left" });
  txt(s, a[1], { x:9.0, y:yy+0.62, w:3.4, h:0.5, fontFace:SANS, fontSize:12, color:MUTE, align:"left" });
  yy+=1.35;
});
foot(s, true);

// ============================================================
// SLIDE 4 — O PROBLEMA (vender hora nao escala)
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
kicker(s, "O problema · 2 de 2", ORANGE, 0.9, 0.7);
txt(s, "Vender hora não escala", { x:0.9, y:1.15, w:11, h:1.0,
  fontFace:SERIF, fontSize:34, bold:true, color:WHITE });
txt(s, "Seu faturamento é do tamanho da sua agenda. Cada real novo exige uma hora nova sua. Quando você para, a receita para junto — e não há ativo que continue rendendo.",
  { x:0.9, y:2.3, w:7.3, h:1.6, fontFace:SANS, fontSize:18, color:MUTE, lineSpacingMultiple:1.25 });
frame(s, 8.7, 2.2, 3.7, 3.4, "Antes → Depois", "hora avulsa  vs.  recorrência");
foot(s, true);

// ============================================================
// SLIDE 5 — A VIRADA
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
s.addShape(p.ShapeType.rect, {x:0,y:0,w:W,h:H, fill:{color:NAVY}});
kicker(s, "A virada", GREEN, 0.9, 1.4);
txt(s, "E se o seu método", { x:0.9, y:2.0, w:11.5, h:0.9, fontFace:SERIF, fontSize:44, bold:true, color:WHITE });
txt(s, "virasse plataforma?", { x:0.9, y:2.95, w:11.5, h:0.9, fontFace:SERIF, fontSize:44, bold:true, color:BLUE });
txt(s, "A YourEyes é a plataforma que transforma o que você já sabe fazer em um produto que roda todo dia na empresa do cliente — com a sua assinatura e a sua evidência.",
  { x:0.9, y:4.2, w:10.6, h:1.2, fontFace:SANS, fontSize:18, color:MUTE, lineSpacingMultiple:1.25 });
foot(s, true);

// ============================================================
// SLIDE 6 — UM DADO, UMA VEZ, PARA TUDO
// ============================================================
s = p.addSlide({ masterName:"LIGHT" });
kicker(s, "Como funciona · o princípio", BLUE, 0.9, 0.7);
txt(s, "Um dado, uma vez, para tudo", { x:0.9, y:1.15, w:11, h:1.0, fontFace:SERIF, fontSize:32, bold:true, color:NAVY });
txt(s, "Pessoas, Saúde, Segurança e Gestão no mesmo lugar. A informação entra uma vez e alimenta todos os módulos — sem retrabalho, sem planilha solta, sem silo.",
  { x:0.9, y:2.2, w:11.4, h:0.9, fontFace:SANS, fontSize:16, color:MUTE2, lineSpacingMultiple:1.15 });
const pil = [["Pessoas", BLUE],["Saúde", GREEN],["Segurança", ORANGE],["Gestão", NAVY]];
let px=0.9, pw=2.85, pg=0.28, py=3.5;
pil.forEach((c,i)=>{
  const x=px+i*(pw+pg);
  s.addShape(p.ShapeType.roundRect,{x,y:py,w:pw,h:2.6,rectRadius:0.08,fill:{color:WHITE},line:{color:"E1E8EC",width:1},
    shadow:{type:"outer",color:"C9D4DA",blur:6,offset:2,angle:90,opacity:0.5}});
  s.addShape(p.ShapeType.ellipse,{x:x+pw/2-0.35,y:py+0.35,w:0.7,h:0.7,fill:{color:c[1]}});
  txt(s, String(i+1), {x:x+pw/2-0.35,y:py+0.35,w:0.7,h:0.7,fontFace:SANS,fontSize:22,bold:true,color:WHITE,align:"center",valign:"middle"});
  txt(s, c[0], {x:x+0.2,y:py+1.25,w:pw-0.4,h:0.5,fontFace:SANS,fontSize:18,bold:true,color:NAVY,align:"center"});
  txt(s, "no mesmo fluxo", {x:x+0.2,y:py+1.75,w:pw-0.4,h:0.5,fontFace:SANS,fontSize:12,color:MUTE2,align:"center"});
});
foot(s, false);

// ============================================================
// SLIDE 7 — DO PDF AO PAINEL (processo)
// ============================================================
s = p.addSlide({ masterName:"LIGHT" });
kicker(s, "Do seu método ao painel que roda todo dia", BLUE, 0.9, 0.7);
txt(s, "O caminho, em 3 passos", { x:0.9, y:1.15, w:11, h:1.0, fontFace:SERIF, fontSize:32, bold:true, color:NAVY });
const steps=[
  ["01","Seu método entra","Seu diagnóstico, sua metodologia, seus critérios — configurados na plataforma."],
  ["02","Vira rotina viva","O que era relatório passa a rodar: campanhas, jornadas, alertas e coleta contínua."],
  ["03","Prova todo dia","O cliente acompanha em painel, com evidência e documento a cada ação. Você aparece."],
];
let sx=0.9, sw=3.8, sgap=0.35, sy=2.5;
steps.forEach((c,i)=>{
  const x=sx+i*(sw+sgap);
  s.addShape(p.ShapeType.roundRect,{x,y:sy,w:sw,h:3.1,rectRadius:0.08,fill:{color:WHITE},line:{color:"E1E8EC",width:1},
    shadow:{type:"outer",color:"C9D4DA",blur:6,offset:2,angle:90,opacity:0.5}});
  txt(s, c[0], {x:x+0.3,y:sy+0.3,w:sw-0.6,h:0.8,fontFace:SERIF,fontSize:40,bold:true,color:BLUE});
  txt(s, c[1], {x:x+0.3,y:sy+1.25,w:sw-0.6,h:0.6,fontFace:SANS,fontSize:18,bold:true,color:NAVY});
  txt(s, c[2], {x:x+0.3,y:sy+1.9,w:sw-0.6,h:1.1,fontFace:SANS,fontSize:13,color:MUTE2,lineSpacingMultiple:1.15});
  if(i<2) txt(s, "→", {x:x+sw-0.05,y:sy+1.1,w:0.5,h:0.6,fontFace:SANS,fontSize:26,bold:true,color:ORANGE,align:"center"});
});
foot(s, false);

// ============================================================
// SLIDE 8 — VEJA FUNCIONANDO (as 5 telas)
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
kicker(s, "Veja funcionando", GREEN, 0.9, 0.55);
txt(s, "Não é promessa. É sistema rodando.", { x:0.9, y:0.98, w:11.5, h:0.7, fontFace:SERIF, fontSize:28, bold:true, color:WHITE });
// hero: dashboard
frame(s, 0.9, 1.95, 6.0, 4.4, "TELA 1 — Dashboard", "Governança do Trabalho Humano\n(4 pilares + score)");
// 2x2 grid dos modulos
const g=[
  ["TELA 2 — Incidentes","Incidentes & Acidentes"],
  ["TELA 3 — EPIs","Gestão de EPIs"],
  ["TELA 4 — Psicossocial","Campanhas · entrevista guiada por IA"],
  ["TELA 5 — Financeiro","Módulo Financeiro"],
];
let gx=7.15, gw=2.9, gg=0.2, gy=1.95, gh=2.1;
g.forEach((c,i)=>{
  const col=i%2,row=Math.floor(i/2);
  frame(s, gx+col*(gw+gg), gy+row*(gh+0.2), gw, gh, c[0], c[1]);
});
foot(s, true);

// ============================================================
// SLIDE 9 — O QUE VOCE GANHA COMO PARCEIRO
// ============================================================
s = p.addSlide({ masterName:"LIGHT" });
kicker(s, "O programa de parceiros", BLUE, 0.9, 0.7);
txt(s, "O que você ganha", { x:0.9, y:1.15, w:11, h:1.0, fontFace:SERIF, fontSize:32, bold:true, color:NAVY });
const ben=[
  ["Recorrência", GREEN, "Receita que continua entre um projeto e o próximo — não do tamanho da sua agenda."],
  ["Diferenciação", BLUE, "Você deixa de ser mais um consultor. Passa a entregar plataforma com a sua marca."],
  ["Evidência", ORANGE, "Cada recomendação sua vira ação rastreável. O cliente vê o seu trabalho render."],
  ["Apoio", NAVY, "Time, material e método da YourEyes ao seu lado. Você não vende sozinho."],
];
let bx=0.9, bw=5.7, bg=0.35, by=2.4, bh=1.75;
ben.forEach((c,i)=>{
  const col=i%2,row=Math.floor(i/2);
  const x=bx+col*(bw+bg), y=by+row*(bh+0.25);
  s.addShape(p.ShapeType.roundRect,{x,y,w:bw,h:bh,rectRadius:0.06,fill:{color:WHITE},line:{color:"E1E8EC",width:1},
    shadow:{type:"outer",color:"C9D4DA",blur:6,offset:2,angle:90,opacity:0.5}});
  s.addShape(p.ShapeType.ellipse,{x:x+0.3,y:y+0.35,w:0.5,h:0.5,fill:{color:c[1]}});
  txt(s, c[0], {x:x+1.0,y:y+0.32,w:bw-1.3,h:0.5,fontFace:SANS,fontSize:18,bold:true,color:NAVY});
  txt(s, c[2], {x:x+1.0,y:y+0.82,w:bw-1.3,h:0.85,fontFace:SANS,fontSize:13,color:MUTE2,lineSpacingMultiple:1.15});
});
txt(s, "Condições comerciais do programa: a combinar na conversa.", {x:0.9,y:H-0.9,w:11,h:0.35,
  fontFace:SANS,fontSize:12,italic:true,color:MUTE2});
foot(s, false);

// ============================================================
// SLIDE 10 — POR QUE AGORA
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
kicker(s, "Por que agora", ORANGE, 0.9, 0.7);
txt(s, "A janela está aberta", { x:0.9, y:1.15, w:11, h:1.0, fontFace:SERIF, fontSize:34, bold:true, color:WHITE });
const now=[
  "A NR-1 psicossocial colocou saúde mental na pauta de toda empresa — a demanda nunca esteve tão quente.",
  "O mercado ainda trata isso como laudo pontual. Quem chegar com plataforma e evidência sai na frente.",
  "Ser parceiro fundador significa entrar antes da concorrência e ajudar a moldar o programa.",
];
let ny=2.5;
now.forEach((t,i)=>{
  s.addShape(p.ShapeType.ellipse,{x:0.9,y:ny+0.05,w:0.45,h:0.45,fill:{color:i===2?GREEN:BLUE}});
  txt(s, String(i+1), {x:0.9,y:ny+0.05,w:0.45,h:0.45,fontFace:SANS,fontSize:16,bold:true,color:WHITE,align:"center",valign:"middle"});
  txt(s, t, {x:1.6,y:ny,w:10.6,h:0.9,fontFace:SANS,fontSize:17,color:MUTE,lineSpacingMultiple:1.15});
  ny+=1.25;
});
foot(s, true);

// ============================================================
// SLIDE 11 — SEGURANCA & CONFIANCA (LGPD)
// ============================================================
s = p.addSlide({ masterName:"LIGHT" });
kicker(s, "Segurança & confiança", GREEN, 0.9, 0.7);
txt(s, "Dado sensível tratado como sensível", { x:0.9, y:1.15, w:11.5, h:1.0, fontFace:SERIF, fontSize:32, bold:true, color:NAVY });
txt(s, "Você recomenda com tranquilidade porque a base é sólida.", { x:0.9, y:2.15, w:11, h:0.5,
  fontFace:SANS, fontSize:16, color:MUTE2 });
const lg=[
  ["LGPD por dentro","Saúde é dado sensível (art. 11). Controle de acesso e trilha em cada movimento."],
  ["Cada perfil vê o seu","Camada de permissão por perfil: quem acessa o quê é regra do sistema, não confiança."],
  ["Rastro que prova","Toda ação gera documento e histórico — o oposto do PDF perdido na gaveta."],
];
let lx=0.9, lw=3.8, lgp=0.35, ly=3.0;
lg.forEach((c,i)=>{
  const x=lx+i*(lw+lgp);
  s.addShape(p.ShapeType.roundRect,{x,y:ly,w:lw,h:2.5,rectRadius:0.08,fill:{color:WHITE},line:{color:"E1E8EC",width:1},
    shadow:{type:"outer",color:"C9D4DA",blur:6,offset:2,angle:90,opacity:0.5}});
  s.addShape(p.ShapeType.ellipse,{x:x+0.3,y:ly+0.3,w:0.55,h:0.55,fill:{color:GREEN}});
  txt(s,"✓",{x:x+0.3,y:ly+0.3,w:0.55,h:0.55,fontFace:SANS,fontSize:18,bold:true,color:WHITE,align:"center",valign:"middle"});
  txt(s, c[0], {x:x+0.3,y:ly+1.0,w:lw-0.6,h:0.5,fontFace:SANS,fontSize:17,bold:true,color:NAVY});
  txt(s, c[1], {x:x+0.3,y:ly+1.5,w:lw-0.6,h:0.9,fontFace:SANS,fontSize:12.5,color:MUTE2,lineSpacingMultiple:1.15});
});
txt(s, "A YourEyes não promete conformidade automática — entrega o meio de provar o que foi feito.",
  {x:0.9,y:H-0.9,w:11.5,h:0.35,fontFace:SANS,fontSize:12,italic:true,color:MUTE2});
foot(s, false);

// ============================================================
// SLIDE 12 — COMO ENTRAR (CTA)
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
kicker(s, "Como entrar", ORANGE, 0.9, 0.9);
txt(s, "Uma conversa de 30 minutos", { x:0.9, y:1.5, w:11.5, h:1.0, fontFace:SERIF, fontSize:38, bold:true, color:WHITE });
txt(s, "Sem compromisso. A gente mostra a plataforma rodando com um caso da sua área e desenha junto como o seu método entraria.",
  { x:0.9, y:2.6, w:8.4, h:1.1, fontFace:SANS, fontSize:18, color:MUTE, lineSpacingMultiple:1.25 });
const steps12=[["1","Você agenda a conversa"],["2","Demo com um caso da sua área"],["3","Desenhamos sua entrada como parceiro"]];
let ty=4.2;
steps12.forEach(a=>{
  s.addShape(p.ShapeType.ellipse,{x:0.9,y:ty,w:0.5,h:0.5,fill:{color:BLUE}});
  txt(s,a[0],{x:0.9,y:ty,w:0.5,h:0.5,fontFace:SANS,fontSize:18,bold:true,color:WHITE,align:"center",valign:"middle"});
  txt(s,a[1],{x:1.65,y:ty+0.03,w:10,h:0.5,fontFace:SANS,fontSize:17,color:WHITE});
  ty+=0.75;
});
// botao CTA
s.addShape(p.ShapeType.roundRect,{x:9.7,y:2.7,w:2.9,h:1.0,rectRadius:0.1,fill:{color:ORANGE}});
txt(s,"Quero conversar",{x:9.7,y:2.7,w:2.9,h:1.0,fontFace:SANS,fontSize:18,bold:true,color:WHITE,align:"center",valign:"middle"});
foot(s, true);

// ============================================================
// SLIDE 13 — ENCERRAMENTO
// ============================================================
s = p.addSlide({ masterName:"NAVY" });
s.addShape(p.ShapeType.rect,{x:0,y:0,w:W,h:H,fill:{color:NAVY}});
txt(s, "Consultor que só recomenda, ensina.", { x:1.0, y:2.0, w:11.3, h:0.8, fontFace:SERIF, fontSize:30, bold:true, color:MUTE });
txt(s, "Consultor que faz acontecer — e prova —", { x:1.0, y:2.85, w:11.3, h:0.8, fontFace:SERIF, fontSize:30, bold:true, color:WHITE });
txt(s, "transforma.", { x:1.0, y:3.7, w:11.3, h:0.8, fontFace:SERIF, fontSize:30, bold:true, color:BLUE });
txt(s, "Vamos transformar juntos.", { x:1.0, y:4.8, w:11.3, h:0.6, fontFace:SANS, fontSize:20, italic:true, color:ORANGE });
txt(s, "YourEyes  ·  Enxergue o que sua gestão ainda não vê.", { x:1.0, y:H-0.9, w:11, h:0.4,
  fontFace:SANS, fontSize:13, color:MUTE });

p.writeFile({ fileName: "./YourEyes-Parceiros.pptx" })
 .then(f=>console.log("OK:", f));
