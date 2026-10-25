GOAL:    em 15 s: fechar a janela não mata a sessão; o Daemon segura sessões fixas (agente pessoal no dia a dia, e CLI de código) com um mascote que mostra o estado.
OUTPUT:  HyperFrames, 1080 x 1080, 30 fps (feed do LinkedIn)
TIME:    15 s x 30 = 450 frames; sem música (feed toca mudo)
LOOK:    chão #EEEEF0 (cena do Daemon) e #E3E4E8 (mesa do gancho), liso, sem grão; tinta #16171B;
         acento laranja #FF8A1F só em "sempre viva" e no ponto de status "esperando".
         display Inter 900, títulos 64 px (5,9% da altura), tracking -2%; terminal JetBrains Mono 28 px.
         meio: a UI real do Daemon a ~2x (janela #141414, abas mono com bolinha de status, raio 16);
         mascote = geometria do CubeMascot.swift (yaw 18°, pitch -7°, tilt 4°, flat 3 tons, vãos recortados).
         sombra das janelas: 0 30px 60px rgba(0,0,0,.25).
OBJECTS: janela de terminal com semáforo; o cubo com chifres e cara > <; abas Daemon · Trabalho · Código;
         tecla ⌥ Espaço; cursor grande (6% do quadro); o nome "daemon" em JetBrains Mono Bold com cursor de bloco.
MOTION:  chegada expo.out 0.5 s; câmera/movimento power3.inOut 0.5–0.6 s; saída power3.in 0.3 s;
         queda do mascote back.out(1.6) 0.6 s; títulos por palavra blur 6px→0 em 0.13 s, 0.07 s entre palavras.
SHOTS:   0–90    gancho: terminal "claude — ~" com "organiza minha semana"; cursor fecha; "Fechou. Parou tudo."
         90–156  reveal: cubo cai no centro; "Com o Daemon, ela continua viva."
         156–315 prova: ⌥Espaço; a janela sai do mascote com a mesma conversa; mascote pensa → termina (^ ^);
                 "Uma sessão fixa para cada assunto"; clique na aba Código abre o codex.
         315–375 a janela volta para o mascote, que achata e vira o cursor de bloco; digita "daemon".
         375–450 o cursor cresce de volta para o mascote sorrindo no fim da palavra (o logo);
                 "Seu agente pessoal, sempre vivo" + "Open source · github.com/LuizaumSB/daemon", parado 2 s.
BANNED:  fundo escuro com coisas pequenas flutuando; glow/partículas; gradiente roxo/azul; logo no canto;
         tudo entrando com fade + slide-up; três cards; título em cima de print escurecido; UI inventada.
QA:      f0 (thumbnail com terminal e título), f45 (clique), f100 (cubo + título), f200 (janela + mascote pensando),
         f240 (resposta + ^ ^), f290 (aba OpenCode), f350 (claim), f440 (end card parado).
