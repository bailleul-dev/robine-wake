// Bedroom decor: a calm, warm Japandi room that echoes the bar's navy blue
// and the terracotta throw. Everything is procedural (geometry and canvas
// textures), like the rest of the room.

import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";

const PALETTE = {
  cream: "#efe6d6",
  sand: "#d8c6a8",
  terracotta: "#b5623f",
  ochre: "#c99a3c",
  navy: "#1d2b52",
  olive: "#6f7a4a",
  ink: "#2a2622",
};

export function addDecor({ add, canvasTexture, noiseField, M, room, window: win, mattressTop, pillowX, pillowZ }) {
  const mat = {
    boucle: new THREE.MeshPhysicalMaterial({ color: 0xe9e1d3, roughness: 1, sheen: 1, sheenColor: 0xffffff, sheenRoughness: 0.8 }),
    cushionTerracotta: new THREE.MeshPhysicalMaterial({ color: 0xa9563a, roughness: 1, sheen: 0.8, sheenColor: 0xffc9ad, normalMap: M.sheet.normalMap }),
    cushionOchre: new THREE.MeshPhysicalMaterial({ color: 0xc4943a, roughness: 1, sheen: 0.8, sheenColor: 0xffe2a8, normalMap: M.sheet.normalMap }),
    cushionNavy: new THREE.MeshPhysicalMaterial({ color: 0x23325c, roughness: 1, sheen: 0.7, sheenColor: 0x9fb0e0, normalMap: M.sheet.normalMap }),
    terracottaPot: new THREE.MeshStandardMaterial({ color: 0xa25a3c, roughness: 0.9 }),
    stoneware: new THREE.MeshPhysicalMaterial({ color: 0xe8e1d4, roughness: 0.55, clearcoat: 0.4, clearcoatRoughness: 0.3 }),
    stonewareDark: new THREE.MeshPhysicalMaterial({ color: 0x3b3833, roughness: 0.6, clearcoat: 0.3 }),
    bark: new THREE.MeshStandardMaterial({ color: 0x5b4a3a, roughness: 1 }),
    leaf: new THREE.MeshPhysicalMaterial({ color: 0x7d8a5a, roughness: 0.7, side: THREE.DoubleSide, sheen: 0.4, sheenColor: 0xd6e0b8 }),
    soil: new THREE.MeshStandardMaterial({ color: 0x2e241c, roughness: 1 }),
    pampas: new THREE.MeshPhysicalMaterial({ color: 0xe6d7b8, roughness: 1, sheen: 1, sheenColor: 0xfff6e0 }),
    stem: new THREE.MeshStandardMaterial({ color: 0xb59c74, roughness: 0.9 }),
    oak: new THREE.MeshPhysicalMaterial({ color: 0xc49a6c, roughness: 0.55, clearcoat: 0.2 }),
    // Thin glass as a transparent, glossy surface: transmission would add a
    // full extra render of the room per frame for two small objects.
    glass: new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.05, transparent: true, opacity: 0.18, clearcoat: 1, ior: 1.5 }),
    paper: new THREE.MeshStandardMaterial({ color: 0xf2ece1, roughness: 0.9 }),
  };

  // --- Patterned Berber rug under the bed --------------------------------
  {
    const texture = canvasTexture(1024, (ctx, size) => {
      ctx.fillStyle = PALETTE.cream;
      ctx.fillRect(0, 0, size, size);
      const fleck = noiseField(size, 128, 41);
      const img = ctx.getImageData(0, 0, size, size);
      for (let i = 0; i < size * size; i++) {
        const v = (fleck(i % size, (i / size) | 0) - 0.5) * 22;
        img.data[i * 4] += v;
        img.data[i * 4 + 1] += v;
        img.data[i * 4 + 2] += v;
      }
      ctx.putImageData(img, 0, 0);
      // Irregular hand-drawn diamonds in ink, as on a Beni Ouarain rug.
      ctx.strokeStyle = "rgba(42,38,34,0.85)";
      ctx.lineWidth = 7;
      ctx.lineCap = "round";
      const step = size / 4;
      for (let i = -1; i < 5; i++) {
        ctx.beginPath();
        for (let y = 0; y <= size; y += step / 2) {
          const x = i * step + ((y / (step / 2)) % 2 ? step / 2 : 0) + Math.sin(y * 0.05 + i) * 6;
          y === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
      ctx.fillStyle = PALETTE.ink;
      for (let i = 0; i < 4; i++) for (let j = 0; j < 8; j++) ctx.fillRect(i * step + step / 2 - 6, j * (step / 2) + step / 4 - 6, 12, 12);
    });
    const rug = add(
      new THREE.Mesh(new RoundedBoxGeometry(2.4, 0.014, 3.0, 2, 0.007), new THREE.MeshPhysicalMaterial({ map: texture, roughness: 1, sheen: 1, sheenColor: 0xffffff })),
      { cast: false }
    );
    rug.position.set(0, 0.007, 1.75);
  }

  // --- Cushions in front of the pillows ----------------------------------
  function cushion(width, height, material, position, tilt, turn) {
    const g = new RoundedBoxGeometry(width, height, 0.13, 8, 0.06);
    const q = g.attributes.position;
    for (let i = 0; i < q.count; i++) {
      const px = q.getX(i) / (width / 2), py = q.getY(i) / (height / 2);
      q.setZ(i, q.getZ(i) * (1 - 0.5 * Math.min(1, px * px * 0.7 + py * py * 0.7)));
    }
    g.computeVertexNormals();
    const mesh = add(new THREE.Mesh(g, material));
    mesh.position.set(...position);
    mesh.rotation.set(tilt, turn, 0);
    return mesh;
  }
  // Laid almost flat in front of the pillows, so they never hide the light
  // falling on the pillows.
  const flat = -Math.PI / 2 + 0.12;
  cushion(0.45, 0.45, mat.cushionTerracotta, [-pillowX + 0.08, mattressTop + 0.07, pillowZ + 0.42], flat, 0.15);
  cushion(0.45, 0.45, mat.cushionOchre, [pillowX - 0.06, mattressTop + 0.07, pillowZ + 0.42], flat, -0.12);
  cushion(0.5, 0.3, mat.cushionNavy, [0.02, mattressTop + 0.1, pillowZ + 0.5], flat, 0.05);

  // --- Olive tree in a terracotta pot, between the bed and the window ----
  {
    const base = new THREE.Vector3(room.x1 - 0.42, 0, win.z0 - 0.75);
    const potShape = new THREE.LatheGeometry(
      [[0, 0], [0.15, 0], [0.19, 0.04], [0.21, 0.36], [0.225, 0.4], [0.2, 0.4], [0.19, 0.37], [0, 0.37]].map(([x, y]) => new THREE.Vector2(x, y)),
      48
    );
    const pot = add(new THREE.Mesh(potShape, mat.terracottaPot));
    pot.position.copy(base);
    const soil = add(new THREE.Mesh(new THREE.CircleGeometry(0.19, 32), mat.soil), { cast: false });
    soil.rotation.x = -Math.PI / 2;
    soil.position.copy(base).add(new THREE.Vector3(0, 0.37, 0));

    // Trunk and branches as tapered tubes along gentle curves.
    const rng = mulberry(7);
    const branchTips = [];
    function limb(start, direction, length, radius, depth) {
      const end = start.clone().addScaledVector(direction, length);
      const mid = start.clone().lerp(end, 0.5).add(new THREE.Vector3((rng() - 0.5) * 0.08, 0, (rng() - 0.5) * 0.08));
      const curve = new THREE.CatmullRomCurve3([start, mid, end]);
      const tube = new THREE.TubeGeometry(curve, 12, radius, 8, false);
      add(new THREE.Mesh(tube, mat.bark));
      if (depth === 0) {
        branchTips.push(end);
        return;
      }
      const children = depth === 2 ? 3 : 2;
      for (let i = 0; i < children; i++) {
        const angle = (i / children) * Math.PI * 2 + rng() * 1.2;
        const spread = 0.45 + rng() * 0.3;
        const dir = new THREE.Vector3(Math.cos(angle) * spread, 1, Math.sin(angle) * spread).normalize();
        limb(end, dir, length * (0.6 + rng() * 0.15), radius * 0.62, depth - 1);
      }
    }
    limb(base.clone().add(new THREE.Vector3(0, 0.35, 0)), new THREE.Vector3(0.05, 1, 0).normalize(), 0.5, 0.03, 2);

    // Narrow olive leaves, instanced around each branch tip.
    const leafShape = new THREE.Shape();
    leafShape.moveTo(0, 0).quadraticCurveTo(0.012, 0.03, 0, 0.065).quadraticCurveTo(-0.012, 0.03, 0, 0);
    const leafGeo = new THREE.ShapeGeometry(leafShape, 4);
    const perTip = 220;
    const leaves = new THREE.InstancedMesh(leafGeo, mat.leaf, branchTips.length * perTip);
    const dummy = new THREE.Object3D();
    const tint = new THREE.Color();
    let n = 0;
    for (const tip of branchTips) {
      for (let i = 0; i < perTip; i++) {
        const r = 0.03 + Math.pow(rng(), 0.7) * 0.24;
        const theta = rng() * Math.PI * 2, phi = Math.acos(2 * rng() - 1);
        dummy.position.set(tip.x + r * Math.sin(phi) * Math.cos(theta), tip.y + r * Math.cos(phi) * 0.7, tip.z + r * Math.sin(phi) * Math.sin(theta));
        dummy.rotation.set(rng() * Math.PI, rng() * Math.PI * 2, rng() * Math.PI);
        dummy.scale.setScalar(1.0 + rng() * 0.6);
        dummy.updateMatrix();
        leaves.setMatrixAt(n, dummy.matrix);
        // Silvery underside or deeper green, at random.
        leaves.setColorAt(n, tint.setHSL(0.2 + rng() * 0.04, 0.18 + rng() * 0.12, 0.38 + rng() * 0.16));
        n++;
      }
    }
    leaves.castShadow = leaves.receiveShadow = true;
    add(leaves);
  }

  // --- Reading corner: bouclé armchair, side table, plant -----------------
  {
    const corner = new THREE.Group();
    corner.position.set(room.x0 + 0.75, 0, room.z1 - 0.7);
    corner.rotation.y = 2.55; // turned toward the bed and the window
    add(corner);
    const part = (geometry, material, position, rotation = [0, 0, 0]) => {
      const mesh = new THREE.Mesh(geometry, material);
      mesh.position.set(...position);
      mesh.rotation.set(...rotation);
      mesh.castShadow = mesh.receiveShadow = true;
      corner.add(mesh);
      return mesh;
    };
    // Low lounge chair: oak sled base, soft bouclé seat and back.
    for (const x of [-0.33, 0.33]) {
      part(new RoundedBoxGeometry(0.04, 0.04, 0.78, 2, 0.015), mat.oak, [x, 0.02, 0]);
      part(new RoundedBoxGeometry(0.04, 0.42, 0.04, 2, 0.015), mat.oak, [x, 0.22, 0.3]);
      part(new RoundedBoxGeometry(0.04, 0.42, 0.04, 2, 0.015), mat.oak, [x, 0.22, -0.3]);
      part(new RoundedBoxGeometry(0.06, 0.04, 0.66, 2, 0.018), mat.oak, [x, 0.56, 0.02]);
    }
    part(new RoundedBoxGeometry(0.62, 0.16, 0.6, 6, 0.07), mat.boucle, [0, 0.36, 0.05]);
    part(new RoundedBoxGeometry(0.62, 0.48, 0.16, 6, 0.07), mat.boucle, [0, 0.62, -0.26], [-0.22, 0, 0]);
    part(new RoundedBoxGeometry(0.3, 0.3, 0.1, 6, 0.045), mat.cushionTerracotta, [0.12, 0.55, -0.12], [-0.3, 0.2, 0.1]);

    // Side table with a stack of books, a mug and a small trailing plant.
    part(new THREE.CylinderGeometry(0.21, 0.21, 0.025, 48), mat.oak, [0.62, 0.5, 0.05]);
    part(new THREE.CylinderGeometry(0.02, 0.03, 0.49, 16), mat.oak, [0.62, 0.245, 0.05]);
    part(new THREE.CylinderGeometry(0.16, 0.17, 0.02, 32), mat.oak, [0.62, 0.01, 0.05]);
    const bookColours = [0x2d3a5f, 0xc9b98f, 0x8b3d2c];
    bookColours.forEach((c, i) => {
      part(new RoundedBoxGeometry(0.17, 0.028, 0.23, 2, 0.004), new THREE.MeshStandardMaterial({ color: c, roughness: 0.8 }), [0.6, 0.527 + i * 0.029, 0.05], [0, 0.25 * (i - 1), 0]);
    });
    part(new THREE.CylinderGeometry(0.04, 0.035, 0.09, 24), mat.stonewareDark, [0.7, 0.557, -0.08]);
  }

  // --- Dresser on the left wall, with ceramics and dried pampas ----------
  {
    const x = room.x0 + 0.24, z = 2.75;
    const body = add(new THREE.Mesh(new RoundedBoxGeometry(0.45, 0.78, 1.3, 4, 0.012), M.walnut));
    body.position.set(x, 0.42, z);
    for (const dz of [-0.33, 0, 0.33]) {
      // Drawer fronts with a recessed line and a small oak pull.
      const pull = add(new THREE.Mesh(new RoundedBoxGeometry(0.02, 0.02, 0.12, 2, 0.008), mat.oak));
      pull.position.set(x + 0.23, 0.62, z + dz);
    }
    for (const [lx, lz] of [[-0.18, -0.6], [0.18, -0.6], [-0.18, 0.6], [0.18, 0.6]]) {
      const leg = add(new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.014, 0.04), M.walnut));
      leg.position.set(x + lx, 0.02, z + lz);
    }
    const top = 0.81;
    // Tall stoneware vase with pampas plumes.
    const vase = add(new THREE.Mesh(
      new THREE.LatheGeometry([[0, 0], [0.06, 0], [0.085, 0.08], [0.09, 0.16], [0.06, 0.26], [0.035, 0.32], [0.04, 0.34], [0, 0.34]].map(([a, b]) => new THREE.Vector2(a, b)), 48),
      mat.stoneware
    ));
    vase.position.set(x + 0.02, top, z + 0.42);
    const rng = mulberry(19);
    for (let i = 0; i < 7; i++) {
      const lean = new THREE.Vector3((rng() - 0.5) * 0.5, 1, (rng() - 0.5) * 0.5).normalize();
      const start = new THREE.Vector3(x + 0.02, top + 0.3, z + 0.42);
      const length = 0.55 + rng() * 0.25;
      const end = start.clone().addScaledVector(lean, length);
      add(new THREE.Mesh(new THREE.TubeGeometry(new THREE.LineCurve3(start, end), 2, 0.003, 5), mat.stem));
      const plume = add(new THREE.Mesh(new THREE.CapsuleGeometry(0.03, 0.2, 6, 12), mat.pampas));
      plume.position.copy(end).addScaledVector(lean, 0.1);
      plume.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), lean);
      plume.scale.set(1, 1, 0.7);
    }
    // Two small bowls and a stack of art books.
    const bowl = add(new THREE.Mesh(new THREE.SphereGeometry(0.07, 32, 16, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), mat.stonewareDark));
    bowl.position.set(x, top + 0.07, z - 0.1);
    bowl.rotation.x = Math.PI;
    const bowl2 = add(new THREE.Mesh(new THREE.SphereGeometry(0.045, 32, 16, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), mat.stoneware));
    bowl2.position.set(x + 0.05, top + 0.045, z + 0.05);
    bowl2.rotation.x = Math.PI;
    [0x1d2b52, 0xd9c7a2].forEach((c, i) => {
      const book = add(new THREE.Mesh(new RoundedBoxGeometry(0.24, 0.035, 0.3, 2, 0.004), new THREE.MeshStandardMaterial({ color: c, roughness: 0.8 })));
      book.position.set(x - 0.02, top + 0.018 + i * 0.036, z - 0.42);
      book.rotation.y = 0.1 * (i ? -1 : 1);
    });

    // Framed abstract print above the dresser: arches and a sun in the
    // palette of the room.
    const print = canvasTexture(1024, (ctx, size) => {
      ctx.fillStyle = PALETTE.cream;
      ctx.fillRect(0, 0, size, size);
      const arch = (cx, w, h, colour) => {
        ctx.fillStyle = colour;
        ctx.beginPath();
        ctx.moveTo(cx - w / 2, size * 0.86);
        ctx.lineTo(cx - w / 2, size * 0.86 - h + w / 2);
        ctx.arc(cx, size * 0.86 - h + w / 2, w / 2, Math.PI, 0);
        ctx.lineTo(cx + w / 2, size * 0.86);
        ctx.fill();
      };
      arch(size * 0.36, size * 0.34, size * 0.58, PALETTE.terracotta);
      arch(size * 0.6, size * 0.26, size * 0.42, PALETTE.navy);
      ctx.fillStyle = PALETTE.ochre;
      ctx.beginPath();
      ctx.arc(size * 0.7, size * 0.3, size * 0.1, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = PALETTE.sand;
      ctx.fillRect(size * 0.14, size * 0.86, size * 0.72, size * 0.025);
      // Paper grain.
      const grain = noiseField(size, 256, 77);
      const img = ctx.getImageData(0, 0, size, size);
      for (let i = 0; i < size * size; i++) {
        const v = (grain(i % size, (i / size) | 0) - 0.5) * 14;
        img.data[i * 4] += v;
        img.data[i * 4 + 1] += v;
        img.data[i * 4 + 2] += v;
      }
      ctx.putImageData(img, 0, 0);
    });
    const frame = new THREE.Group();
    frame.position.set(room.x0 + 0.02, 1.6, z);
    frame.rotation.y = Math.PI / 2;
    add(frame);
    const outer = new THREE.Mesh(new RoundedBoxGeometry(0.74, 0.92, 0.03, 2, 0.004), mat.oak);
    outer.castShadow = true;
    const matBoard = new THREE.Mesh(new THREE.PlaneGeometry(0.66, 0.84), mat.paper);
    matBoard.position.z = 0.0155;
    const art = new THREE.Mesh(new THREE.PlaneGeometry(0.5, 0.66), new THREE.MeshStandardMaterial({ map: print, roughness: 0.85 }));
    art.position.z = 0.016;
    const glass = new THREE.Mesh(new THREE.PlaneGeometry(0.66, 0.84), new THREE.MeshPhysicalMaterial({ roughness: 0.02, transparent: true, opacity: 0.08, clearcoat: 1 }));
    glass.position.z = 0.017;
    frame.add(outer, matBoard, art, glass);
  }

  // --- Floating shelf with books, above the nightstand on the viewer's left
  {
    const shelfX = -1.25, shelfY = 1.32, depth = 0.2;
    const shelf = add(new THREE.Mesh(new RoundedBoxGeometry(0.72, 0.03, depth, 2, 0.006), mat.oak));
    shelf.position.set(shelfX, shelfY, depth / 2);
    const top = shelfY + 0.015;
    const rng = mulberry(31);
    const spines = [0x1d2b52, 0xb5623f, 0xd9c7a2, 0x6f7a4a, 0xefe6d6, 0x2a2622, 0xc99a3c, 0x8b3d2c, 0x3d4f7a, 0xe0d2b8];
    // Upright row from the left end, the last book leaning on the others.
    let x = shelfX - 0.33;
    for (let i = 0; i < 11; i++) {
      const w = 0.018 + rng() * 0.022, h = 0.17 + rng() * 0.07, d = 0.13 + rng() * 0.04;
      const book = add(new THREE.Mesh(
        new RoundedBoxGeometry(w, h, d, 2, 0.002),
        new THREE.MeshStandardMaterial({ color: spines[i % spines.length], roughness: 0.75 })
      ));
      book.position.set(x + w / 2, top + h / 2, d / 2 + 0.02);
      x += w + 0.002;
      if (i === 10) {
        book.rotation.z = -0.32;
        book.position.x += 0.035;
        book.position.y -= 0.012;
      }
    }
    // A short stack lying flat, a small stoneware pot on top.
    [0xd9c7a2, 0x1d2b52, 0xb5623f].forEach((c, i) => {
      const b = add(new THREE.Mesh(new RoundedBoxGeometry(0.2, 0.03, 0.15, 2, 0.003), new THREE.MeshStandardMaterial({ color: c, roughness: 0.8 })));
      b.position.set(shelfX + 0.2, top + 0.015 + i * 0.031, 0.1);
      b.rotation.y = 0.08 * (i - 1);
    });
    const pot = add(new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.03, 0.06, 32), mat.stonewareDark));
    pot.position.set(shelfX + 0.2, top + 0.093 + 0.03, 0.1);
    const sprigs = add(new THREE.Mesh(new THREE.SphereGeometry(0.045, 16, 12), mat.leaf));
    sprigs.position.set(shelfX + 0.2, top + 0.17, 0.1);
    sprigs.scale.set(1, 0.7, 1);
  }

  // --- Small framed print above the nightstand on the viewer's right ----
  {
    const moon = canvasTexture(512, (ctx, size) => {
      ctx.fillStyle = PALETTE.navy;
      ctx.fillRect(0, 0, size, size);
      const rng = mulberry(53);
      ctx.fillStyle = "rgba(239,230,214,0.8)";
      for (let i = 0; i < 40; i++) ctx.fillRect(rng() * size, rng() * size, 2 + rng() * 2, 2 + rng() * 2);
      // Crescent: a cream disc with a navy disc taken out of it.
      ctx.fillStyle = PALETTE.cream;
      ctx.beginPath();
      ctx.arc(size * 0.5, size * 0.45, size * 0.2, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = PALETTE.navy;
      ctx.beginPath();
      ctx.arc(size * 0.58, size * 0.4, size * 0.18, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = PALETTE.ochre;
      ctx.fillRect(size * 0.3, size * 0.8, size * 0.4, 3);
    });
    const frame = new THREE.Group();
    frame.position.set(1.22, 1.4, 0.012);
    add(frame);
    const outer = new THREE.Mesh(new RoundedBoxGeometry(0.26, 0.32, 0.022, 2, 0.003), mat.oak);
    outer.castShadow = true;
    const matBoard = new THREE.Mesh(new THREE.PlaneGeometry(0.22, 0.28), mat.paper);
    matBoard.position.z = 0.0115;
    const art = new THREE.Mesh(new THREE.PlaneGeometry(0.15, 0.2), new THREE.MeshStandardMaterial({ map: moon, roughness: 0.85 }));
    art.position.z = 0.012;
    frame.add(outer, matBoard, art);
  }

  // --- Nightstand still lifes -------------------------------------------
  {
    const top = 0.45;
    // Left (viewer's right): carafe and glass of water, small vase with a sprig.
    const carafe = add(new THREE.Mesh(
      new THREE.LatheGeometry([[0, 0], [0.045, 0], [0.05, 0.1], [0.03, 0.17], [0.022, 0.22], [0.024, 0.23], [0, 0.23]].map(([a, b]) => new THREE.Vector2(a, b)), 40),
      mat.glass
    ));
    carafe.position.set(1.3, top, 0.12);
    const glassCup = add(new THREE.Mesh(new THREE.CylinderGeometry(0.032, 0.028, 0.09, 32, 1, true), mat.glass));
    glassCup.position.set(1.36, top + 0.045, 0.28);
    // Right (viewer's left): stoneware bud vase with a sprig of olive.
    const bud = add(new THREE.Mesh(
      new THREE.LatheGeometry([[0, 0], [0.04, 0], [0.05, 0.05], [0.035, 0.11], [0.015, 0.14], [0.018, 0.15], [0, 0.15]].map(([a, b]) => new THREE.Vector2(a, b)), 40),
      mat.stoneware
    ));
    bud.position.set(-1.28, top, 0.15);
    const sprig = add(new THREE.Mesh(new THREE.TubeGeometry(new THREE.QuadraticBezierCurve3(
      new THREE.Vector3(-1.28, top + 0.14, 0.15), new THREE.Vector3(-1.26, top + 0.3, 0.2), new THREE.Vector3(-1.18, top + 0.38, 0.25)
    ), 10, 0.002, 5), mat.stem));
    sprig.castShadow = true;
    const books = [0xd9c7a2, 0x6f7a4a];
    books.forEach((c, i) => {
      const b = add(new THREE.Mesh(new RoundedBoxGeometry(0.15, 0.025, 0.21, 2, 0.004), new THREE.MeshStandardMaterial({ color: c, roughness: 0.8 })));
      b.position.set(-1.2, top + 0.013 + i * 0.026, 0.3);
      b.rotation.y = -0.2 + i * 0.25;
    });
  }
}

function mulberry(seed) {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
