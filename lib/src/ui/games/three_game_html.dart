/// The self-contained HTML + Three.js for the in-app games, parameterised only
/// by a message [nonce]. Everything else (game type, board state, the current
/// user) arrives over postMessage from Flutter, and moves/scores go back the
/// same way. Kept JS-template-literal- and `$`-free so it embeds cleanly in a
/// Dart string.
String threeGameHtml(String nonce) => '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  html,body{margin:0;height:100%;overflow:hidden;background:#0b1220;font-family:sans-serif;}
  #c{display:block;width:100%;height:100%;touch-action:none;}
  #hud{position:absolute;top:10px;left:0;right:0;text-align:center;color:#fff;font-weight:700;font-size:17px;pointer-events:none;text-shadow:0 1px 3px #000;}
  #over{position:absolute;inset:0;display:none;flex-direction:column;align-items:center;justify-content:center;color:#fff;background:rgba(0,0,0,.55);}
  #over .msg{font-size:22px;font-weight:700;margin-bottom:12px;}
  #over button,#pad button{border:0;border-radius:10px;background:#2563eb;color:#fff;font-weight:700;font-size:16px;padding:10px 20px;}
  #pad{position:absolute;bottom:14px;left:0;right:0;display:none;justify-content:center;gap:10px;}
  #pad button{padding:12px 16px;background:#1e293b;}
</style></head><body>
<div id="hud"></div>
<canvas id="c"></canvas>
<div id="pad"></div>
<div id="over"><div class="msg" id="overmsg"></div><button id="again">Play again</button></div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script>
var NONCE="$nonce";
var D=document, Wd=window;
function send(type,extra){var m={type:type,nonce:NONCE};if(extra)for(var k in extra)m[k]=extra[k];parent.postMessage(m,"*");}
function hud(t){D.getElementById("hud").textContent=t||"";}
function showOver(t){D.getElementById("overmsg").textContent=t;D.getElementById("over").style.display="flex";}
function hideOver(){D.getElementById("over").style.display="none";}

var renderer,scene,camera,raycaster,pointer,current=null,you=null,pickables=[];
function setup3D(bg){
  var canvas=D.getElementById("c");
  if(!renderer){renderer=new THREE.WebGLRenderer({canvas:canvas,antialias:true});}
  scene=new THREE.Scene(); scene.background=new THREE.Color(bg||0x0b1220);
  camera=new THREE.PerspectiveCamera(50,1,0.1,200);
  raycaster=new THREE.Raycaster(); pointer=new THREE.Vector2();
  scene.add(new THREE.AmbientLight(0xffffff,0.7));
  var dl=new THREE.DirectionalLight(0xffffff,0.8); dl.position.set(6,14,8); scene.add(dl);
  resize();
}
function resize(){if(!renderer)return;var w=Wd.innerWidth,h=Wd.innerHeight;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();}
Wd.addEventListener("resize",resize);

function onPointerDown(e){
  if(!current||!current.pick||!camera)return;
  var r=renderer.domElement.getBoundingClientRect();
  var cx=(e.touches?e.touches[0].clientX:e.clientX);
  var cy=(e.touches?e.touches[0].clientY:e.clientY);
  pointer.x=((cx-r.left)/r.width)*2-1; pointer.y=-((cy-r.top)/r.height)*2+1;
  raycaster.setFromCamera(pointer,camera);
  var hits=raycaster.intersectObjects(pickables,false);
  if(hits.length)current.pick(hits[0].object.userData);
}
D.getElementById("c").addEventListener("pointerdown",onPointerDown);

function animate(){requestAnimationFrame(animate);if(current&&current.tick)current.tick();if(renderer&&scene&&camera)renderer.render(scene,camera);}

Wd.addEventListener("message",function(e){
  var d=e.data; if(!d)return;
  if(d.type==="init"){ start(d.gameType,d.state||{}); }
  else if(d.type==="state"){ if(current&&current.onState)current.onState(d.state||{}); }
});

function start(gameType,state){
  you=state.you;
  if(current&&current.dispose)current.dispose();
  pickables=[];
  current=GAMES[gameType]?GAMES[gameType]():null;
  if(current){ if(current.bg!==undefined)setup3D(current.bg); else setup3D(); current.build(state); }
}

// ===== shared helpers =====
function textTexture(text,fg,bg){
  var s=128,cv=D.createElement("canvas");cv.width=s;cv.height=s;var x=cv.getContext("2d");
  if(bg){x.fillStyle=bg;x.fillRect(0,0,s,s);}
  x.fillStyle=fg;x.font="bold 84px sans-serif";x.textAlign="center";x.textBaseline="middle";
  x.fillText(text,s/2,s/2+4);
  var t=new THREE.CanvasTexture(cv);return t;
}

var GAMES={};

// ===== Pong (3D, self-contained arcade vs CPU) =====
GAMES.pong=function(){
  var Wp=10,Dp=14,ball,pl,cpu,bx=0,bz=0,vx=0.06,vz=0.11,ps=0,cs=0,over=false;
  function paddle(c){return new THREE.Mesh(new THREE.BoxGeometry(2.6,0.5,0.45),new THREE.MeshStandardMaterial({color:c}));}
  function reset(toP){bx=0;bz=0;vx=(Math.random()<0.5?0.06:-0.06);vz=toP?0.11:-0.11;}
  function setPX(cx){var r=renderer.domElement.getBoundingClientRect();var nx=(cx-r.left)/r.width;pl.position.x=Math.max(-Wp/2+1.3,Math.min(Wp/2-1.3,(nx-0.5)*Wp));}
  function pm(e){setPX(e.clientX);}
  function tm(e){if(e.touches[0])setPX(e.touches[0].clientX);e.preventDefault();}
  function ui(){hud("You "+ps+" — CPU "+cs);}
  function endGame(){over=true;showOver((ps>cs)?"You win!":"CPU wins");send("score",{score:ps});}
  D.getElementById("again").onclick=function(){ps=0;cs=0;over=false;reset(true);ui();hideOver();};
  return {
    bg:0x0b1220,
    build:function(){
      camera.position.set(0,12,12);camera.lookAt(0,0,0);
      var table=new THREE.Mesh(new THREE.BoxGeometry(Wp,0.5,Dp),new THREE.MeshStandardMaterial({color:0x14223b}));table.position.y=-0.35;scene.add(table);
      var line=new THREE.Mesh(new THREE.BoxGeometry(Wp,0.07,0.12),new THREE.MeshBasicMaterial({color:0x335577}));line.position.y=0.02;scene.add(line);
      ball=new THREE.Mesh(new THREE.SphereGeometry(0.35,18,18),new THREE.MeshStandardMaterial({color:0xffffff}));scene.add(ball);
      pl=paddle(0x38bdf8);pl.position.set(0,0,Dp/2-0.6);scene.add(pl);
      cpu=paddle(0xf87171);cpu.position.set(0,0,-Dp/2+0.6);scene.add(cpu);
      reset(true);ui();
      var cv=renderer.domElement;cv.addEventListener("pointermove",pm);cv.addEventListener("touchmove",tm,{passive:false});
    },
    tick:function(){
      if(over)return;
      cpu.position.x+=Math.max(-0.075,Math.min(0.075,bx-cpu.position.x));
      bx+=vx;bz+=vz;
      if(bx<-Wp/2+0.35){bx=-Wp/2+0.35;vx=Math.abs(vx);}
      if(bx>Wp/2-0.35){bx=Wp/2-0.35;vx=-Math.abs(vx);}
      if(bz>Dp/2-1.0){if(Math.abs(bx-pl.position.x)<1.5){vz=-Math.abs(vz);vx+=(bx-pl.position.x)*0.01;}else{cs++;if(cs>=7){ui();endGame();}else{reset(false);ui();}}}
      if(bz<-Dp/2+1.0){if(Math.abs(bx-cpu.position.x)<1.5){vz=Math.abs(vz);}else{ps++;if(ps>=7){ui();endGame();}else{reset(true);ui();}}}
      ball.position.set(bx,0,bz);
    },
    dispose:function(){var cv=renderer.domElement;cv.removeEventListener("pointermove",pm);cv.removeEventListener("touchmove",tm);}
  };
};

// ===== Snake (3D, self-contained arcade) =====
GAMES.snake=function(){
  var N=15,cell=1,half=(N*cell)/2;
  var snake=[{x:7,y:7},{x:6,y:7},{x:5,y:7}],dir={x:1,y:0},nextDir={x:1,y:0},food={x:10,y:7},score=0,dead=false,acc=0,group=null,foodMesh=null;
  function pos(gx,gy){return new THREE.Vector3(gx-half+0.5,0.5,gy-half+0.5);}
  function cube(c){return new THREE.Mesh(new THREE.BoxGeometry(0.9,0.9,0.9),new THREE.MeshStandardMaterial({color:c}));}
  function spawnFood(){while(true){var p={x:Math.floor(Math.random()*N),y:Math.floor(Math.random()*N)};var on=false;for(var i=0;i<snake.length;i++)if(snake[i].x===p.x&&snake[i].y===p.y)on=true;if(!on){food=p;return;}}}
  function steer(x,y){if(x===-dir.x&&y===-dir.y)return;nextDir={x:x,y:y};}
  function render(){
    if(group)scene.remove(group);group=new THREE.Group();
    var floor=new THREE.Mesh(new THREE.BoxGeometry(N,0.3,N),new THREE.MeshStandardMaterial({color:0x0b1626}));floor.position.y=-0.05;group.add(floor);
    for(var i=0;i<snake.length;i++){var m=cube(i===0?0x4ade80:0x22c55e);m.position.copy(pos(snake[i].x,snake[i].y));group.add(m);}
    foodMesh=cube(0xef4444);foodMesh.position.copy(pos(food.x,food.y));group.add(foodMesh);
    scene.add(group);
  }
  function step(){
    dir=nextDir;var nh={x:snake[0].x+dir.x,y:snake[0].y+dir.y};
    if(nh.x<0||nh.y<0||nh.x>=N||nh.y>=N){return die();}
    for(var i=0;i<snake.length;i++)if(snake[i].x===nh.x&&snake[i].y===nh.y)return die();
    snake.unshift(nh);
    if(nh.x===food.x&&nh.y===food.y){score++;hud("Score: "+score);spawnFood();}else{snake.pop();}
    render();
  }
  function die(){dead=true;showOver("Game over · "+score);send("score",{score:score});}
  // keyboard + swipe
  function key(e){var k=e.key;if(k==="ArrowUp")steer(0,-1);else if(k==="ArrowDown")steer(0,1);else if(k==="ArrowLeft")steer(-1,0);else if(k==="ArrowRight")steer(1,0);}
  Wd.addEventListener("keydown",key);
  var sx=0,sy=0;
  function ts(e){sx=e.touches[0].clientX;sy=e.touches[0].clientY;}
  function te(e){var dx=e.changedTouches[0].clientX-sx,dy=e.changedTouches[0].clientY-sy;if(Math.abs(dx)>Math.abs(dy))steer(dx>0?1:-1,0);else steer(0,dy>0?1:-1);}
  var cv=D.getElementById("c");cv.addEventListener("touchstart",ts);cv.addEventListener("touchend",te);
  D.getElementById("again").onclick=function(){snake=[{x:7,y:7},{x:6,y:7},{x:5,y:7}];dir={x:1,y:0};nextDir={x:1,y:0};score=0;dead=false;spawnFood();hideOver();hud("Score: 0");render();};
  return {
    bg:0x0b1220,
    build:function(){camera.position.set(0,16,13);camera.lookAt(0,0,0);hud("Score: 0");spawnFood();render();},
    tick:function(){if(dead)return;acc++;if(acc>=11){acc=0;step();}},
    dispose:function(){Wd.removeEventListener("keydown",key);}
  };
};

// ===== Tic-tac-toe (3D, backend-bridged) =====
GAMES.tictactoe=function(){
  var st=null,tiles=[],marks=[];
  function status(){
    if(!st)return "";
    var myMark=st.x===you?"X":(st.o===you?"O":"");
    if(st.status==="draw")return "It is a draw";
    if(st.status==="won")return (st.winner===you)?"You won!":"You lost";
    if(st.turn==="cpu")return "Thinking...";
    if(myMark==="")return st.turn===st.x?"X to move":"O to move";
    return st.turn===you?("Your move ("+myMark+")"):"Their move";
  }
  function drawMarks(){
    for(var i=0;i<marks.length;i++)scene.remove(marks[i]);marks=[];
    if(!st)return;
    for(var i=0;i<9;i++){
      var v=st.board[i];if(!v)continue;
      var gx=(i%3-1)*2.1, gz=(Math.floor(i/3)-1)*2.1, m;
      if(v==="X"){m=new THREE.Group();var a=new THREE.Mesh(new THREE.BoxGeometry(1.5,0.3,0.3),new THREE.MeshStandardMaterial({color:0x38bdf8}));var b=a.clone();a.rotation.y=Math.PI/4;b.rotation.y=-Math.PI/4;m.add(a);m.add(b);}
      else{m=new THREE.Mesh(new THREE.TorusGeometry(0.7,0.22,16,32),new THREE.MeshStandardMaterial({color:0xf87171}));m.rotation.x=Math.PI/2;}
      m.position.set(gx,0.5,gz);scene.add(m);marks.push(m);
    }
  }
  return {
    bg:0x0b1220,
    build:function(state){
      st=state;camera.position.set(0,8,7);camera.lookAt(0,0,0);
      var base=new THREE.Mesh(new THREE.BoxGeometry(6.6,0.2,6.6),new THREE.MeshStandardMaterial({color:0x14223b}));scene.add(base);
      for(var i=0;i<9;i++){
        var gx=(i%3-1)*2.1, gz=(Math.floor(i/3)-1)*2.1;
        var tile=new THREE.Mesh(new THREE.BoxGeometry(1.9,0.2,1.9),new THREE.MeshStandardMaterial({color:0x1e2d49}));
        tile.position.set(gx,0.15,gz);tile.userData={cell:i};scene.add(tile);tiles.push(tile);pickables.push(tile);
      }
      drawMarks();hud(status());
    },
    onState:function(state){st=state;drawMarks();hud(status());},
    pick:function(ud){if(ud.cell===undefined||!st)return;if(st.board[ud.cell])return;if(st.turn!==you)return;send("action",{action:{cell:ud.cell}});hud("...");}
  };
};

// ===== shared 3D helpers for the board/card games =====
function setButtons(defs){
  var pad=D.getElementById("pad");pad.innerHTML="";
  if(!defs||!defs.length){pad.style.display="none";return;}
  pad.style.display="flex";
  for(var i=0;i<defs.length;i++){(function(def){var b=D.createElement("button");b.textContent=def.label;b.onclick=def.cb;pad.appendChild(b);})(defs[i]);}
}
function dispPos(sq,amWhite){var k=amWhite?sq:63-sq;return {x:(k%8)-3.5,z:Math.floor(k/8)-3.5};}
function buildBoard(amWhite,lightC,darkC){
  var tiles=[];
  for(var sq=0;sq<64;sq++){
    var f=sq%8,r=Math.floor(sq/8),light=((f+r)%2===0),p=dispPos(sq,amWhite);
    var t=new THREE.Mesh(new THREE.BoxGeometry(0.96,0.2,0.96),new THREE.MeshStandardMaterial({color:light?lightC:darkC}));
    t.position.set(p.x,0,p.z);t.userData={sq:sq};scene.add(t);pickables.push(t);tiles.push(t);
  }
  return tiles;
}
function sqName(sq){return String.fromCharCode(97+(sq%8))+(8-Math.floor(sq/8));}
function glyphSprite(ch,color){
  var cv=D.createElement("canvas");cv.width=128;cv.height=128;var x=cv.getContext("2d");
  x.fillStyle=color;x.font="104px serif";x.textAlign="center";x.textBaseline="middle";x.fillText(ch,64,72);
  var sp=new THREE.Sprite(new THREE.SpriteMaterial({map:new THREE.CanvasTexture(cv),transparent:true}));
  sp.scale.set(1.05,1.05,1.05);return sp;
}
function cardMesh(card){
  var cv=D.createElement("canvas");cv.width=128;cv.height=180;var x=cv.getContext("2d");
  if(card&&card.r!=="?"&&card.r!==undefined){
    x.fillStyle="#fff";x.fillRect(0,0,128,180);x.strokeStyle="#bbb";x.lineWidth=4;x.strokeRect(2,2,124,176);
    var red=(card.s==="♥"||card.s==="♦");x.fillStyle=red?"#dc2626":"#111";
    x.font="bold 40px sans-serif";x.textAlign="left";x.fillText(card.r,12,50);
    x.font="62px sans-serif";x.textAlign="center";x.fillText(card.s,64,118);
  }else{x.fillStyle="#1e293b";x.fillRect(0,0,128,180);x.strokeStyle="#475569";x.lineWidth=4;x.strokeRect(2,2,124,176);}
  return new THREE.Mesh(new THREE.PlaneGeometry(1.35,1.9),new THREE.MeshBasicMaterial({map:new THREE.CanvasTexture(cv)}));
}

// ===== Chess (3D, backend-bridged) =====
var CG={k:"♚",q:"♛",r:"♜",b:"♝",n:"♞",p:"♟"};
GAMES.chess=function(){
  var st=null,amWhite=true,sel=null,grp=null,hl=null;
  function status(){
    if(st.status==="checkmate")return st.winner===you?"Checkmate — you win!":"Checkmate — you lost";
    if(st.status==="stalemate")return "Stalemate — draw";
    if(st.status==="draw")return "Draw";
    return (st.turn===you?"Your move":"Their move")+(st.inCheck?" · check!":"");
  }
  function highlight(){
    if(hl){scene.remove(hl);hl=null;}
    if(sel===null)return;
    var p=dispPos(sel,amWhite);hl=new THREE.Mesh(new THREE.BoxGeometry(0.98,0.24,0.98),new THREE.MeshBasicMaterial({color:0x86efac,transparent:true,opacity:0.6}));hl.position.set(p.x,0.12,p.z);scene.add(hl);
  }
  function draw(){
    if(grp)scene.remove(grp);grp=new THREE.Group();
    for(var sq=0;sq<64;sq++){var c=st.board[sq];if(c===".")continue;var sp=glyphSprite(CG[c.toLowerCase()],(c===c.toUpperCase())?"#f8fafc":"#0f172a");var p=dispPos(sq,amWhite);sp.position.set(p.x,0.7,p.z);grp.add(sp);}
    scene.add(grp);hud(status());
  }
  return {
    bg:0x0b1220,
    build:function(state){st=state;amWhite=(st.white===you);camera.position.set(0,9,8);camera.lookAt(0,0,0);buildBoard(amWhite,0xedd9b5,0xb48761);draw();},
    onState:function(state){st=state;sel=null;highlight();draw();},
    pick:function(ud){
      if(st.turn!==you||st.status!=="active")return;
      var sq=ud.sq,pc=st.board[sq],mineHere=pc!=="."&&(amWhite?pc===pc.toUpperCase():pc===pc.toLowerCase());
      if(sel===null){if(mineHere){sel=sq;highlight();}return;}
      if(sq===sel){sel=null;highlight();return;}
      if(mineHere){sel=sq;highlight();return;}
      var from=sqName(sel),to=sqName(sq);sel=null;highlight();hud("...");send("action",{action:{from:from,to:to}});
    }
  };
};

// ===== Checkers (3D, backend-bridged) =====
GAMES.checkers=function(){
  var st=null,amWhite=true,sel=null,grp=null,hl=null;
  function status(){if(st.status!=="active")return st.winner===you?"You win!":"You lost";return st.turn===you?"Your move":"Their move";}
  function highlight(){if(hl){scene.remove(hl);hl=null;}if(sel===null)return;var p=dispPos(sel,amWhite);hl=new THREE.Mesh(new THREE.BoxGeometry(0.98,0.24,0.98),new THREE.MeshBasicMaterial({color:0x86efac,transparent:true,opacity:0.6}));hl.position.set(p.x,0.12,p.z);scene.add(hl);}
  function disc(white,king){var m=new THREE.Mesh(new THREE.CylinderGeometry(0.36,0.36,0.22,24),new THREE.MeshStandardMaterial({color:white?0xf1f5f9:0x1f2937}));if(king){var c=new THREE.Mesh(new THREE.CylinderGeometry(0.2,0.2,0.26,24),new THREE.MeshStandardMaterial({color:0xf6c455}));c.position.y=0.12;m.add(c);}return m;}
  function draw(){if(grp)scene.remove(grp);grp=new THREE.Group();for(var sq=0;sq<64;sq++){var c=st.board[sq];if(c===".")continue;var white=(c==="w"||c==="W"),king=(c==="W"||c==="B");var d=disc(white,king);var p=dispPos(sq,amWhite);d.position.set(p.x,0.22,p.z);grp.add(d);}scene.add(grp);hud(status());}
  return {
    bg:0x0b1220,
    build:function(state){st=state;amWhite=(st.white===you);camera.position.set(0,9,8);camera.lookAt(0,0,0);buildBoard(amWhite,0xead9bd,0x8d6748);draw();},
    onState:function(state){st=state;sel=(st.turn===you&&st.chain!==null&&st.chain!==undefined)?st.chain:null;highlight();draw();},
    pick:function(ud){
      if(st.turn!==you||st.status!=="active")return;
      var sq=ud.sq,p=st.board[sq],mineHere=amWhite?(p==="w"||p==="W"):(p==="b"||p==="B");
      if(sel===null){if(mineHere){sel=sq;highlight();}return;}
      if(sq===sel){sel=null;highlight();return;}
      if(mineHere){sel=sq;highlight();return;}
      var from=sel;sel=null;highlight();hud("...");send("action",{action:{from:from,to:sq}});
    }
  };
};

// ===== Blackjack (3D cards, backend-bridged) =====
GAMES.blackjack=function(){
  var st=null,grp=null;
  function result(s){return s==="blackjack"?"Blackjack! You win":s==="win"?"You win":s==="lose"?"Dealer wins":s==="push"?"Push — tie":"";}
  function row(cards,z){for(var i=0;i<cards.length;i++){var m=cardMesh(cards[i]);m.position.set((i-(cards.length-1)/2)*1.5,0.01,z);m.rotation.x=-Math.PI/2;grp.add(m);}}
  function draw(){
    if(grp)scene.remove(grp);grp=new THREE.Group();
    row(st.dealer,-2.0);row(st.player,2.0);scene.add(grp);
    var over=(st.status!=="active");
    hud("Dealer "+(over?st.dealerTotal:"?")+"   ·   You "+st.playerTotal);
    if(over){showOver(result(st.status));setButtons(null);}
    else{hideOver();if(st.mine)setButtons([{label:"Hit",cb:function(){hud("...");send("action",{action:{move:"hit"}});}},{label:"Stand",cb:function(){hud("...");send("action",{action:{move:"stand"}});}}]);else setButtons(null);}
  }
  D.getElementById("again").onclick=function(){send("action",{action:{move:"rematch"}});};
  return {bg:0x0b3b24,build:function(state){st=state;camera.position.set(0,7,6.5);camera.lookAt(0,0,0);draw();},onState:function(state){st=state;draw();}};
};

// ===== Poker (3D cards, backend-bridged) =====
GAMES.poker=function(){
  var st=null,grp=null,holds={};
  function result(s){return s==="win"?"You win":s==="lose"?"Dealer wins":s==="push"?"Split — tie":"";}
  function draw(){
    if(grp)scene.remove(grp);grp=new THREE.Group();pickables=[];
    for(var i=0;i<st.opponent.length;i++){var d=cardMesh(st.opponent[i]);d.position.set((i-2)*1.55,0.01,-2.4);d.rotation.x=-Math.PI/2;grp.add(d);}
    for(var i=0;i<st.you.length;i++){var m=cardMesh(st.you[i]);m.position.set((i-2)*1.55,holds[i]?0.5:0.01,2.4);m.rotation.x=-Math.PI/2;m.userData={hold:i};grp.add(m);pickables.push(m);}
    scene.add(grp);
    var over=(st.status==="win"||st.status==="lose"||st.status==="push");
    hud("You: "+st.yourHand+(st.opponentHand?("   ·   Dealer: "+st.opponentHand):""));
    if(over){showOver(result(st.status));setButtons(null);}
    else if(st.status==="active"&&st.mine){hideOver();setButtons([{label:"Draw",cb:function(){var h=[];for(var k in holds)if(holds[k])h.push(parseInt(k,10));hud("Dealing...");setButtons(null);send("action",{action:{move:"draw",holds:h}});}}]);}
    else setButtons(null);
  }
  D.getElementById("again").onclick=function(){holds={};send("action",{action:{move:"rematch"}});};
  return {
    bg:0x0b3b24,
    build:function(state){st=state;camera.position.set(0,7,6.5);camera.lookAt(0,0,0);draw();},
    onState:function(state){st=state;draw();},
    pick:function(ud){if(ud.hold===undefined||st.status!=="active")return;holds[ud.hold]=!holds[ud.hold];draw();}
  };
};

send("ready");
</script></body></html>
''';
