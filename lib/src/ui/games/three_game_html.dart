/// The self-contained HTML for the in-app games, drawn with the **HTML5 Canvas
/// 2D** API (no Three.js / WebGL — crisp and dependency-free). Parameterised
/// only by a message [nonce]; the game type, board state and current user
/// arrive over postMessage from Flutter, and moves/scores go back the same way.
/// Kept JS-template-literal- and `$`-free so it embeds cleanly in a Dart string.
String threeGameHtml(String nonce) => '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  html,body{margin:0;height:100%;overflow:hidden;background:#0b1220;font-family:-apple-system,sans-serif;}
  #c{display:block;width:100%;height:100%;touch-action:none;}
  #hud{position:absolute;top:12px;left:0;right:0;text-align:center;color:#fff;font-weight:700;font-size:17px;pointer-events:none;}
  #over{position:absolute;inset:0;display:none;flex-direction:column;align-items:center;justify-content:center;color:#fff;background:rgba(0,0,0,.55);}
  #over .msg{font-size:22px;font-weight:700;margin-bottom:14px;}
  #over button,#pad button{border:0;border-radius:10px;background:#2563eb;color:#fff;font-weight:700;font-size:16px;padding:11px 22px;}
  #pad{position:absolute;bottom:20px;left:0;right:0;display:none;justify-content:center;gap:12px;}
  #pad button{background:#1e293b;}
</style></head><body>
<div id="hud"></div>
<canvas id="c"></canvas>
<div id="pad"></div>
<div id="over"><div class="msg" id="overmsg"></div><button id="again">Play again</button></div>
<script>
var NONCE="$nonce";
var D=document, Wd=window;
var canvas=D.getElementById("c"), ctx=canvas.getContext("2d");
var W=0,H=0,DPR=Wd.devicePixelRatio||1;
function resize(){W=Wd.innerWidth;H=Wd.innerHeight;canvas.width=Math.floor(W*DPR);canvas.height=Math.floor(H*DPR);ctx.setTransform(DPR,0,0,DPR,0,0);dirty=true;}
Wd.addEventListener("resize",resize);

function send(type,extra){var m={type:type,nonce:NONCE};if(extra)for(var k in extra)m[k]=extra[k];parent.postMessage(m,"*");}
function hud(t){D.getElementById("hud").textContent=t||"";}
function showOver(t){D.getElementById("overmsg").textContent=t;D.getElementById("over").style.display="flex";}
function hideOver(){D.getElementById("over").style.display="none";}
function overWith(msg){showOver(msg);D.getElementById("again").onclick=function(){hideOver();sendAction({move:"rematch"});};}
function setButtons(defs){var pad=D.getElementById("pad");pad.innerHTML="";if(!defs||!defs.length){pad.style.display="none";return;}pad.style.display="flex";for(var i=0;i<defs.length;i++){(function(def){var b=D.createElement("button");b.textContent=def.label;b.onclick=def.cb;pad.appendChild(b);})(defs[i]);}}

var current=null, you=null, dirty=true, pending=false;
// Sends a move and locks input until the server's reply arrives, so a fast
// double-tap can't fire two moves.
function sendAction(a){if(pending)return;pending=true;send("action",{action:a});}
function ptXY(e){var r=canvas.getBoundingClientRect();return {x:(e.touches?e.touches[0].clientX:e.clientX)-r.left,y:(e.touches?e.touches[0].clientY:e.clientY)-r.top};}
function onDown(e){if(pending||!current||!current.pick)return;var p=ptXY(e);current.pick(p.x,p.y);dirty=true;}
function onMove(e){if(!current||!current.move)return;var p=ptXY(e);current.move(p.x,p.y);dirty=true;}
canvas.addEventListener("pointerdown",onDown);
canvas.addEventListener("pointermove",onMove);

function loop(){requestAnimationFrame(loop);if(!current)return;if(current.tick){current.tick();dirty=true;}if(dirty){ctx.clearRect(0,0,W,H);if(current.draw)current.draw();dirty=false;}}

Wd.addEventListener("message",function(e){var d=e.data;if(!d)return;
  if(d.type==="init")start(d.gameType,d.state||{});
  else if(d.type==="state"){pending=false;if(current&&current.onState)current.onState(d.state||{});dirty=true;}
  else if(d.type==="unlock"){pending=false;}});

function start(gameType,state){you=state.you;pending=false;if(current&&current.dispose)current.dispose();setButtons(null);hideOver();current=GAMES[gameType]?GAMES[gameType]():null;if(current&&current.build)current.build(state);dirty=true;}

// ----- shared drawing helpers -----
function rr(x,y,w,h,r){ctx.beginPath();ctx.moveTo(x+r,y);ctx.arcTo(x+w,y,x+w,y+h,r);ctx.arcTo(x+w,y+h,x,y+h,r);ctx.arcTo(x,y+h,x,y,r);ctx.arcTo(x,y,x+w,y,r);ctx.closePath();}
function sqName(sq){return String.fromCharCode(97+(sq%8))+(8-Math.floor(sq/8));}
function boardGeom(){var bs=Math.max(140,Math.min(W-16,H-150));var cs=bs/8;return {bs:bs,cs:cs,ox:(W-bs)/2,oy:Math.max(70,(H-bs)/2-10)};}
function sqAt(cx,cy,amWhite,g){var f=Math.floor((cx-g.ox)/g.cs),r=Math.floor((cy-g.oy)/g.cs);if(f<0||f>7||r<0||r>7)return -1;var dk=r*8+f;return amWhite?dk:63-dk;}
function sqXY(sq,amWhite,g){var dk=amWhite?sq:63-sq;return {x:g.ox+(dk%8)*g.cs,y:g.oy+Math.floor(dk/8)*g.cs};}
function drawCard(x,y,w,h,card,sel){
  if(card&&card.r!=="?"&&card.r!==undefined){
    ctx.fillStyle="#fff";rr(x,y,w,h,6);ctx.fill();
    ctx.lineWidth=sel?3:1;ctx.strokeStyle=sel?"#22c55e":"#cbd5e1";rr(x,y,w,h,6);ctx.stroke();
    var red=(card.s==="♥"||card.s==="♦");ctx.fillStyle=red?"#dc2626":"#0f172a";
    ctx.textAlign="left";ctx.textBaseline="top";ctx.font="bold "+Math.round(h*0.24)+"px sans-serif";ctx.fillText(card.r,x+5,y+5);
    ctx.textAlign="center";ctx.font=Math.round(h*0.42)+"px sans-serif";ctx.fillText(card.s,x+w/2,y+h*0.4);
  }else{ctx.fillStyle="#1e293b";rr(x,y,w,h,6);ctx.fill();ctx.lineWidth=2;ctx.strokeStyle="#475569";rr(x,y,w,h,6);ctx.stroke();}
}

var GAMES={};

// ===== Tic-tac-toe =====
GAMES.tictactoe=function(){
  var st=null;
  function status(){var m=st.x===you?"X":(st.o===you?"O":"");if(st.status==="draw")return "It is a draw";if(st.status==="won")return st.winner===you?"You won!":"You lost";if(st.turn==="cpu")return "Thinking...";if(m==="")return st.turn===st.x?"X to move":"O to move";return st.turn===you?("Your move ("+m+")"):"Their move";}
  function geom(){var bs=Math.max(150,Math.min(W-40,H-200));return {bs:bs,cs:bs/3,ox:(W-bs)/2,oy:Math.max(80,(H-bs)/2-10)};}
  return {
    build:function(s){st=s;},onState:function(s){st=s;},
    draw:function(){hud(status());var g=geom();ctx.fillStyle="#1e2d49";rr(g.ox,g.oy,g.bs,g.bs,10);ctx.fill();
      ctx.strokeStyle="#0b1220";ctx.lineWidth=4;for(var i=1;i<3;i++){ctx.beginPath();ctx.moveTo(g.ox+i*g.cs,g.oy);ctx.lineTo(g.ox+i*g.cs,g.oy+g.bs);ctx.moveTo(g.ox,g.oy+i*g.cs);ctx.lineTo(g.ox+g.bs,g.oy+i*g.cs);ctx.stroke();}
      for(var c=0;c<9;c++){var v=st.board[c];if(!v)continue;var x=g.ox+(c%3)*g.cs+g.cs/2,y=g.oy+Math.floor(c/3)*g.cs+g.cs/2;ctx.lineWidth=g.cs*0.12;if(v==="X"){ctx.strokeStyle="#38bdf8";var d=g.cs*0.27;ctx.beginPath();ctx.moveTo(x-d,y-d);ctx.lineTo(x+d,y+d);ctx.moveTo(x+d,y-d);ctx.lineTo(x-d,y+d);ctx.stroke();}else{ctx.strokeStyle="#f87171";ctx.beginPath();ctx.arc(x,y,g.cs*0.3,0,7);ctx.stroke();}}
      if(st.status==="won"||st.status==="draw")overWith(status());else hideOver();},
    pick:function(cx,cy){if(st.turn!==you||st.status!=="active")return;var g=geom();var f=Math.floor((cx-g.ox)/g.cs),r=Math.floor((cy-g.oy)/g.cs);if(f<0||f>2||r<0||r>2)return;var cell=r*3+f;if(st.board[cell])return;sendAction({cell:cell});}
  };
};

// ===== Chess =====
// Pieces are drawn as vector shapes (a Staunton-style set), NOT Unicode glyphs:
// iOS/Safari renders the chess characters as fixed-colour emoji that ignore
// fillStyle, so glyphs can't be recoloured. Each piece is built from simple
// parts, filled in the piece colour and outlined for contour detail.
function drawChessPiece(px,py,s,white,kind){
  var cx=px+s/2;
  function Y(f){return py+f*s;}
  var parts=[];
  function trap(yt,yb,ht,hb){parts.push(function(){ctx.moveTo(cx-ht*s,Y(yt));ctx.lineTo(cx+ht*s,Y(yt));ctx.lineTo(cx+hb*s,Y(yb));ctx.lineTo(cx-hb*s,Y(yb));ctx.closePath();});}
  function ball(xf,yf,rf){parts.push(function(){ctx.moveTo(cx+(xf+rf)*s,Y(yf));ctx.arc(cx+xf*s,Y(yf),rf*s,0,7);});}
  function bar(xf,yt,yb,hf){parts.push(function(){ctx.rect(cx+(xf-hf)*s,Y(yt),2*hf*s,(yb-yt)*s);});}
  function spike(xf,yb,yt,hf){parts.push(function(){ctx.moveTo(cx+(xf-hf)*s,Y(yb));ctx.lineTo(cx+xf*s,Y(yt));ctx.lineTo(cx+(xf+hf)*s,Y(yb));ctx.closePath();});}
  function poly(pts){parts.push(function(){ctx.moveTo(cx+pts[0][0]*s,Y(pts[0][1]));for(var i=1;i<pts.length;i++)ctx.lineTo(cx+pts[i][0]*s,Y(pts[i][1]));ctx.closePath();});}
  trap(0.82,0.88,0.30,0.24); trap(0.77,0.82,0.24,0.27);            // base + foot
  if(kind==="p"){
    trap(0.47,0.77,0.105,0.20); trap(0.43,0.47,0.15,0.105); ball(0,0.32,0.135);
  }else if(kind==="r"){
    trap(0.47,0.77,0.18,0.22); trap(0.39,0.47,0.25,0.18); trap(0.345,0.39,0.27,0.25);
    bar(-0.20,0.26,0.345,0.06); bar(0,0.26,0.345,0.06); bar(0.20,0.26,0.345,0.06);
  }else if(kind==="b"){
    trap(0.47,0.77,0.115,0.21); trap(0.43,0.47,0.17,0.115); ball(0,0.33,0.145);
    spike(0,0.30,0.13,0.05); ball(0,0.115,0.042);
  }else if(kind==="q"){
    trap(0.49,0.77,0.13,0.23); trap(0.43,0.49,0.22,0.13); trap(0.37,0.43,0.26,0.22);
    var qx=[-0.22,-0.11,0,0.11,0.22];
    for(var i=0;i<5;i++){spike(qx[i],0.37,0.21,0.045); ball(qx[i],0.19,0.04);}
  }else if(kind==="k"){
    trap(0.49,0.77,0.13,0.23); trap(0.43,0.49,0.22,0.13); trap(0.37,0.43,0.25,0.22);
    trap(0.31,0.37,0.18,0.25); bar(0,0.10,0.31,0.03); bar(0,0.145,0.205,0.085);
  }else if(kind==="n"){
    poly([[-0.20,0.78],[-0.16,0.52],[-0.24,0.44],[-0.30,0.405],[-0.265,0.335],
          [-0.15,0.35],[-0.12,0.22],[-0.03,0.13],[0.01,0.225],[0.07,0.155],
          [0.105,0.255],[0.20,0.34],[0.215,0.55],[0.23,0.78]]);
  }
  ctx.lineJoin="round"; ctx.lineCap="round";
  ctx.fillStyle=white?"#f8f6ef":"#46443f";
  ctx.shadowColor="rgba(0,0,0,0.28)"; ctx.shadowBlur=s*0.045; ctx.shadowOffsetY=s*0.025;
  for(var a=0;a<parts.length;a++){ctx.beginPath();parts[a]();ctx.fill();}
  ctx.shadowColor="transparent"; ctx.shadowBlur=0; ctx.shadowOffsetY=0;
  ctx.lineWidth=Math.max(1,s*0.026); ctx.strokeStyle=white?"#7a756b":"#1c1a17";
  for(var b2=0;b2<parts.length;b2++){ctx.beginPath();parts[b2]();ctx.stroke();}
  if(kind==="n"){ctx.beginPath();ctx.arc(cx-0.135*s,Y(0.31),s*0.022,0,7);ctx.fillStyle=white?"#7a756b":"#d2d8e0";ctx.fill();}
}
var CT={light:"#eeeed2",dark:"#769656",last:"rgba(245,222,82,0.55)",sel:"rgba(245,222,82,0.85)"};
GAMES.chess=function(){
  var st=null,amWhite=true,sel=null,prev=null,lastFrom=-1,lastTo=-1;
  function status(){if(st.status==="checkmate")return st.winner===you?"Checkmate — you win!":"Checkmate — you lost";if(st.status==="stalemate")return "Stalemate — draw";if(st.status==="draw")return "Draw";return (st.turn===you?"Your move":"Their move")+(st.inCheck?" · check!":"");}
  // Spot the last move by diffing the previous board (square emptied -> filled).
  function diffLast(nb){if(prev&&nb&&nb!==prev){var gone=-1,got=-1;for(var i=0;i<64;i++){if(prev[i]!==nb[i]){if(nb[i]===".")gone=i;else got=i;}}if(gone>=0&&got>=0){lastFrom=gone;lastTo=got;}}prev=nb;}
  function checkSq(){if(!st.inCheck)return -1;var k=(st.turn===st.white)?"K":"k";for(var i=0;i<64;i++)if(st.board[i]===k)return i;return -1;}
  function piece(p,c,g){drawChessPiece(p.x,p.y,g.cs,c===c.toUpperCase(),c.toLowerCase());}
  return {
    build:function(s){st=s;amWhite=(st.white===you);prev=s.board;lastFrom=lastTo=-1;},
    onState:function(s){diffLast(s.board);st=s;sel=null;},
    draw:function(){hud(status());var g=boardGeom();var chk=checkSq();
      ctx.save();ctx.shadowColor="rgba(0,0,0,0.35)";ctx.shadowBlur=14;ctx.shadowOffsetY=4;ctx.fillStyle="#262522";rr(g.ox-3,g.oy-3,g.bs+6,g.bs+6,6);ctx.fill();ctx.restore();
      for(var sq=0;sq<64;sq++){var p=sqXY(sq,amWhite,g);var f=sq%8,r=Math.floor(sq/8);var light=((f+r)%2===0);
        ctx.fillStyle=light?CT.light:CT.dark;ctx.fillRect(p.x,p.y,g.cs,g.cs);
        if(sq===lastFrom||sq===lastTo){ctx.fillStyle=CT.last;ctx.fillRect(p.x,p.y,g.cs,g.cs);}
        if(sq===sel){ctx.fillStyle=CT.sel;ctx.fillRect(p.x,p.y,g.cs,g.cs);}
        if(sq===chk){var rg=ctx.createRadialGradient(p.x+g.cs/2,p.y+g.cs/2,g.cs*0.1,p.x+g.cs/2,p.y+g.cs/2,g.cs*0.62);rg.addColorStop(0,"rgba(231,76,60,0.95)");rg.addColorStop(1,"rgba(231,76,60,0)");ctx.fillStyle=rg;ctx.fillRect(p.x,p.y,g.cs,g.cs);}
        var dk=amWhite?sq:63-sq,dcol=dk%8,drow=Math.floor(dk/8);ctx.font="700 "+Math.round(g.cs*0.2)+"px sans-serif";ctx.fillStyle=light?CT.dark:CT.light;
        if(dcol===0){ctx.textAlign="left";ctx.textBaseline="top";ctx.fillText(String(8-r),p.x+3,p.y+3);}
        if(drow===7){ctx.textAlign="right";ctx.textBaseline="bottom";ctx.fillText(String.fromCharCode(97+f),p.x+g.cs-3,p.y+g.cs-2);}
        var c=st.board[sq];if(c!==".")piece(p,c,g);}
      if(st.status==="checkmate"||st.status==="stalemate"||st.status==="draw")overWith(status());else hideOver();},
    pick:function(cx,cy){if(st.turn!==you||st.status!=="active")return;var g=boardGeom();var sq=sqAt(cx,cy,amWhite,g);if(sq<0)return;var pc=st.board[sq],mine=pc!=="."&&(amWhite?pc===pc.toUpperCase():pc===pc.toLowerCase());if(sel===null){if(mine)sel=sq;return;}if(sq===sel){sel=null;return;}if(mine){sel=sq;return;}var from=sqName(sel),to=sqName(sq);sel=null;sendAction({from:from,to:to});}
  };
};

// ===== Checkers =====
GAMES.checkers=function(){
  var st=null,amWhite=true,sel=null;
  function status(){if(st.status!=="active")return st.winner===you?"You win!":"You lost";return st.turn===you?"Your move":"Their move";}
  return {
    build:function(s){st=s;amWhite=(st.white===you);},
    onState:function(s){st=s;sel=(st.turn===you&&st.chain!==null&&st.chain!==undefined)?st.chain:null;},
    draw:function(){hud(status());var g=boardGeom();
      for(var sq=0;sq<64;sq++){var p=sqXY(sq,amWhite,g);var f=sq%8,r=Math.floor(sq/8);var dark=((f+r)%2===1);
        ctx.fillStyle=(sel===sq)?"#86efac":(dark?"#8d6748":"#ead9bd");ctx.fillRect(p.x,p.y,g.cs,g.cs);
        var c=st.board[sq];if(c!=="."){var white=(c==="w"||c==="W"),king=(c==="W"||c==="B");ctx.beginPath();ctx.arc(p.x+g.cs/2,p.y+g.cs/2,g.cs*0.36,0,7);ctx.fillStyle=white?"#f1f5f9":"#1f2937";ctx.fill();ctx.lineWidth=2;ctx.strokeStyle="#0008";ctx.stroke();if(king){ctx.beginPath();ctx.arc(p.x+g.cs/2,p.y+g.cs/2,g.cs*0.16,0,7);ctx.fillStyle="#f6c455";ctx.fill();}}}
      if(st.status!=="active")overWith(status());else hideOver();},
    pick:function(cx,cy){if(st.turn!==you||st.status!=="active")return;var g=boardGeom();var sq=sqAt(cx,cy,amWhite,g);if(sq<0)return;var p=st.board[sq],mine=amWhite?(p==="w"||p==="W"):(p==="b"||p==="B");if(sel===null){if(mine)sel=sq;return;}if(sq===sel){sel=null;return;}if(mine){sel=sq;return;}var from=sel;sel=null;sendAction({from:from,to:sq});}
  };
};

// ===== Connect Four =====
GAMES.connect4=function(){
  var st=null,hoverCol=-1;
  function status(){if(st.status==="won")return st.winner===you?"You won!":"You lost";if(st.status==="draw")return "It is a draw";if(st.turn==="cpu")return "Thinking...";return st.turn===you?"Your move":"Their move";}
  function geom(){var cs=Math.max(26,Math.min((W-24)/7,(H-170)/6));var bw=cs*7,bh=cs*6;return {cs:cs,bw:bw,bh:bh,ox:(W-bw)/2,oy:Math.max(64,(H-bh)/2-6)};}
  function colAt(cx,g){var c=Math.floor((cx-g.ox)/g.cs);return (c<0||c>6)?-1:c;}
  return {
    build:function(s){st=s;},onState:function(s){st=s;hoverCol=-1;},
    draw:function(){hud(status());var g=geom();
      var mine=(st.turn===you&&st.status==="active");
      if(mine&&hoverCol>=0&&st.board[hoverCol]==="."){ctx.fillStyle="#1e3a8a";ctx.fillRect(g.ox+hoverCol*g.cs,g.oy,g.cs,g.bh);}
      ctx.fillStyle="#1d4ed8";rr(g.ox,g.oy,g.bw,g.bh,12);ctx.fill();
      for(var i=0;i<42;i++){var c=i%7,r=Math.floor(i/7);var x=g.ox+c*g.cs+g.cs/2,y=g.oy+r*g.cs+g.cs/2;var v=st.board[i];ctx.beginPath();ctx.arc(x,y,g.cs*0.38,0,7);ctx.fillStyle=(v==="R")?"#ef4444":(v==="Y")?"#facc15":"#0b1220";ctx.fill();if(v!=="."){ctx.lineWidth=2;ctx.strokeStyle="#0006";ctx.stroke();}}
      if(st.status!=="active")overWith(status());else hideOver();},
    move:function(cx,cy){var g=geom();hoverCol=colAt(cx,g);},
    pick:function(cx,cy){if(st.turn!==you||st.status!=="active")return;var g=geom();var c=colAt(cx,g);if(c<0)return;if(st.board[c]!==".")return;sendAction({col:c});}
  };
};

// ===== Dots and Boxes =====
GAMES.dotsboxes=function(){
  var st=null,dots=4,hover=null;
  function myScore(){return st.red===you?st.redScore:st.yellowScore;}
  function oppScore(){return st.red===you?st.yellowScore:st.redScore;}
  function status(){var sc=" ("+myScore()+"-"+oppScore()+")";if(st.status==="won")return (st.winner===you?"You won!":"You lost")+sc;if(st.status==="draw")return "Draw"+sc;if(st.turn==="cpu")return "Thinking..."+sc;return (st.turn===you?"Your move":"Their move")+sc;}
  function geom(){var n=dots-1;var cell=Math.max(40,Math.min((W-64)/n,(H-200)/n));var bw=n*cell;return {cell:cell,bw:bw,n:n,ox:(W-bw)/2,oy:Math.max(80,(H-bw)/2-10)};}
  function hEnds(g,row,col){return [g.ox+col*g.cell,g.oy+row*g.cell,g.ox+(col+1)*g.cell,g.oy+row*g.cell];}
  function vEnds(g,row,col){return [g.ox+col*g.cell,g.oy+row*g.cell,g.ox+col*g.cell,g.oy+(row+1)*g.cell];}
  function distSeg(px,py,x1,y1,x2,y2){var dx=x2-x1,dy=y2-y1,l2=dx*dx+dy*dy;var t=l2?((px-x1)*dx+(py-y1)*dy)/l2:0;t=Math.max(0,Math.min(1,t));return Math.hypot(px-(x1+t*dx),py-(y1+t*dy));}
  function nearest(cx,cy){var g=geom();var best=null,bd=g.cell*0.45;
    for(var i=0;i<st.h.length;i++){if(st.h[i]==="1")continue;var e=hEnds(g,Math.floor(i/g.n),i%g.n);var d=distSeg(cx,cy,e[0],e[1],e[2],e[3]);if(d<bd){bd=d;best={kind:"h",idx:i};}}
    for(var j=0;j<st.v.length;j++){if(st.v[j]==="1")continue;var ev=vEnds(g,Math.floor(j/dots),j%dots);var dv=distSeg(cx,cy,ev[0],ev[1],ev[2],ev[3]);if(dv<bd){bd=dv;best={kind:"v",idx:j};}}
    return best;}
  function line(e,col,w){ctx.strokeStyle=col;ctx.lineWidth=w;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(e[0],e[1]);ctx.lineTo(e[2],e[3]);ctx.stroke();}
  return {
    build:function(s){st=s;dots=s.dots||4;},onState:function(s){st=s;dots=s.dots||4;hover=null;},
    draw:function(){hud(status());var g=geom();
      for(var b=0;b<st.owner.length;b++){var o=st.owner[b];if(o===".")continue;var br=Math.floor(b/g.n),bc=b%g.n;ctx.fillStyle=(o==="R")?"rgba(239,68,68,0.32)":"rgba(250,204,21,0.32)";ctx.fillRect(g.ox+bc*g.cell+g.cell*0.07,g.oy+br*g.cell+g.cell*0.07,g.cell*0.86,g.cell*0.86);}
      for(var i=0;i<st.h.length;i++){var dn=st.h[i]==="1";line(hEnds(g,Math.floor(i/g.n),i%g.n),dn?"#e2e8f0":"#28344d",dn?g.cell*0.085:2);}
      for(var j=0;j<st.v.length;j++){var dv2=st.v[j]==="1";line(vEnds(g,Math.floor(j/dots),j%dots),dv2?"#e2e8f0":"#28344d",dv2?g.cell*0.085:2);}
      if(hover&&st.turn===you&&st.status==="active"){var ee=hover.kind==="h"?hEnds(g,Math.floor(hover.idx/g.n),hover.idx%g.n):vEnds(g,Math.floor(hover.idx/dots),hover.idx%dots);line(ee,"#38bdf8",g.cell*0.085);}
      for(var r=0;r<dots;r++)for(var c=0;c<dots;c++){ctx.beginPath();ctx.arc(g.ox+c*g.cell,g.oy+r*g.cell,Math.max(3,g.cell*0.07),0,7);ctx.fillStyle="#f8fafc";ctx.fill();}
      if(st.status!=="active")overWith(status());else hideOver();},
    move:function(cx,cy){if(st.turn!==you||st.status!=="active"){hover=null;return;}hover=nearest(cx,cy);},
    pick:function(cx,cy){if(st.turn!==you||st.status!=="active")return;var e=nearest(cx,cy);if(e)sendAction(e);}
  };
};

// ===== Blackjack =====
GAMES.blackjack=function(){
  var st=null;
  function result(s){return s==="blackjack"?"Blackjack! You win":s==="win"?"You win":s==="lose"?"Dealer wins":s==="push"?"Push — tie":"";}
  function row(cards,cy){var cw=Math.min(70,(W-40)/Math.max(cards.length,2)-8),ch=cw*1.4;var tot=cards.length*(cw+8)-8;var x0=(W-tot)/2;for(var i=0;i<cards.length;i++)drawCard(x0+i*(cw+8),cy,cw,ch,cards[i],false);}
  function refresh(){var over=(st.status!=="active");if(over){overWith(result(st.status));setButtons(null);}else{hideOver();if(st.mine)setButtons([{label:"Hit",cb:function(){hud("...");setButtons(null);sendAction({move:"hit"});}},{label:"Stand",cb:function(){hud("...");setButtons(null);sendAction({move:"stand"});}}]);else setButtons(null);}}
  return {
    build:function(s){st=s;refresh();},onState:function(s){st=s;refresh();},
    draw:function(){var over=(st.status!=="active");hud("Dealer "+(over?st.dealerTotal:"?")+"   ·   You "+st.playerTotal);
      ctx.fillStyle="#0b3b24";ctx.fillRect(0,0,W,H);ctx.fillStyle="#9fb3a8";ctx.font="14px sans-serif";ctx.textAlign="left";ctx.textBaseline="alphabetic";ctx.fillText("Dealer",16,H*0.22-10);ctx.fillText("You",16,H*0.55-10);
      row(st.dealer,H*0.22);row(st.player,H*0.55);}
  };
};

// ===== Poker =====
GAMES.poker=function(){
  var st=null,holds={};
  function result(s){return s==="win"?"You win":s==="lose"?"Dealer wins":s==="push"?"Split — tie":"";}
  var lay=null;
  function refresh(){var over=(st.status==="win"||st.status==="lose"||st.status==="push");if(over){overWith(result(st.status));setButtons(null);}else if(st.status==="active"&&st.mine){hideOver();setButtons([{label:"Draw",cb:function(){var h=[];for(var k in holds)if(holds[k])h.push(parseInt(k,10));hud("Dealing...");setButtons(null);sendAction({move:"draw",holds:h});}}]);}else setButtons(null);}
  function row(cards,cy,tappable){var cw=Math.min(64,(W-30)/5-8),ch=cw*1.4;var tot=cards.length*(cw+8)-8;var x0=(W-tot)/2;var r=[];for(var i=0;i<cards.length;i++){var x=x0+i*(cw+8),y=tappable&&holds[i]?cy-14:cy;drawCard(x,y,cw,ch,cards[i],tappable&&holds[i]);r.push({x:x,y:cy,w:cw,h:ch,i:i});}return r;}
  return {
    build:function(s){st=s;refresh();},onState:function(s){st=s;refresh();},
    draw:function(){ctx.fillStyle="#0b3b24";ctx.fillRect(0,0,W,H);
      hud("You: "+st.yourHand+(st.opponentHand?("   ·   Dealer: "+st.opponentHand):""));
      ctx.fillStyle="#9fb3a8";ctx.font="14px sans-serif";ctx.textAlign="left";ctx.textBaseline="alphabetic";ctx.fillText("Dealer",16,H*0.24-10);ctx.fillText("You",16,H*0.58-10);
      row(st.opponent,H*0.24,false);lay=row(st.you,H*0.58,st.status==="active"&&st.mine);},
    pick:function(cx,cy){if(!lay||st.status!=="active"||!st.mine)return;for(var i=0;i<lay.length;i++){var c=lay[i];if(cx>=c.x&&cx<=c.x+c.w&&cy>=c.y-20&&cy<=c.y+c.h){holds[c.i]=!holds[c.i];return;}}}
  };
};

// ===== Pong (arcade, self-contained) =====
GAMES.pong=function(){
  var pw,px,cx,bx,by,vx,vy,ps=0,cs=0,over=false,R=8,spk=1,cpk=0.013,predict=true;
  function reset(toP){bx=W/2;by=H/2;var sp=Math.max(4.5,H*0.007)*spk;vx=(Math.random()<0.5?1:-1)*sp*0.55;vy=toP?sp:-sp;}
  // Anticipate where the ball will cross the CPU's line (reflecting off walls).
  function predictX(){if(vy>=0||!predict)return bx;var t=(by-22)/(-vy);var x=bx+vx*t;var span=W-2*R;if(span<=0)return bx;x=(((x-R)%(2*span))+2*span)%(2*span);if(x>span)x=2*span-x;return x+R;}
  function setPX(clientX){var r=canvas.getBoundingClientRect();px=Math.max(pw/2,Math.min(W-pw/2,clientX-r.left));}
  function pm(e){setPX(e.clientX);}function tm(e){if(e.touches[0])setPX(e.touches[0].clientX);e.preventDefault();}
  function end(){over=true;showOver((ps>cs)?"You win!":"CPU wins");send("score",{score:ps});}
  D.getElementById("again").onclick=function(){ps=0;cs=0;over=false;reset(true);hideOver();};
  return {
    build:function(s){var d=(s&&s.difficulty)||"medium";spk=d==="easy"?0.8:d==="hard"?1.3:1.0;cpk=d==="easy"?0.009:d==="hard"?0.022:0.014;predict=d!=="easy";pw=Math.min(130,W*0.32);px=W/2;cx=W/2;reset(true);hud("You 0 — CPU 0");canvas.addEventListener("pointermove",pm);canvas.addEventListener("touchmove",tm,{passive:false});},
    tick:function(){if(over)return;var tgt=predictX();cx+=Math.max(-W*cpk,Math.min(W*cpk,tgt-cx));bx+=vx;by+=vy;
      if(bx<R){bx=R;vx=Math.abs(vx);}if(bx>W-R){bx=W-R;vx=-Math.abs(vx);}
      if(by>H-22){if(Math.abs(bx-px)<pw/2){by=H-22;vy=-Math.abs(vy);vx+=(bx-px)*0.03;}else{cs++;if(cs>=7)end();else reset(false);}hud("You "+ps+" — CPU "+cs);}
      if(by<22){if(Math.abs(bx-cx)<pw/2){by=22;vy=Math.abs(vy);}else{ps++;if(ps>=7)end();else reset(true);}hud("You "+ps+" — CPU "+cs);}},
    draw:function(){ctx.fillStyle="#0b1220";ctx.fillRect(0,0,W,H);ctx.strokeStyle="#334155";ctx.lineWidth=2;ctx.setLineDash([8,8]);ctx.beginPath();ctx.moveTo(0,H/2);ctx.lineTo(W,H/2);ctx.stroke();ctx.setLineDash([]);
      ctx.fillStyle="#f87171";rr(cx-pw/2,8,pw,11,5);ctx.fill();ctx.fillStyle="#38bdf8";rr(px-pw/2,H-19,pw,11,5);ctx.fill();
      ctx.fillStyle="#fff";ctx.beginPath();ctx.arc(bx,by,R,0,7);ctx.fill();},
    dispose:function(){canvas.removeEventListener("pointermove",pm);canvas.removeEventListener("touchmove",tm);}
  };
};

// ===== Snake (arcade, self-contained) =====
GAMES.snake=function(){
  var N=17,snake,dir,nd,food,score,dead,acc,stepN=10;
  function geom(){var s=Math.max(150,Math.min(W-16,H-150));return {cs:s/N,ox:(W-s)/2,oy:Math.max(70,(H-s)/2-10)};}
  function spawn(){while(true){var p={x:Math.floor(Math.random()*N),y:Math.floor(Math.random()*N)};var on=false;for(var i=0;i<snake.length;i++)if(snake[i].x===p.x&&snake[i].y===p.y)on=true;if(!on){food=p;return;}}}
  function steer(x,y){if(x===-dir.x&&y===-dir.y)return;nd={x:x,y:y};}
  function step(){dir=nd;var h={x:snake[0].x+dir.x,y:snake[0].y+dir.y};if(h.x<0||h.y<0||h.x>=N||h.y>=N){return die();}for(var i=0;i<snake.length;i++)if(snake[i].x===h.x&&snake[i].y===h.y)return die();snake.unshift(h);if(h.x===food.x&&h.y===food.y){score++;hud("Score: "+score);spawn();}else snake.pop();}
  function die(){dead=true;showOver("Game over · "+score);send("score",{score:score});}
  function key(e){var k=e.key;if(k==="ArrowUp")steer(0,-1);else if(k==="ArrowDown")steer(0,1);else if(k==="ArrowLeft")steer(-1,0);else if(k==="ArrowRight")steer(1,0);}
  function start2(){snake=[{x:8,y:8},{x:7,y:8},{x:6,y:8}];dir={x:1,y:0};nd={x:1,y:0};score=0;dead=false;acc=0;spawn();hud("Score: 0  ·  tap to steer");}
  D.getElementById("again").onclick=function(){start2();hideOver();};
  return {
    build:function(s){var d=(s&&s.difficulty)||"medium";stepN=d==="easy"?14:d==="hard"?6:10;start2();Wd.addEventListener("keydown",key);},
    // Tap (or click) anywhere: turn toward the tap relative to the head. Works
    // on every platform, unlike arrow keys (need iframe focus) or swipes.
    pick:function(cx,cy){if(dead)return;var g=geom();var hx=g.ox+(snake[0].x+0.5)*g.cs,hy=g.oy+(snake[0].y+0.5)*g.cs;var dx=cx-hx,dy=cy-hy;if(Math.abs(dx)>Math.abs(dy))steer(dx>0?1:-1,0);else steer(0,dy>0?1:-1);},
    tick:function(){if(dead)return;acc++;if(acc>=stepN){acc=0;step();}},
    draw:function(){var g=geom();ctx.fillStyle="#0b1626";ctx.fillRect(g.ox,g.oy,g.cs*N,g.cs*N);
      ctx.fillStyle="#ef4444";ctx.fillRect(g.ox+food.x*g.cs+1,g.oy+food.y*g.cs+1,g.cs-2,g.cs-2);
      for(var i=0;i<snake.length;i++){ctx.fillStyle=i===0?"#4ade80":"#22c55e";ctx.fillRect(g.ox+snake[i].x*g.cs+1,g.oy+snake[i].y*g.cs+1,g.cs-2,g.cs-2);}},
    dispose:function(){Wd.removeEventListener("keydown",key);}
  };
};

resize();send("ready");loop();
</script></body></html>
''';
