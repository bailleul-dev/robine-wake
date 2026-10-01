// Robine Wake demo room: the sound bar above the bed, with its breathing halo
// and dawn / reading lamps. Real-time PBR with three.js.
//
// The bar geometry and light anchors come from the FreeCAD model
// (export_gltf.py). Units are metres; Y is up; the headboard wall is Z = 0
// and the room extends toward +Z. The sleepers' left is +X.

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { GTAOPass } from "three/addons/postprocessing/GTAOPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import { addDecor } from "./decor.js";
import { mountRemote } from "./remote.js";

const anchors = await (await fetch("./assets/anchors.json")).json();

// ---------------------------------------------------------------------------
// Room layout, derived from the listening geometry of the model.

const MATTRESS_TOP = 0.56;
const EAR_HEIGHT = MATTRESS_TOP + 0.11; // head resting on the pillow
const BAR_Y = EAR_HEIGHT + anchors.listening.ears_below_baffle - anchors.listening.baffle_centre_height;
const CEILING = BAR_Y + anchors.bar.height + anchors.listening.ceiling_above_top;
const ROOM = { x0: -2.1, x1: 2.1, z1: 4.6 };
const PILLOW_X = anchors.listening.pillow_offset;
const PILLOW_Z = anchors.listening.head_from_wall + 0.05;

// ---------------------------------------------------------------------------
// Renderer, camera, post-processing.

// Anti-aliasing happens on the composer's render target (MSAA below): the
// canvas only receives the final full-screen pass.
const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: "high-performance" });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.AgXToneMapping;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
// Nothing in the room moves: shadow maps are rendered once (see below).
renderer.shadowMap.autoUpdate = false;
document.body.prepend(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x020308);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.03, 30);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.maxDistance = 6;

const composer = new EffectComposer(
  renderer,
  new THREE.WebGLRenderTarget(window.innerWidth, window.innerHeight, { type: THREE.HalfFloatType, samples: 4 })
);
composer.addPass(new RenderPass(scene, camera));
const ao = new GTAOPass(scene, camera, window.innerWidth, window.innerHeight);
ao.updateGtaoMaterial({ radius: 0.35, distanceExponent: 1.5, thickness: 1.0, scale: 1.0 });
ao.blendIntensity = 0.85;
// Ambient occlusion is soft and low-frequency: computed at half resolution
// and upsampled when blended, it looks the same for a quarter of the cost.
const aoSetSize = ao.setSize.bind(ao);
ao.setSize = (w, h) => aoSetSize(Math.ceil(w / 2), Math.ceil(h / 2));
ao.setSize(window.innerWidth * renderer.getPixelRatio(), window.innerHeight * renderer.getPixelRatio());
composer.addPass(ao);
// Bloom only on the emitters (unclipped, above 1.0).
const bloom = new UnrealBloomPass(new THREE.Vector2(window.innerWidth, window.innerHeight), 0.35, 0.5, 1.0);
composer.addPass(bloom);
composer.addPass(new OutputPass());

// ---------------------------------------------------------------------------
// Procedural textures (canvas): no external image files.

function canvasTexture(size, draw, { repeat = [1, 1], colour = true } = {}) {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = size;
  draw(canvas.getContext("2d"), size);
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(...repeat);
  texture.anisotropy = renderer.capabilities.getMaxAnisotropy();
  if (colour) texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function noiseField(size, cells, seed) {
  // Value noise on a periodic grid so textures tile seamlessly.
  let s = seed;
  const rand = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  const grid = Array.from({ length: cells * cells }, rand);
  const at = (i, j) => grid[((j + cells) % cells) * cells + ((i + cells) % cells)];
  return (x, y) => {
    const fx = (x / size) * cells, fy = (y / size) * cells;
    const i = Math.floor(fx), j = Math.floor(fy);
    const u = fx - i, v = fy - j;
    const su = u * u * (3 - 2 * u), sv = v * v * (3 - 2 * v);
    const a = at(i, j) * (1 - su) + at(i + 1, j) * su;
    const b = at(i, j + 1) * (1 - su) + at(i + 1, j + 1) * su;
    return a * (1 - sv) + b * sv;
  };
}

function heightToNormal(ctx, size, height, strength) {
  const img = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = (height(x + 1, y) - height(x - 1, y)) * strength;
      const dy = (height(x, y + 1) - height(x, y - 1)) * strength;
      const inv = 1 / Math.sqrt(dx * dx + dy * dy + 1);
      const k = (y * size + x) * 4;
      img.data[k] = (-dx * inv * 0.5 + 0.5) * 255;
      img.data[k + 1] = (-dy * inv * 0.5 + 0.5) * 255;
      img.data[k + 2] = (inv * 0.5 + 0.5) * 255;
      img.data[k + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
}

function normalTexture(size, height, strength, repeat) {
  return canvasTexture(size, (ctx) => heightToNormal(ctx, size, height, strength), { repeat, colour: false });
}

// Tolex levant grain: crinkled cells.
const levant = (() => {
  const a = noiseField(256, 48, 11), b = noiseField(256, 96, 23);
  return (x, y) => Math.abs(a(x, y) - 0.5) * 1.6 + b(x, y) * 0.4;
})();
// Linen weave.
const weave = (x, y) => 0.5 + 0.25 * Math.sin(x * 1.6) * Math.sin(y * 0.2) + 0.25 * Math.sin(y * 1.6) * Math.sin(x * 0.2);
// Plaster.
const plaster = noiseField(256, 24, 7);

const textures = {
  tolexNormal: normalTexture(256, levant, 2.2, [6, 6]),
  linenNormal: normalTexture(128, weave, 0.6, [40, 40]),
  plasterNormal: normalTexture(256, plaster, 1.0, [6, 6]),
  oak: canvasTexture(
    1024,
    (ctx, size) => {
      const grain = noiseField(size, 64, 5);
      const planks = 6;
      const img = ctx.createImageData(size, size);
      for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
          const p = Math.floor((x * planks) / size);
          const tone = 0.85 + ((p * 37) % 11) / 60;
          const g = grain(x * 0.15, y * 3);
          const k = (y * size + x) * 4;
          img.data[k] = (172 + 40 * g) * tone;
          img.data[k + 1] = (128 + 30 * g) * tone;
          img.data[k + 2] = (86 + 18 * g) * tone;
          img.data[k + 3] = 255;
        }
      }
      ctx.putImageData(img, 0, 0);
      for (let p = 0; p < planks; p++) {
        ctx.fillStyle = "rgba(40,25,15,0.55)";
        ctx.fillRect(((p + 1) * size) / planks - 2, 0, 2, size);
        ctx.fillRect((p * size) / planks, ((p * 397) % size), size / planks, 2);
      }
    },
    { repeat: [2.2, 2.2] }
  ),
  walnut: canvasTexture(
    512,
    (ctx, size) => {
      const grain = noiseField(size, 32, 9);
      const img = ctx.createImageData(size, size);
      for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
          const g = grain(x * 0.2, y * 4);
          const k = (y * size + x) * 4;
          img.data[k] = 78 + 40 * g;
          img.data[k + 1] = 50 + 26 * g;
          img.data[k + 2] = 32 + 14 * g;
          img.data[k + 3] = 255;
        }
      }
      ctx.putImageData(img, 0, 0);
    },
    { repeat: [1, 1] }
  ),
};

// ---------------------------------------------------------------------------
// Materials.

const M = {
  tolex: new THREE.MeshPhysicalMaterial({
    color: 0x1b2a52, roughness: 0.62, normalMap: textures.tolexNormal, normalScale: new THREE.Vector2(0.45, 0.45),
    clearcoat: 0.12, clearcoatRoughness: 0.5, side: THREE.DoubleSide,
  }),
  driver: new THREE.MeshPhysicalMaterial({ color: 0x0b0b0d, roughness: 0.75, sheen: 0.3, side: THREE.DoubleSide }),
  housing: new THREE.MeshStandardMaterial({ color: 0x080808, roughness: 0.6, side: THREE.DoubleSide }),
  wall: new THREE.MeshStandardMaterial({ color: 0xebe4da, roughness: 0.95, normalMap: textures.plasterNormal, normalScale: new THREE.Vector2(0.06, 0.06) }),
  ceiling: new THREE.MeshStandardMaterial({ color: 0xf4f1ec, roughness: 1.0 }),
  floor: new THREE.MeshPhysicalMaterial({ map: textures.oak, roughness: 0.48, clearcoat: 0.25, clearcoatRoughness: 0.35 }),
  sheet: new THREE.MeshPhysicalMaterial({ color: 0xf1eee8, roughness: 1, sheen: 0.6, sheenColor: 0xffffff, normalMap: textures.linenNormal }),
  duvet: new THREE.MeshPhysicalMaterial({ color: 0xcdbfa8, roughness: 1, sheen: 0.7, sheenColor: 0xfff4e0, normalMap: textures.linenNormal }),
  throwBlanket: new THREE.MeshPhysicalMaterial({ color: 0xa4553a, roughness: 1, sheen: 0.8, sheenColor: 0xffc7a8, normalMap: textures.linenNormal }),
  headboard: new THREE.MeshPhysicalMaterial({ color: 0xb3a592, roughness: 1, sheen: 0.9, sheenColor: 0xe8dccb }),
  walnut: new THREE.MeshPhysicalMaterial({ map: textures.walnut, roughness: 0.42, clearcoat: 0.3 }),
  rug: new THREE.MeshPhysicalMaterial({ color: 0xd9d0c1, roughness: 1, sheen: 1, sheenColor: 0xffffff }),
  // No transmission: it would add a full extra render of the room per frame.
  curtain: new THREE.MeshPhysicalMaterial({ color: 0xe5dccd, roughness: 1, sheen: 0.6, side: THREE.DoubleSide }),
  frame: new THREE.MeshStandardMaterial({ color: 0x2b2b2b, roughness: 0.5 }),
};

// ---------------------------------------------------------------------------
// Room.

function add(mesh, { cast = true, receive = true } = {}) {
  mesh.castShadow = cast;
  mesh.receiveShadow = receive;
  scene.add(mesh);
  return mesh;
}

function plane(w, h, material, position, rotation) {
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), material);
  mesh.position.set(...position);
  mesh.rotation.set(...rotation);
  return add(mesh, { cast: false });
}

const width = ROOM.x1 - ROOM.x0;
plane(width, ROOM.z1, M.floor, [0, 0, ROOM.z1 / 2], [-Math.PI / 2, 0, 0]);
plane(width, ROOM.z1, M.ceiling, [0, CEILING, ROOM.z1 / 2], [Math.PI / 2, 0, 0]);
plane(width, CEILING, M.wall, [0, CEILING / 2, 0], [0, 0, 0]);
plane(width, CEILING, M.wall, [0, CEILING / 2, ROOM.z1], [0, Math.PI, 0]);
plane(ROOM.z1, CEILING, M.wall, [ROOM.x0, CEILING / 2, ROOM.z1 / 2], [0, Math.PI / 2, 0]);

// Right wall (+X) with a window.
const WINDOW = { z0: 2.4, z1: 3.6, y0: 0.85, y1: 2.15 };
{
  const shape = new THREE.Shape();
  shape.moveTo(0, 0).lineTo(ROOM.z1, 0).lineTo(ROOM.z1, CEILING).lineTo(0, CEILING).lineTo(0, 0);
  const hole = new THREE.Path();
  hole.moveTo(WINDOW.z0, WINDOW.y0).lineTo(WINDOW.z1, WINDOW.y0).lineTo(WINDOW.z1, WINDOW.y1).lineTo(WINDOW.z0, WINDOW.y1);
  shape.holes.push(hole);
  const wall = add(new THREE.Mesh(new THREE.ShapeGeometry(shape), M.wall), { cast: true });
  wall.rotation.y = -Math.PI / 2;
  wall.position.set(ROOM.x1, 0, 0);
}
const sky = new THREE.Mesh(
  new THREE.PlaneGeometry(WINDOW.z1 - WINDOW.z0 + 0.6, WINDOW.y1 - WINDOW.y0 + 0.6),
  new THREE.MeshBasicMaterial({ color: 0x0a1020 })
);
sky.rotation.y = -Math.PI / 2;
sky.position.set(ROOM.x1 + 0.25, (WINDOW.y0 + WINDOW.y1) / 2, (WINDOW.z0 + WINDOW.z1) / 2);
scene.add(sky);
// Window frame and mullion.
for (const [w, h, y, z] of [
  [0.05, WINDOW.y1 - WINDOW.y0, (WINDOW.y0 + WINDOW.y1) / 2, (WINDOW.z0 + WINDOW.z1) / 2],
  [WINDOW.z1 - WINDOW.z0, 0.05, (WINDOW.y0 + WINDOW.y1) / 2 + 0.2, (WINDOW.z0 + WINDOW.z1) / 2],
]) {
  const bar = add(new THREE.Mesh(new THREE.BoxGeometry(0.05, h, w), M.frame));
  bar.position.set(ROOM.x1 - 0.03, y, z);
}
// Linen curtains, gathered on both sides of the window.
function curtain(z, width) {
  const geometry = new THREE.PlaneGeometry(width, CEILING - 0.1, 48, 4);
  const pos = geometry.attributes.position;
  for (let i = 0; i < pos.count; i++) pos.setZ(i, Math.sin(pos.getX(i) * 38) * 0.03);
  geometry.computeVertexNormals();
  const mesh = add(new THREE.Mesh(geometry, M.curtain));
  mesh.rotation.y = -Math.PI / 2;
  mesh.position.set(ROOM.x1 - 0.12, (CEILING - 0.1) / 2, z);
}
curtain(WINDOW.z0 - 0.1, 0.45);
curtain(WINDOW.z1 + 0.1, 0.45);

// Bed: frame, mattress, sheet, duvet, pillows, headboard.
{
  const frame = add(new THREE.Mesh(new RoundedBoxGeometry(1.72, 0.3, 2.12, 4, 0.03), M.walnut));
  frame.position.set(0, 0.2, 1.1);
  const legs = [[-0.8, 0.1], [0.8, 0.1], [-0.8, 2.1], [0.8, 2.1]];
  for (const [x, z] of legs) {
    const leg = add(new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.02, 0.06), M.walnut));
    leg.position.set(x, 0.03, z);
  }
  const mattress = add(new THREE.Mesh(new RoundedBoxGeometry(1.6, 0.22, 2.0, 6, 0.06), M.sheet));
  mattress.position.set(0, MATTRESS_TOP - 0.11, 1.1);

  const headboard = add(new THREE.Mesh(new RoundedBoxGeometry(1.8, 0.62, 0.08, 6, 0.035), M.headboard));
  headboard.position.set(0, 0.68, 0.05);

  // Duvet: a high-resolution sheet over the lower part of the bed, draped
  // over the sides, with soft wrinkles and a folded edge.
  const duvetGeo = new THREE.PlaneGeometry(1.86, 1.55, 120, 100);
  duvetGeo.rotateX(-Math.PI / 2);
  const wrinkle = noiseField(512, 12, 3);
  const p = duvetGeo.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i);
    const over = Math.max(0, Math.abs(x) - 0.78);
    let y = MATTRESS_TOP + 0.045 - over * 1.6 + (wrinkle((x + 1) * 200, (z + 1) * 200) - 0.5) * 0.02;
    if (over > 0) y -= over * over * 2;
    p.setXYZ(i, Math.sign(x) * Math.min(Math.abs(x), 0.8 + over * 0.15), y, z);
  }
  duvetGeo.computeVertexNormals();
  const duvet = add(new THREE.Mesh(duvetGeo, M.duvet));
  duvet.position.set(0, 0, 1.38);
  const fold = add(new THREE.Mesh(new RoundedBoxGeometry(1.64, 0.05, 0.22, 4, 0.024), M.duvet));
  fold.position.set(0, MATTRESS_TOP + 0.06, 0.66);
  const throwBlanket = add(new THREE.Mesh(new RoundedBoxGeometry(1.7, 0.03, 0.42, 4, 0.014), M.throwBlanket));
  throwBlanket.position.set(0, MATTRESS_TOP + 0.075, 1.85);

  // Pillows: rounded boxes puffed toward the centre.
  for (const x of [-PILLOW_X, PILLOW_X]) {
    const g = new RoundedBoxGeometry(0.62, 0.15, 0.42, 8, 0.07);
    const q = g.attributes.position;
    for (let i = 0; i < q.count; i++) {
      const px = q.getX(i) / 0.31, pz = q.getZ(i) / 0.21;
      const puff = 1 - 0.55 * Math.min(1, px * px * 0.6 + pz * pz * 0.6);
      q.setY(i, q.getY(i) * puff);
    }
    g.computeVertexNormals();
    const pillow = add(new THREE.Mesh(g, M.sheet));
    pillow.position.set(x, MATTRESS_TOP + 0.06, PILLOW_Z);
    pillow.rotation.x = -0.12;
  }
}

// Nightstands with a book on the left one.
for (const x of [-1.22, 1.22]) {
  const table = add(new THREE.Mesh(new RoundedBoxGeometry(0.5, 0.45, 0.4, 4, 0.015), M.walnut));
  table.position.set(x, 0.225, 0.22);
}
{
  const book = add(new THREE.Mesh(new RoundedBoxGeometry(0.16, 0.03, 0.23, 2, 0.004), new THREE.MeshStandardMaterial({ color: 0x8a3b2c, roughness: 0.8 })));
  book.position.set(1.18, 0.465, 0.22);
  book.rotation.y = 0.3;
}

addDecor({
  add, canvasTexture, noiseField, M,
  room: ROOM, window: WINDOW, mattressTop: MATTRESS_TOP, pillowX: PILLOW_X, pillowZ: PILLOW_Z,
});

// ---------------------------------------------------------------------------
// The sound bar.

const bar = new THREE.Group();
bar.position.set(0, BAR_Y, 0);
scene.add(bar);
const gltf = await new GLTFLoader().loadAsync("./assets/robine-soundbar.glb");
gltf.scene.traverse((node) => {
  if (!node.isMesh) return;
  const family = node.material.name;
  node.material = M[family] ?? M.housing;
  node.castShadow = node.receiveShadow = true;
});
bar.add(gltf.scene);

// Emitter discs at the lamp and halo apertures (they bloom when lit).
function emitter(position, axis, diameter) {
  // Tone-mapped like the rest of the scene; its brightness is scaled by
  // glowGain so it stays above the bloom threshold at any exposure.
  const material = new THREE.MeshBasicMaterial({ color: 0x000000 });
  const disc = new THREE.Mesh(new THREE.CircleGeometry(diameter / 2, 40), material);
  const p = new THREE.Vector3(...position);
  const a = new THREE.Vector3(...axis).normalize();
  disc.position.copy(p).addScaledVector(a, -0.004);
  disc.lookAt(disc.position.clone().add(a));
  bar.add(disc);
  return material;
}

// ---------------------------------------------------------------------------
// Static batching: every mesh sharing a material (and shadow flags) becomes a
// single draw call. Materials are kept, so lights and emitters still drive
// them. Instanced meshes (olive leaves) are already one draw call.

function mergeStatic(root) {
  root.updateMatrixWorld(true);
  const groups = new Map();
  root.traverse((o) => {
    if (!o.isMesh || o.isInstancedMesh) return;
    const key = `${o.material.uuid}|${o.castShadow}|${o.receiveShadow}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(o);
  });
  for (const meshes of groups.values()) {
    if (meshes.length < 2) continue;
    const geometries = meshes.map((mesh) => {
      const g = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry.clone();
      for (const name of Object.keys(g.attributes)) {
        if (!["position", "normal", "uv"].includes(name)) g.deleteAttribute(name);
      }
      if (!g.attributes.uv) g.setAttribute("uv", new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      g.applyMatrix4(mesh.matrixWorld);
      return g;
    });
    const merged = new THREE.Mesh(mergeGeometries(geometries), meshes[0].material);
    merged.castShadow = meshes[0].castShadow;
    merged.receiveShadow = meshes[0].receiveShadow;
    for (const mesh of meshes) {
      mesh.removeFromParent();
      mesh.geometry.dispose();
    }
    scene.add(merged);
  }
}
mergeStatic(scene);

// ---------------------------------------------------------------------------
// Lights.

const SOLID = (beamDeg) => 2 * Math.PI * (1 - Math.cos(THREE.MathUtils.degToRad(beamDeg / 2)));
const BEAM_EFFICIENCY = 0.8;
const candela = (lumens, beamDeg) => (lumens * BEAM_EFFICIENCY) / SOLID(beamDeg);

function spot(position, target, beamDeg, penumbra, shadows) {
  const light = new THREE.SpotLight(0xffffff, 0, 0, THREE.MathUtils.degToRad(beamDeg / 2), penumbra, 2);
  light.position.copy(position);
  light.target.position.copy(target);
  light.castShadow = shadows;
  light.shadow.mapSize.set(1024, 1024);
  light.shadow.bias = -0.0004;
  light.shadow.radius = 4;
  scene.add(light, light.target);
  return light;
}

const toWorld = (v) => new THREE.Vector3(...v).add(bar.position);

const halo = (() => {
  const position = toWorld(anchors.halo.position);
  const target = toWorld(anchors.halo.target);
  const axis = target.clone().sub(position).normalize();
  const light = spot(position.clone().addScaledVector(axis, 0.01), target, anchors.halo.beam_deg, 0.55, false);
  const glow = emitter(anchors.halo.position, axis.toArray(), anchors.halo.aperture * 0.75);
  return { light, glow };
})();

const lamps = {};
for (const side of ["L", "R"]) {
  const a = anchors.lamps[side];
  const position = toWorld(a.position);
  const axis = new THREE.Vector3(...a.axis).normalize();
  const light = spot(position.clone().addScaledVector(axis, 0.01), position.clone().addScaledVector(axis, 1), anchors.lamps.beam_deg, 0.45, true);
  const glow = emitter(a.position, a.axis, anchors.lamps.aperture * 0.8);
  lamps[side] = { light, glow };
}

// Moon / sun through the window, and a sky fill.
const windowLight = new THREE.DirectionalLight(0xffffff, 0);
windowLight.position.set(ROOM.x1 + 3, 3.2, (WINDOW.z0 + WINDOW.z1) / 2 - 1.2);
windowLight.target.position.set(-0.4, 0.4, 1.4);
windowLight.castShadow = true;
windowLight.shadow.mapSize.set(2048, 2048);
Object.assign(windowLight.shadow.camera, { left: -3, right: 3, top: 3, bottom: -3, near: 0.5, far: 12 });
windowLight.shadow.bias = -0.0003;
windowLight.shadow.radius = 6;
scene.add(windowLight, windowLight.target);
const skyFill = new THREE.HemisphereLight(0xbfd2ff, 0x3a2a20, 0);
scene.add(skyFill);
// Stand-in for the light bounced by walls and bedding (no real-time GI).
const bounce = new THREE.AmbientLight(0xffffff, 0);
scene.add(bounce);

// ---------------------------------------------------------------------------
// Colour helpers.

function kelvin(temperature) {
  // Tanner Helland approximation of a black body, in sRGB.
  const t = temperature / 100;
  const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
  const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
  const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
  const c = (v) => THREE.MathUtils.clamp(v, 0, 255) / 255;
  return new THREE.Color().setRGB(c(r), c(g), c(b), THREE.SRGBColorSpace);
}

function fromXy(x, y) {
  // CIE xy (Y = 1) to a normalised linear sRGB colour.
  const X = x / y, Z = (1 - x - y) / y;
  let r = 3.2406 * X - 1.5372 - 0.4986 * Z;
  let g = -0.9689 * X + 1.8758 + 0.0415 * Z;
  let b = 0.0557 * X - 0.204 + 1.057 * Z;
  const m = Math.max(r, g, b);
  [r, g, b] = [r, g, b].map((v) => Math.max(0, v / m));
  return new THREE.Color().setRGB(r, g, b, THREE.LinearSRGBColorSpace);
}

// Spec 30-003: amber gold on the inhale, dusk pink on the exhale.
const AMBER = fromXy(0.56, 0.42);
const DUSK = fromXy(0.5, 0.3);

// ---------------------------------------------------------------------------
// Scenes. Each one sets the light outputs (lumens) every frame.

// Halo: a few lumens is plenty in a dark room; at the 30 % peak of the
// breath it puts ~16 lux on the ceiling.
const HALO_MAX_LM = 3;
const READING_LUX = 900; // on the book at full power (lighting.py)
// One adaptation for every night scene (night, breathing, start of the
// dawn): the room keeps the same overall darkness and only the halo or the
// lamps make the difference.
const NIGHT_ADAPTATION_LUX = 10;
const LAMP_LM = anchors.lamps.flux_lm;
const LUX_PER_LUMEN_AT_EYE = 3.21; // from lighting.py

// alarm: "none" | "active" (the dawn reached the wake time) | "dismissed"
// (stopped from the remote).
const state = { scene: "night", dawnMinutes: 0, dawnPlaying: true, started: performance.now(), alarm: "none" };
let glowGain = 1; // 1 / exposure of the previous frame

function setLamp(side, lumens, colour) {
  const { light, glow } = lamps[side];
  light.intensity = candela(lumens, anchors.lamps.beam_deg);
  light.color.copy(colour);
  glow.color.copy(colour).multiplyScalar(Math.min(6, lumens / 40) * glowGain);
  if (lumens > 0) bounce.color.copy(colour);
}

function setHalo(lumens, colour) {
  halo.light.intensity = candela(lumens, anchors.halo.beam_deg);
  halo.light.color.copy(colour);
  halo.glow.color.copy(colour).multiplyScalar(Math.min(4, lumens * 2) * glowGain);
  if (lumens > 0) bounce.color.copy(colour);
}

function setWindow(skyColour, lightColour, lux, fill) {
  if (lux > 100) bounce.color.copy(lightColour);
  sky.material.color.copy(skyColour);
  windowLight.color.copy(lightColour);
  windowLight.intensity = lux;
  skyFill.intensity = fill;
}

// Every scene returns the light it emits (lumens, for the bounce light) and a
// reference illuminance (lux) the eye adapts to: exposure follows it, so a
// 1-lux halo and a 900-lux reading lamp both read correctly.
const NIGHT_SKY = new THREE.Color(0x0b1430);
const MOON = new THREE.Color(0x9fb6ff);
const darkWindow = () => setWindow(NIGHT_SKY, MOON, 0.05, 0.004);
const lampsOff = () => (setLamp("L", 0, kelvin(2700)), setLamp("R", 0, kelvin(2700)));

const SCENES = {
  night: {
    label: "Night: the room is dark, moonlight through the window.",
    environment: 0.01,
    update() {
      setHalo(0, AMBER);
      lampsOff();
      darkWindow();
      return { lumens: 0, lux: NIGHT_ADAPTATION_LUX };
    },
  },
  breathing: {
    label: "Breathing: 4 s in, 6 s out, the halo glows on the ceiling (spec 30-003).",
    animated: () => true,
    environment: 0.01,
    update(t) {
      const cycle = t % 10;
      const k = cycle < 4 ? cycle / 4 : 1 - (cycle - 4) / 6;
      const s = k * k * (3 - 2 * k);
      const level = 0.02 + (0.3 - 0.02) * s;
      setHalo(HALO_MAX_LM * level, DUSK.clone().lerp(AMBER, s));
      lampsOff();
      darkWindow();
      return { lumens: HALO_MAX_LM * level, lux: NIGHT_ADAPTATION_LUX };
    },
    status: (t) => ((t % 10) < 4 ? "<strong>Inhale</strong>" : "<strong>Exhale</strong>"),
  },
  dawn: {
    label: "Dawn: 30 minutes before the alarm, rising to 300 lux at the eye (spec 00-002).",
    animated: () => state.dawnPlaying && state.dawnMinutes < 30,
    environment: 0.01,
    update() {
      const p = state.dawnMinutes / 30;
      const lux = 300 * Math.pow(p, 2.2);
      const lumens = lux / LUX_PER_LUMEN_AT_EYE;
      const colour = kelvin(1800 + 2200 * Math.pow(p, 0.8));
      setLamp("L", lumens, colour);
      setLamp("R", lumens, colour);
      setHalo(0, AMBER);
      const dayK = Math.max(0, (p - 0.75) / 0.25);
      setWindow(NIGHT_SKY.clone().lerp(new THREE.Color(0x6f86b8), dayK), new THREE.Color(0xb8c8ff), 0.05 + 8 * dayK, 0.004 + 0.4 * dayK);
      return { lumens: lumens * 2, lux: Math.max(NIGHT_ADAPTATION_LUX, lux) };
    },
    status: () => {
      const p = state.dawnMinutes / 30;
      const lux = 300 * Math.pow(p, 2.2);
      const alarm = { active: " · <strong>alarm ringing</strong>", dismissed: " · alarm stopped from the remote" }[state.alarm] ?? "";
      return `<strong>${state.dawnMinutes.toFixed(1)} min</strong> · ${lux.toFixed(0)} lux at the eye · ${Math.round(1800 + 2200 * Math.pow(p, 0.8))} K${alarm}`;
    },
  },
  readingLeft: {
    label: "Reading, left side: warm white at full power, the other pillow stays dark.",
    environment: 0.02,
    update() {
      setLamp("L", LAMP_LM, kelvin(2700));
      setLamp("R", 0, kelvin(2700));
      setHalo(0, AMBER);
      darkWindow();
      return { lumens: LAMP_LM, lux: READING_LUX };
    },
  },
  readingRight: {
    label: "Reading, right side.",
    environment: 0.02,
    update() {
      setLamp("L", 0, kelvin(2700));
      setLamp("R", LAMP_LM, kelvin(2700));
      setHalo(0, AMBER);
      darkWindow();
      return { lumens: LAMP_LM, lux: READING_LUX };
    },
  },
  day: {
    label: "Day: daylight through the window.",
    environment: 0.15,
    update() {
      lampsOff();
      setHalo(0, AMBER);
      setWindow(new THREE.Color(0xcfe3ff), new THREE.Color(0xfff1dc), 250, 22);
      return { lumens: 400, lux: 220 };
    },
  },
};

// ---------------------------------------------------------------------------
// Camera views.

const VIEWS = {
  room: { position: [1.25, 1.6, 4.1], target: [0, 0.95, 0.75] },
  pillow: { position: [PILLOW_X - 0.05, EAR_HEIGHT + 0.08, PILLOW_Z + 0.35], target: [0.05, CEILING - 0.3, 0.75] },
  bar: { position: [0.55, 0.85, 1.25], target: [0.15, BAR_Y + 0.05, 0.08] },
  decor: { position: [1.75, 1.55, 4.35], target: [-0.9, 1.05, 1.9] },
};

// Render on demand: static scenes are drawn again only when something changes
// (camera, scene, size). The camera moves at a lower resolution and snaps
// back to full resolution as soon as it stops.
let dirty = true;
const invalidate = () => (dirty = true);
controls.addEventListener("change", invalidate);
const FULL_PIXEL_RATIO = Math.min(window.devicePixelRatio, 2);
function setPixelRatio(ratio) {
  if (renderer.getPixelRatio() === ratio) return;
  renderer.setPixelRatio(ratio);
  composer.setPixelRatio(ratio);
}
let idle;
controls.addEventListener("start", () => {
  clearTimeout(idle);
  setPixelRatio(1);
});
controls.addEventListener("end", () => {
  idle = setTimeout(() => {
    setPixelRatio(FULL_PIXEL_RATIO);
    invalidate();
  }, 300);
});

function setView(name) {
  const view = VIEWS[name];
  camera.position.set(...view.position);
  controls.target.set(...view.target);
  controls.update();
  invalidate();
  document.querySelectorAll("[data-view]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.view === name)));
}

function setScene(name) {
  state.scene = name;
  state.started = performance.now();
  if (name === "dawn") state.dawnMinutes = 0;
  state.alarm = "none";
  invalidate();
  scene.environmentIntensity = SCENES[name].environment;
  document.querySelectorAll("[data-scene]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.scene === name)));
  document.getElementById("dawn-row").hidden = name !== "dawn";
}

// H hides the controls, for clean demos and recordings.
window.addEventListener("keydown", (e) => {
  if (e.key === "h" || e.key === "H") {
    const panel = document.querySelector(".panel");
    panel.hidden = !panel.hidden;
    document.getElementById("keyhint").hidden = !panel.hidden;
  }
});
document.getElementById("scenes").addEventListener("click", (e) => e.target.dataset.scene && setScene(e.target.dataset.scene));
document.getElementById("views").addEventListener("click", (e) => e.target.dataset.view && setView(e.target.dataset.view));
const dawnTime = document.getElementById("dawn-time");
dawnTime.addEventListener("input", () => {
  state.dawnMinutes = Number(dawnTime.value);
  invalidate();
});
const dawnPlay = document.getElementById("dawn-play");
dawnPlay.addEventListener("click", () => {
  state.dawnPlaying = !state.dawnPlaying;
  dawnPlay.textContent = state.dawnPlaying ? "Pause" : "Play";
  dawnPlay.setAttribute("aria-pressed", String(state.dawnPlaying));
});

// The URL can pick a scene and a view, e.g. ?scene=breathing&view=pillow.
const query = new URLSearchParams(location.search);
setScene(SCENES[query.get("scene")] ? query.get("scene") : "breathing");
if (query.has("minutes")) {
  state.dawnMinutes = Number(query.get("minutes"));
  state.dawnPlaying = false;
  dawnPlay.textContent = "Play";
  dawnPlay.setAttribute("aria-pressed", "false");
}
setView(VIEWS[query.get("view")] ? query.get("view") : "room");

// ---------------------------------------------------------------------------
// Loop.

const DAWN_SPEED = 30; // the 30-minute dawn plays in one minute
const statusEl = document.getElementById("status");
let last = performance.now();

function frame(now) {
  const dt = (now - last) / 1000;
  last = now;
  const t = (now - state.started) / 1000;
  if (state.scene === "dawn" && state.dawnPlaying) {
    state.dawnMinutes = Math.min(30, state.dawnMinutes + (dt * DAWN_SPEED) / 60);
  }
  // The wake time is the end of the 30-minute dawn.
  if (state.scene === "dawn" && state.dawnMinutes >= 30 && state.alarm === "none") state.alarm = "active";
  if (state.scene === "dawn" && state.dawnMinutes < 30) state.alarm = "none";
  if (state.scene === "dawn" && document.activeElement !== dawnTime) dawnTime.value = state.dawnMinutes;
  const scene_ = SCENES[state.scene];
  const { lumens, lux } = scene_.update(t);
  // Eye adaptation: a white surface at the reference illuminance lands in the
  // upper mid-tones. Bounce: light reflected by the walls and bedding.
  renderer.toneMappingExposure = 6 / lux;
  // Bloom works on scene radiance before exposure: only what is several
  // times brighter than a white wall at the reference light blooms.
  bloom.threshold = 1.6 / renderer.toneMappingExposure;
  glowGain = 1 / renderer.toneMappingExposure;
  bounce.intensity = lumens * 0.025;
  statusEl.innerHTML = scene_.label + (scene_.status ? ` · ${scene_.status(t)}` : "");
  controls.update();
  if (dirty || scene_.animated?.()) {
    composer.render();
    dirty = false;
    if (window.robineRoom) window.robineRoom.frames++;
  }
  requestAnimationFrame(frame);
}

window.addEventListener("resize", () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  composer.setSize(window.innerWidth, window.innerHeight);
  invalidate();
});

// Bedside remote (emulated ESP32). During the dawn its clock runs from 06:30
// to the 07:00 alarm; otherwise it shows the real time.
mountRemote(document.getElementById("remote"), {
  alarmActive: () => state.alarm === "active",
  press() {
    if (state.alarm !== "active") return "idle";
    state.alarm = "dismissed";
    invalidate();
    return "dismissed";
  },
  clock() {
    const now = new Date();
    const minutes = state.scene === "dawn" ? 6 * 60 + 30 + Math.floor(state.dawnMinutes) : now.getHours() * 60 + now.getMinutes();
    return `${String(Math.floor(minutes / 60) % 24).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
  },
});

renderer.shadowMap.needsUpdate = true; // the one and only shadow pass
document.getElementById("loading").remove();
// Console access for debugging and performance checks.
window.robineRoom = { renderer, scene, camera, readyMs: performance.now(), frames: 0 };
requestAnimationFrame(frame);
