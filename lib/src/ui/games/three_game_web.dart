import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web build supports the in-app WebGL games.
bool get threeGamesSupported => true;

int _seq = 0;

/// Renders a Three.js game inside a sandboxed iframe and surfaces its final
/// score via [onScore]. Each instance uses a unique nonce so its score message
/// isn't confused with another open game.
class ThreeGameView extends StatefulWidget {
  const ThreeGameView(
      {super.key, required this.gameType, required this.onScore});

  final String gameType;
  final void Function(int score) onScore;

  @override
  State<ThreeGameView> createState() => _ThreeGameViewState();
}

class _ThreeGameViewState extends State<ThreeGameView> {
  late final String _viewType;
  late final String _nonce;
  JSFunction? _listener;

  @override
  void initState() {
    super.initState();
    _nonce = 'tg${_seq++}';
    _viewType = 'three-game-$_nonce';
    final html = _gameHtml(widget.gameType, _nonce);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.setAttribute('srcdoc', html);
      iframe.setAttribute('sandbox', 'allow-scripts');
      iframe.setAttribute('scrolling', 'no');
      iframe.style.setProperty('border', 'none');
      iframe.style.setProperty('width', '100%');
      iframe.style.setProperty('height', '100%');
      return iframe;
    });
    _listener = ((web.Event e) {
      final data = (e as web.MessageEvent).data.dartify();
      if (data is Map &&
          data['nonce'] == _nonce &&
          data['type'] == 'score') {
        final s = data['score'];
        widget.onScore(s is num ? s.toInt() : 0);
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) web.window.removeEventListener('message', l);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

/// The self-contained HTML/Three.js for a game. The example is 3D Pong; other
/// types fall back to a placeholder until they're built.
String _gameHtml(String gameType, String nonce) {
  if (gameType != 'pong') {
    return '<!DOCTYPE html><html><body style="margin:0;background:#0b1220;'
        'color:#fff;font-family:sans-serif;display:flex;align-items:center;'
        'justify-content:center;height:100vh">'
        'Coming soon in 3D</body></html>';
  }
  return '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  html,body{margin:0;height:100%;overflow:hidden;background:#0b1220;font-family:sans-serif;}
  #ui{position:absolute;top:8px;left:0;right:0;text-align:center;color:#fff;font-weight:700;font-size:16px;}
  #over{position:absolute;inset:0;display:none;flex-direction:column;align-items:center;justify-content:center;color:#fff;background:rgba(0,0,0,.55);}
  #over button{margin-top:12px;padding:9px 18px;border:0;border-radius:9px;background:#0ea5e9;color:#fff;font-weight:700;font-size:15px;}
</style></head><body>
<div id="ui">You 0 — CPU 0</div>
<div id="over"><div id="msg" style="font-size:20px;font-weight:700"></div><button id="again">Play again</button></div>
<canvas id="c" style="display:block;width:100%;height:100%"></canvas>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script>
var NONCE="$nonce";
var W=10, D=14;
var renderer=new THREE.WebGLRenderer({canvas:document.getElementById('c'),antialias:true});
var scene=new THREE.Scene(); scene.background=new THREE.Color(0x0b1220);
var camera=new THREE.PerspectiveCamera(50,1,0.1,100);
camera.position.set(0,12,12); camera.lookAt(0,0,0);
function resize(){var w=window.innerWidth,h=window.innerHeight;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();}
window.addEventListener('resize',resize); resize();
scene.add(new THREE.AmbientLight(0xffffff,0.65));
var dl=new THREE.DirectionalLight(0xffffff,0.8); dl.position.set(5,12,6); scene.add(dl);
var table=new THREE.Mesh(new THREE.BoxGeometry(W,0.5,D),new THREE.MeshStandardMaterial({color:0x14223b}));
table.position.y=-0.35; scene.add(table);
var line=new THREE.Mesh(new THREE.BoxGeometry(W,0.07,0.12),new THREE.MeshBasicMaterial({color:0x335577}));
line.position.y=0.02; scene.add(line);
var ball=new THREE.Mesh(new THREE.SphereGeometry(0.35,18,18),new THREE.MeshStandardMaterial({color:0xffffff}));
scene.add(ball);
function paddle(c){return new THREE.Mesh(new THREE.BoxGeometry(2.6,0.5,0.45),new THREE.MeshStandardMaterial({color:c}));}
var pl=paddle(0x38bdf8); pl.position.set(0,0,D/2-0.6); scene.add(pl);
var cpu=paddle(0xf87171); cpu.position.set(0,0,-D/2+0.6); scene.add(cpu);
var bx=0,bz=0,vx=0.06,vz=0.11,ps=0,cs=0,over=false;
function reset(toP){bx=0;bz=0;vx=(Math.random()<0.5?0.06:-0.06);vz=toP?0.11:-0.11;}
reset(true);
function setPX(clientX){var r=renderer.domElement.getBoundingClientRect();var nx=(clientX-r.left)/r.width;pl.position.x=Math.max(-W/2+1.3,Math.min(W/2-1.3,(nx-0.5)*W));}
renderer.domElement.addEventListener('pointermove',function(e){setPX(e.clientX);});
renderer.domElement.addEventListener('touchmove',function(e){if(e.touches[0])setPX(e.touches[0].clientX);e.preventDefault();},{passive:false});
function ui(){document.getElementById('ui').textContent='You '+ps+' — CPU '+cs;}
function endGame(){over=true;document.getElementById('msg').textContent=(ps>cs)?'You win!':'CPU wins';document.getElementById('over').style.display='flex';parent.postMessage({type:'score',nonce:NONCE,score:ps},'*');}
document.getElementById('again').onclick=function(){ps=0;cs=0;over=false;reset(true);ui();document.getElementById('over').style.display='none';};
function tick(){
  requestAnimationFrame(tick);
  if(!over){
    cpu.position.x += Math.max(-0.075,Math.min(0.075, bx-cpu.position.x));
    bx+=vx; bz+=vz;
    if(bx<-W/2+0.35){bx=-W/2+0.35;vx=Math.abs(vx);}
    if(bx>W/2-0.35){bx=W/2-0.35;vx=-Math.abs(vx);}
    if(bz>D/2-1.0){ if(Math.abs(bx-pl.position.x)<1.5){vz=-Math.abs(vz);vx+=(bx-pl.position.x)*0.01;} else {cs++; if(cs>=7){ui();endGame();} else {reset(false);ui();}} }
    if(bz<-D/2+1.0){ if(Math.abs(bx-cpu.position.x)<1.5){vz=Math.abs(vz);} else {ps++; if(ps>=7){ui();endGame();} else {reset(true);ui();}} }
    ball.position.set(bx,0,bz);
  }
  renderer.render(scene,camera);
}
ui(); tick();
</script></body></html>
''';
}
