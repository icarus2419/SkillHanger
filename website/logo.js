// Hero mark: particles spiral in and crystallise into the glossy, extruded SkillHanger "h".
// Adapted from the TikTok end-card engine. Falls back to the PNG when WebGL or motion is unavailable.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { MeshSurfaceSampler } from 'three/addons/math/MeshSurfaceSampler.js';

const stage = document.querySelector('.hero-stage');
const canvas = document.getElementById('logo3d');
const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const easeOut = (t) => 1 - Math.pow(1 - t, 3);

async function main() {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.78;
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1, 1, 5000);
  camera.position.set(0, 0, 1800);
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  const key = new THREE.DirectionalLight(0xfff1e8, 1.5); key.position.set(-600, 900, 1400); scene.add(key);
  const rim = new THREE.DirectionalLight(0xff9aa6, 0.8); rim.position.set(900, -300, -600); scene.add(rim);
  scene.add(new THREE.AmbientLight(0xffffff, 0.2));

  // --- extruded logo from the traced silhouette ---
  const S = 420;
  const data = await (await fetch('assets/logo-shape.json')).json();
  const shapes = data.shapes.map(({ outer, holes }) => {
    const s = new THREE.Shape(outer.map(([x, y]) => new THREE.Vector2(x * S, y * S)));
    s.holes = holes.map((h) => new THREE.Path(h.map(([x, y]) => new THREE.Vector2(x * S, y * S))));
    return s;
  });
  const depth = S * 0.2;
  const geo = new THREE.ExtrudeGeometry(shapes, {
    depth, bevelEnabled: true, bevelThickness: S * 0.05, bevelSize: S * 0.035, bevelSegments: 10, curveSegments: 24,
  });
  geo.center();
  geo.computeVertexNormals();

  const uniforms = { uSweep: { value: -9999 }, uGlint: { value: 0 } };
  const mat = new THREE.MeshPhysicalMaterial({
    color: new THREE.Color('#B3243B'), roughness: 0.32, clearcoat: 1, clearcoatRoughness: 0.12,
    envMapIntensity: 0.5, transparent: true, opacity: still ? 1 : 0,
  });
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;')
      .replace('#include <worldpos_vertex>', '#include <worldpos_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;\nuniform float uSweep;\nuniform float uGlint;')
      .replace('#include <dithering_fragment>', `
        float band = vWPos.x * 0.75 + vWPos.y;
        float g = smoothstep(70.0, 0.0, abs(band - uSweep));
        float core = smoothstep(14.0, 0.0, abs(band - uSweep));
        gl_FragColor.rgb += uGlint * (g * vec3(1.0, 0.72, 0.74) * 0.55 + core * vec3(1.0, 0.95, 0.92) * 0.9);
        #include <dithering_fragment>`);
  };
  const mesh = new THREE.Mesh(geo, mat);
  const group = new THREE.Group();
  group.add(mesh);
  scene.add(group);

  // --- particles sampled on the surface, launched from a wide shell ---
  const N = still ? 0 : (innerWidth < 700 ? 7000 : 14000);
  const sampler = new MeshSurfaceSampler(mesh).build();
  const tgt = new Float32Array(N * 3), start = new Float32Array(N * 3), aux = new Float32Array(N * 3);
  const v = new THREE.Vector3();
  for (let i = 0; i < N; i++) {
    sampler.sample(v);
    tgt.set([v.x, v.y, v.z], i * 3);
    const a = Math.random() * Math.PI * 2, r = 700 + Math.random() * 900, z = (Math.random() - 0.5) * 1400;
    start.set([Math.cos(a) * r, Math.sin(a) * r, z], i * 3);
    aux.set([Math.random(), Math.random(), Math.random() < 0.5 ? -1 : 1], i * 3);
  }
  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(tgt, 3));
  pGeo.setAttribute('aStart', new THREE.BufferAttribute(start, 3));
  pGeo.setAttribute('aAux', new THREE.BufferAttribute(aux, 3));
  const pU = { uT: { value: 0 }, uFade: { value: 1 }, uSize: { value: 5.0 * renderer.getPixelRatio() } };
  const pMat = new THREE.ShaderMaterial({
    uniforms: pU, transparent: true, depthWrite: false,
    vertexShader: /* glsl */`
      attribute vec3 aStart; attribute vec3 aAux;
      uniform float uT; uniform float uSize;
      varying vec3 vCol; varying float vShade;
      vec3 rotY(vec3 p, float a){ float c=cos(a), s=sin(a); return vec3(c*p.x + s*p.z, p.y, -s*p.x + c*p.z); }
      vec3 rotZ(vec3 p, float a){ float c=cos(a), s=sin(a); return vec3(c*p.x - s*p.y, s*p.x + c*p.y, p.z); }
      void main(){
        float delay = aAux.x * 0.45, sd = aAux.y, dir = aAux.z;
        float p = clamp((uT - delay) / 1.1, 0.0, 1.0);
        p = p < 0.5 ? 4.0*p*p*p : 1.0 - pow(-2.0*p + 2.0, 3.0) / 2.0;
        vec3 pos = mix(aStart, position, p);
        float swirl = (1.0 - p) * 3.2 * dir * (0.6 + sd);
        pos = rotZ(rotY(pos, swirl * 0.5), swirl * 0.4);
        pos.z += sin(p * 3.14159) * (sd - 0.35) * 420.0;
        vec4 mv = modelViewMatrix * vec4(pos, 1.0);
        gl_Position = projectionMatrix * mv;
        float flight = sin(p * 3.14159);
        gl_PointSize = uSize * (1.0 + flight * 1.2) * (1800.0 / -mv.z);
        vec3 brand = mix(vec3(0.70, 0.14, 0.23), vec3(0.98, 0.47, 0.53), step(0.7, sd));
        vCol = mix(vec3(0.48, 0.16, 0.22), brand, p);
        vShade = 0.55 + 0.45 * (1.0 - flight);
      }`,
    fragmentShader: /* glsl */`
      uniform float uFade; varying vec3 vCol; varying float vShade;
      void main(){
        vec2 c = gl_PointCoord * 2.0 - 1.0;
        float r2 = dot(c, c);
        if (r2 > 1.0) discard;
        float light = 0.75 + 0.35 * (1.0 - r2) - 0.15 * c.y;
        gl_FragColor = vec4(vCol * light * vShade, uFade * smoothstep(1.0, 0.6, r2));
      }`,
  });
  const points = new THREE.Points(pGeo, pMat);
  points.frustumCulled = false;
  if (N) group.add(points);

  // --- sizing ---
  const resize = () => {
    const { width, height } = stage.getBoundingClientRect();
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    // fit the ~420px-tall mark to ~42% of the stage height
    camera.position.z = (S / 0.42 / 2) / Math.tan((camera.fov / 2) * Math.PI / 180);
    camera.position.y = -S * 0.02;
    camera.updateProjectionMatrix();
  };
  new ResizeObserver(resize).observe(stage);
  resize();

  // --- interaction: pointer tilt + drag to spin with inertia ---
  let tx = 0, ty = 0, spin = 0, vel = 0, dragging = false, lastX = 0;
  stage.addEventListener('pointermove', (e) => {
    const r = stage.getBoundingClientRect();
    tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
    ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    if (dragging) { const dx = e.clientX - lastX; vel = dx * 0.012; spin += vel; lastX = e.clientX; }
  });
  stage.addEventListener('pointerdown', (e) => { dragging = true; lastX = e.clientX; stage.setPointerCapture(e.pointerId); });
  const up = () => { dragging = false; };
  stage.addEventListener('pointerup', up);
  stage.addEventListener('pointercancel', up);
  stage.addEventListener('pointerleave', () => { tx = ty = 0; });

  let visible = true;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(stage);

  stage.classList.add('gl');
  const t0 = performance.now();
  let rx = 0, ry = 0, lastGlint = still ? 0 : 1.7;
  const tick = (now) => {
    requestAnimationFrame(tick);
    if (!visible) return;
    const t = (now - t0) / 1000;

    if (N) {
      pU.uT.value = t;
      const lock = clamp((t - 1.25) / 0.35);
      mat.opacity = easeOut(lock);
      pU.uFade.value = 1 - lock;
      points.visible = lock < 1;
      // spring settle on impact
      const k = clamp(t - 1.3, 0, 3);
      group.scale.setScalar(1 + (k > 0 ? Math.exp(-k * 6) * Math.sin(k * 22) * 0.06 : 0));
    }

    // glint sweep: once after lock-in, then every ~6s
    const since = t - lastGlint;
    if (since >= 0 && since < 1.1) {
      uniforms.uGlint.value = Math.sin((since / 1.1) * Math.PI);
      uniforms.uSweep.value = -420 + (since / 1.1) * 840;
    } else {
      uniforms.uGlint.value = 0;
      if (since >= 1.1 && !still) lastGlint = t + 5;
    }

    if (!dragging) { vel *= 0.94; spin += vel; spin *= 0.985; }
    const idle = still ? 0 : Math.sin(t * 0.6) * 0.18;
    rx += ((ty * 0.25) - rx) * 0.06;
    ry += ((tx * 0.45 + idle) - ry) * 0.06;
    group.rotation.set(rx, ry + spin, 0);
    group.position.y = still ? 0 : Math.sin(t * 1.1) * 6;

    renderer.render(scene, camera);
  };
  requestAnimationFrame(tick);
}

main().catch((err) => { console.warn('3D logo unavailable, using image fallback.', err); });
