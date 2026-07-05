// ══════════════════════════════════════════════════════════════════════════
//  Редактор зала — canvas, vanilla JS.
//  Editor.open(container, { layout, mode, onSave, title }) — открыть редактор.
//  mode: 'venue' (шаблон) | 'event' (схема мероприятия)
// ══════════════════════════════════════════════════════════════════════════
const Editor = (() => {
  const SEAT = 36;                       // фикс. размер кресла (px в мире)
  const DEFAULT_COLOR = '#6C63FF';
  const SEAT_TYPES = ['Standard', 'VIP', 'Sofa', 'Standing', 'Disabled'];
  const TYPE_RU = { Standard: 'Стандарт', VIP: 'VIP', Sofa: 'Диван', Standing: 'Стоячее', Disabled: 'Инвалид' };

  const rad = (d) => d * Math.PI / 180;
  const uid = () => 'tmp-' + Math.random().toString(36).slice(2, 10);

  let S = null;   // состояние редактора

  // ── Пересчёт абсолютных координат кресел из локальных (с учётом поворота) ──
  function applyBlockTransform(block) {
    const a = rad(block.rotationDeg || 0);
    const cos = Math.cos(a), sin = Math.sin(a);
    for (const s of block.seats) {
      s.x = block.x + s.lx * cos - s.ly * sin;
      s.y = block.y + s.lx * sin + s.ly * cos;
    }
  }

  // Восстановить lx/ly из абсолютных (при загрузке с сервера)
  function deriveLocal(block) {
    const a = rad(block.rotationDeg || 0);
    const cos = Math.cos(-a), sin = Math.sin(-a);
    for (const s of block.seats) {
      const dx = s.x - block.x, dy = s.y - block.y;
      s.lx = dx * cos - dy * sin;
      s.ly = dx * sin + dy * cos;
    }
  }

  // ── Создание блока: сетка rows×cols, кресла 36px, промежутки gapX/gapY ──
  function buildBlockSeats(block) {
    const { rows, seatsPerRow: cols, gapX, gapY } = block;
    const w = cols * SEAT + (cols - 1) * gapX;
    const h = rows * SEAT + (rows - 1) * gapY;
    block.seats = [];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const lx = -w / 2 + SEAT / 2 + c * (SEAT + gapX);
        const ly = -h / 2 + SEAT / 2 + r * (SEAT + gapY);
        block.seats.push({
          id: uid(), row: r + 1, number: c + 1,
          seatType: block.seatType, price: block.defaultPrice,
          description: block.defaultDescription, color: block.defaultColor,
          lx, ly, x: 0, y: 0, isActive: true,
        });
      }
    }
    applyBlockTransform(block);
  }

  // ── Сквозная нумерация по этажу (как на бэкенде) ──
  function renumberFloor(floor) {
    const band = 24;
    const active = [];
    for (const b of floor.blocks) for (const s of b.seats) if (s.isActive) active.push(s);
    active.sort((a, b) => a.y - b.y);
    const rows = [];
    let baseline = -Infinity;
    for (const s of active) {
      if (rows.length === 0 || s.y - baseline > band) { rows.push([]); baseline = s.y; }
      rows[rows.length - 1].push(s);
    }
    let n = 1;
    rows.forEach((row, ri) => {
      row.sort((a, b) => a.x - b.x);
      for (const s of row) { s.row = ri + 1; s.number = n++; }
    });
  }

  // ── Координатные преобразования ──
  const cam = () => S.camera;
  function worldToScreen(x, y) {
    return { x: (x - cam().panX) * cam().zoom, y: (y - cam().panY) * cam().zoom };
  }
  function screenToWorld(x, y) {
    return { x: x / cam().zoom + cam().panX, y: y / cam().zoom + cam().panY };
  }

  const floor = () => S.floors[S.activeFloor];

  // ── Рендер ──────────────────────────────────────────────────────────
  function render() {
    const { ctx, canvas } = S;
    const W = canvas.clientWidth, H = canvas.clientHeight;
    const dpr = window.devicePixelRatio || 1;
    if (canvas.width !== W * dpr || canvas.height !== H * dpr) {
      canvas.width = W * dpr; canvas.height = H * dpr;
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);

    // фон + сетка точек
    ctx.fillStyle = getVar('--canvas-bg');
    ctx.fillRect(0, 0, W, H);
    drawGrid(W, H);

    const f = floor();
    if (!f) return;

    // сцена
    if (f.stage) drawStage(f.stage);

    // блоки и кресла
    for (const b of f.blocks) {
      for (const s of b.seats) {
        if (!s.isActive) continue;
        drawSeat(s, b.rotationDeg);
      }
    }

    // выделение
    if (S.sel.type === 'block') {
      const b = f.blocks.find(x => x.id === S.sel.blockId);
      if (b) drawBlockSelection(b);
    }
    if (S.sel.type === 'seats') {
      for (const s of allSelectedSeats()) drawSeatOutline(s, b_rot(s), '#FF4FA3', 3);
    }

    // лассо
    if (S.drag && S.drag.kind === 'lasso') drawLasso(S.drag);
  }

  function b_rot(seat) {
    const b = floor().blocks.find(x => x.seats.includes(seat));
    return b ? b.rotationDeg : 0;
  }

  function drawGrid(W, H) {
    const { ctx } = S;
    const step = 32 * cam().zoom;
    if (step < 8) return;
    const start = screenToWorld(0, 0);
    const ox = ((-start.x % 32) * cam().zoom);
    const oy = ((-start.y % 32) * cam().zoom);
    ctx.fillStyle = getVar('--canvas-grid');
    for (let x = ox; x < W; x += step) {
      for (let y = oy; y < H; y += step) {
        ctx.beginPath(); ctx.arc(x, y, 1, 0, Math.PI * 2); ctx.fill();
      }
    }
  }

  function drawStage(stage) {
    const { ctx } = S;
    const p = worldToScreen(stage.x, stage.y);
    const w = stage.width * cam().zoom, h = stage.height * cam().zoom;
    ctx.save();
    ctx.fillStyle = getVar('--stage');
    roundRect(ctx, p.x - w / 2, p.y - h / 2, w, h, 10 * cam().zoom);
    ctx.fill();
    if (S.sel.type === 'stage') { ctx.strokeStyle = '#00D9FF'; ctx.lineWidth = 2; ctx.stroke(); }
    ctx.fillStyle = 'rgba(255,255,255,.85)';
    ctx.font = `700 ${Math.max(10, 14 * cam().zoom)}px Manrope, sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(stage.label || 'СЦЕНА', p.x, p.y);
    ctx.restore();
  }

  // Затемнение (f < 0) или осветление (f > 0) цвета кресла.
  function shade(hex, f) {
    let h = String(hex || DEFAULT_COLOR).replace('#', '');
    if (h.length === 3) h = h.split('').map(c => c + c).join('');
    const n = parseInt(h, 16);
    if (Number.isNaN(n)) return hex;
    let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    if (f < 0) { r *= 1 + f; g *= 1 + f; b *= 1 + f; }
    else { r += (255 - r) * f; g += (255 - g) * f; b += (255 - b) * f; }
    return `rgb(${r | 0},${g | 0},${b | 0})`;
  }

  function drawSeat(seat, rotationDeg) {
    const { ctx } = S;
    const p = worldToScreen(seat.x, seat.y);
    const z = cam().zoom;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(rad(rotationDeg || 0));

    const col = seat.color || DEFAULT_COLOR;
    const dark = shade(col, -0.28);   // подлокотники
    const darker = shade(col, -0.45); // спинка
    const glow = 'rgba(255,255,255,.18)'; // блик подушки

    const fillRR = (x, y, w, h, r, c) => { ctx.fillStyle = c; roundRect(ctx, x * z, y * z, w * z, h * z, r * z); ctx.fill(); };

    switch (seat.seatType) {
      case 'Standing': { // круг-«пятачок» с человечком
        ctx.fillStyle = dark;
        ctx.beginPath(); ctx.arc(0, 0, 16 * z, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = col;
        ctx.beginPath(); ctx.arc(0, 0, 13.5 * z, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = 'rgba(255,255,255,.92)';
        ctx.beginPath(); ctx.arc(0, -4.5 * z, 3 * z, 0, Math.PI * 2); ctx.fill();
        fillRR(-4, -0.5, 8, 8, 4, 'rgba(255,255,255,.92)');
        break;
      }
      case 'Sofa': { // диван: подлокотники + спинка + две подушки
        fillRR(-29, -10, 6, 24, 3, dark);
        fillRR(23, -10, 6, 24, 3, dark);
        fillRR(-24, -15, 48, 9, 4, darker);
        fillRR(-23, -7, 22.5, 20, 5, col);
        fillRR(0.5, -7, 22.5, 20, 5, col);
        fillRR(-21, -5, 18.5, 5, 2.5, glow);
        fillRR(2.5, -5, 18.5, 5, 2.5, glow);
        break;
      }
      case 'VIP': { // кресло с подлокотниками и золотой строчкой на спинке
        fillRR(-22, -8, 5, 20, 2.5, dark);
        fillRR(17, -8, 5, 20, 2.5, dark);
        fillRR(-17, -15, 34, 9, 4, darker);
        fillRR(-6, -12.5, 12, 3.5, 1.75, '#FFD166');
        fillRR(-16, -7, 32, 21, 5, col);
        fillRR(-13, -4.5, 26, 6, 3, glow);
        break;
      }
      case 'Disabled': { // место для инвалида: рамка + значок
        fillRR(-15, -15, 30, 30, 8, dark);
        fillRR(-13, -13, 26, 26, 6.5, col);
        ctx.fillStyle = 'rgba(255,255,255,.95)';
        ctx.font = `${Math.max(8, 17 * z)}px sans-serif`;
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText('♿', 0, 1 * z);
        break;
      }
      default: { // Standard: спинка + подушка + блик
        fillRR(-13, -14, 26, 8, 4, darker);
        fillRR(-14, -7, 28, 20, 5, col);
        fillRR(-11, -4.5, 22, 5.5, 2.75, glow);
      }
    }
    ctx.restore();
  }

  function drawSeatOutline(seat, rotationDeg, color, lw) {
    const { ctx } = S;
    const p = worldToScreen(seat.x, seat.y);
    const z = cam().zoom, half = (SEAT / 2) * z + 3;
    ctx.save();
    ctx.translate(p.x, p.y); ctx.rotate(rad(rotationDeg || 0));
    ctx.strokeStyle = color; ctx.lineWidth = lw;
    roundRect(ctx, -half, -half, half * 2, half * 2, 6); ctx.stroke();
    ctx.restore();
  }

  function blockBBox(b) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const s of b.seats) {
      if (!s.isActive) continue;
      minX = Math.min(minX, s.x); minY = Math.min(minY, s.y);
      maxX = Math.max(maxX, s.x); maxY = Math.max(maxY, s.y);
    }
    return { minX: minX - SEAT / 2, minY: minY - SEAT / 2, maxX: maxX + SEAT / 2, maxY: maxY + SEAT / 2 };
  }

  function drawBlockSelection(b) {
    const { ctx } = S;
    const bb = blockBBox(b);
    const p1 = worldToScreen(bb.minX, bb.minY), p2 = worldToScreen(bb.maxX, bb.maxY);
    ctx.save();
    ctx.strokeStyle = '#00A3FF'; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
    ctx.strokeRect(p1.x - 6, p1.y - 6, (p2.x - p1.x) + 12, (p2.y - p1.y) + 12);
    ctx.setLineDash([]);
    // ручка поворота
    const handle = worldToScreen((bb.minX + bb.maxX) / 2, bb.minY);
    const hy = handle.y - 28;
    ctx.strokeStyle = '#00A3FF'; ctx.beginPath();
    ctx.moveTo(handle.x, handle.y - 6); ctx.lineTo(handle.x, hy); ctx.stroke();
    ctx.fillStyle = '#00A3FF'; ctx.beginPath(); ctx.arc(handle.x, hy, 6, 0, Math.PI * 2); ctx.fill();
    S._rotHandle = { x: handle.x, y: hy };
    ctx.restore();
  }

  function drawLasso(d) {
    const { ctx } = S;
    const x = Math.min(d.x0, d.x1), y = Math.min(d.y0, d.y1);
    const w = Math.abs(d.x1 - d.x0), h = Math.abs(d.y1 - d.y0);
    ctx.save();
    ctx.fillStyle = 'rgba(0,163,255,0.12)'; ctx.strokeStyle = '#00A3FF'; ctx.lineWidth = 1;
    ctx.fillRect(x, y, w, h); ctx.strokeRect(x, y, w, h);
    ctx.restore();
  }

  function roundRect(ctx, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function getVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  // ── Хит-тесты ────────────────────────────────────────────────────────
  function seatAt(wx, wy) {
    const f = floor();
    for (let i = f.blocks.length - 1; i >= 0; i--) {
      const b = f.blocks[i];
      const a = rad(-(b.rotationDeg || 0));
      for (const s of b.seats) {
        if (!s.isActive) continue;
        const dx = wx - s.x, dy = wy - s.y;
        const lx = dx * Math.cos(a) - dy * Math.sin(a);
        const ly = dx * Math.sin(a) + dy * Math.cos(a);
        if (Math.abs(lx) <= SEAT / 2 && Math.abs(ly) <= SEAT / 2) return { block: b, seat: s };
      }
    }
    return null;
  }

  function stageAt(wx, wy) {
    const st = floor().stage;
    if (!st) return false;
    return Math.abs(wx - st.x) <= st.width / 2 && Math.abs(wy - st.y) <= st.height / 2;
  }

  function allSelectedSeats() {
    const f = floor();
    const out = [];
    for (const b of f.blocks) for (const s of b.seats) if (S.sel.seatIds.has(s.id)) out.push(s);
    return out;
  }

  // ── Ввод мыши ────────────────────────────────────────────────────────
  function bindInput() {
    const c = S.canvas;

    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (e.ctrlKey || e.metaKey) {
        zoomAt(e.offsetX, e.offsetY, e.deltaY < 0 ? 1.1 : 1 / 1.1);
      } else {
        cam().panX += e.deltaX / cam().zoom;
        cam().panY += e.deltaY / cam().zoom;
        render();
      }
    }, { passive: false });

    c.addEventListener('mousedown', onDown);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    window.addEventListener('keydown', (e) => { if (e.code === 'Space') S.space = true; });
    window.addEventListener('keyup', (e) => { if (e.code === 'Space') S.space = false; });
  }

  function zoomAt(sx, sy, factor) {
    const before = screenToWorld(sx, sy);
    cam().zoom = Math.max(0.2, Math.min(4, cam().zoom * factor));
    const after = screenToWorld(sx, sy);
    cam().panX += before.x - after.x;
    cam().panY += before.y - after.y;
    render();
  }

  function onDown(e) {
    const sx = e.offsetX, sy = e.offsetY;
    const w = screenToWorld(sx, sy);

    // Панорамирование: средняя кнопка или пробел
    if (e.button === 1 || S.space) {
      S.drag = { kind: 'pan', sx, sy, panX: cam().panX, panY: cam().panY };
      S.canvas.classList.add('panning');
      return;
    }
    if (e.button !== 0) return;

    // Режим добавления блока — рисуем превью
    if (S.tool === 'add') {
      S.drag = { kind: 'newblock', x0: sx, y0: sy, x1: sx, y1: sy };
      return;
    }

    // Ручка поворота выбранного блока
    if (S.sel.type === 'block' && S._rotHandle) {
      const dh = Math.hypot(sx - S._rotHandle.x, sy - S._rotHandle.y);
      if (dh <= 10) {
        const b = floor().blocks.find(x => x.id === S.sel.blockId);
        const bb = blockBBox(b);
        const center = { x: (bb.minX + bb.maxX) / 2, y: (bb.minY + bb.maxY) / 2 };
        S.drag = { kind: 'rotate', block: b, center };
        return;
      }
    }

    const hit = seatAt(w.x, w.y);

    // Двойной клик по сцене — переименовать
    if (!hit && stageAt(w.x, w.y)) {
      S.sel = { type: 'stage', blockId: null, seatIds: new Set() };
      S.drag = { kind: 'stage', sx, sy, ox: floor().stage.x, oy: floor().stage.y, moved: false };
      renderPanel(); render();
      return;
    }

    if (hit) {
      // если кликнули кресло, входящее в текущее выделение мест — двигать выделение? (упрощаем: выбираем блок)
      if (S.sel.type !== 'block' || S.sel.blockId !== hit.block.id) {
        S.sel = { type: 'block', blockId: hit.block.id, seatIds: new Set() };
        renderPanel();
      }
      S.drag = { kind: 'moveblock', block: hit.block, sx, sy, moved: false };
      render();
      return;
    }

    // Пустое место: если выбран блок — лассо по его креслам; иначе снять выделение/пан
    if (S.sel.type === 'block' || S.sel.type === 'seats') {
      S.drag = { kind: 'lasso', x0: sx, y0: sy, x1: sx, y1: sy };
    } else {
      S.drag = { kind: 'pan', sx, sy, panX: cam().panX, panY: cam().panY };
      S.canvas.classList.add('panning');
    }
  }

  function onMove(e) {
    if (!S || !S.drag) return;
    const rect = S.canvas.getBoundingClientRect();
    const sx = e.clientX - rect.left, sy = e.clientY - rect.top;
    const d = S.drag;

    if (d.kind === 'pan') {
      cam().panX = d.panX - (sx - d.sx) / cam().zoom;
      cam().panY = d.panY - (sy - d.sy) / cam().zoom;
      render();
    } else if (d.kind === 'newblock') {
      d.x1 = sx; d.y1 = sy;
      render(); drawPreviewRect(d);
    } else if (d.kind === 'moveblock') {
      const dxw = (sx - d.sx) / cam().zoom, dyw = (sy - d.sy) / cam().zoom;
      if (Math.abs(sx - d.sx) + Math.abs(sy - d.sy) > 3) d.moved = true;
      d.block.x += dxw; d.block.y += dyw;
      for (const s of d.block.seats) { s.x += dxw; s.y += dyw; }
      d.sx = sx; d.sy = sy;
      render();
    } else if (d.kind === 'stage') {
      const dxw = (sx - d.sx) / cam().zoom, dyw = (sy - d.sy) / cam().zoom;
      floor().stage.x = d.ox + dxw; floor().stage.y = d.oy + dyw;
      if (Math.abs(sx - d.sx) + Math.abs(sy - d.sy) > 3) d.moved = true;
      render();
    } else if (d.kind === 'rotate') {
      const cs = worldToScreen(d.center.x, d.center.y);
      const ang = Math.atan2(sy - cs.y, sx - cs.x) * 180 / Math.PI + 90;
      d.block.rotationDeg = Math.round(ang);
      applyBlockTransform(d.block);
      render(); renderPanel();
    } else if (d.kind === 'lasso') {
      d.x1 = sx; d.y1 = sy; render();
    }
  }

  function onUp() {
    if (!S || !S.drag) return;
    const d = S.drag;
    S.canvas.classList.remove('panning');

    if (d.kind === 'newblock') {
      const w0 = screenToWorld(d.x0, d.y0), w1 = screenToWorld(d.x1, d.y1);
      const cx = (w0.x + w1.x) / 2, cy = (w0.y + w1.y) / 2;
      if (Math.abs(d.x1 - d.x0) > 6 || Math.abs(d.y1 - d.y0) > 6) {
        openBlockCreatePopup(cx, cy);
      }
    } else if (d.kind === 'moveblock' && d.moved) {
      renumberFloor(floor());
    } else if (d.kind === 'lasso') {
      const x = Math.min(d.x0, d.x1), y = Math.min(d.y0, d.y1);
      const x2 = Math.max(d.x0, d.x1), y2 = Math.max(d.y0, d.y1);
      const w1 = screenToWorld(x, y), w2 = screenToWorld(x2, y2);
      const ids = new Set();
      for (const b of floor().blocks) for (const s of b.seats) {
        if (s.isActive && s.x >= w1.x && s.x <= w2.x && s.y >= w1.y && s.y <= w2.y) ids.add(s.id);
      }
      if (ids.size > 0) { S.sel = { type: 'seats', blockId: null, seatIds: ids }; }
      else if (Math.abs(d.x1 - d.x0) + Math.abs(d.y1 - d.y0) < 4) { S.sel = { type: 'none', blockId: null, seatIds: new Set() }; }
      renderPanel();
    }
    S.drag = null;
    render();
  }

  function drawPreviewRect(d) {
    const { ctx } = S;
    const x = Math.min(d.x0, d.x1), y = Math.min(d.y0, d.y1);
    ctx.save();
    ctx.strokeStyle = S.newColor || DEFAULT_COLOR; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
    ctx.strokeRect(x, y, Math.abs(d.x1 - d.x0), Math.abs(d.y1 - d.y0));
    ctx.restore();
  }

  // ── Попап создания блока (кол-во рядов/мест + промежутки) ─────────────
  function openBlockCreatePopup(cx, cy) {
    UI.modal({
      title: 'Новый блок кресел',
      body: `
        <div class="row"><label>Рядов</label><input id="bp-rows" type="number" min="1" value="5"></div>
        <div class="row"><label>Мест в ряду</label><input id="bp-cols" type="number" min="1" value="8"></div>
        <div class="row"><label>Промежуток рядов</label><input id="bp-gy" type="range" min="4" max="16" value="8"><span class="range-val" id="bp-gy-v">8</span></div>
        <div class="row"><label>Промежуток мест</label><input id="bp-gx" type="range" min="4" max="16" value="8"><span class="range-val" id="bp-gx-v">8</span></div>
      `,
      okText: 'Создать',
      onMount: (root) => {
        root.querySelector('#bp-gy').oninput = (e) => root.querySelector('#bp-gy-v').textContent = e.target.value;
        root.querySelector('#bp-gx').oninput = (e) => root.querySelector('#bp-gx-v').textContent = e.target.value;
      },
      onOk: (root) => {
        const rows = Math.max(1, +root.querySelector('#bp-rows').value || 1);
        const cols = Math.max(1, +root.querySelector('#bp-cols').value || 1);
        const gapY = +root.querySelector('#bp-gy').value;
        const gapX = +root.querySelector('#bp-gx').value;
        const block = {
          id: uid(), seatType: S.newType, defaultPrice: S.newPrice,
          defaultDescription: S.newDesc, defaultColor: S.newColor,
          x: cx, y: cy, rotationDeg: 0, rows, seatsPerRow: cols, gapX, gapY, seats: [],
        };
        buildBlockSeats(block);
        floor().blocks.push(block);
        renumberFloor(floor());
        S.sel = { type: 'block', blockId: block.id, seatIds: new Set() };
        S.tool = 'select'; S.canvas.classList.remove('mode-add');
        renderPanel(); render();
        return true;
      }
    });
  }

  // ── Нижняя контекстная панель ─────────────────────────────────────────
  function renderPanel() {
    const el = S.dom.panel;
    const sel = S.sel;

    if (sel.type === 'block') {
      const b = floor().blocks.find(x => x.id === sel.blockId);
      if (!b) { sel.type = 'none'; }
      else {
        el.innerHTML = `
          <div class="bp-group"><span class="bp-label">Блок</span>${typeSelect('bp-type', b.seatType)}</div>
          <div class="bp-group"><span class="bp-label">Цвет</span><input class="bp-color" id="bp-color" type="color" value="${toHex(b.defaultColor)}"><input class="bp-field" id="bp-color-hex" style="width:88px" value="${b.defaultColor}"></div>
          <div class="bp-group"><span class="bp-label">Цена</span><input class="bp-field" id="bp-price" type="number" value="${b.defaultPrice}" style="width:90px"></div>
          <div class="bp-group"><span class="bp-label">Описание</span><input class="bp-field" id="bp-desc" value="${b.defaultDescription || ''}"></div>
          <div class="bp-group"><span class="bp-label">Угол</span><input class="bp-field" id="bp-rot" type="number" value="${Math.round(b.rotationDeg)}" style="width:70px">°</div>
          <div class="bp-spacer"></div>
          <button class="btn btn-danger btn-sm" id="bp-del">Удалить блок</button>
          <button class="btn btn-ghost btn-sm" id="bp-clear">Снять выделение</button>`;
        wireBlockPanel(b);
        return;
      }
    }

    if (sel.type === 'seats') {
      const seats = allSelectedSeats();
      const first = seats[0] || {};
      el.innerHTML = `
        <div class="bp-group"><span class="bp-label">Выбрано мест: <b>${seats.length}</b></span></div>
        <div class="bp-group">${typeSelect('bp-type', first.seatType || 'Standard')}</div>
        <div class="bp-group"><span class="bp-label">Цвет</span><input class="bp-color" id="bp-color" type="color" value="${toHex(first.color || DEFAULT_COLOR)}"><input class="bp-field" id="bp-color-hex" style="width:88px" value="${first.color || DEFAULT_COLOR}"></div>
        <div class="bp-group"><span class="bp-label">Цена</span><input class="bp-field" id="bp-price" type="number" value="${first.price ?? ''}" style="width:90px"></div>
        <div class="bp-group"><span class="bp-label">Описание</span><input class="bp-field" id="bp-desc" value="${first.description || ''}"></div>
        <div class="bp-spacer"></div>
        <button class="btn btn-primary btn-sm" id="bp-apply">Применить к выбранным</button>
        <button class="btn btn-danger btn-sm" id="bp-del-seats">Удалить выбранные</button>`;
      wireSeatsPanel();
      return;
    }

    if (sel.type === 'stage') {
      const st = floor().stage;
      el.innerHTML = `
        <div class="bp-group"><span class="bp-label">Сцена</span><input class="bp-field" id="bp-stage-label" value="${st.label}"></div>
        <div class="bp-group"><span class="bp-label">Ширина</span><input class="bp-field" id="bp-stage-w" type="number" value="${Math.round(st.width)}" style="width:80px"></div>
        <div class="bp-group"><span class="bp-label">Высота</span><input class="bp-field" id="bp-stage-h" type="number" value="${Math.round(st.height)}" style="width:80px"></div>
        <div class="bp-spacer"></div>
        <button class="btn btn-ghost btn-sm" id="bp-clear">Снять выделение</button>`;
      const st_ = floor().stage;
      el.querySelector('#bp-stage-label').oninput = (e) => { st_.label = e.target.value; render(); };
      el.querySelector('#bp-stage-w').oninput = (e) => { st_.width = +e.target.value || st_.width; render(); };
      el.querySelector('#bp-stage-h').oninput = (e) => { st_.height = +e.target.value || st_.height; render(); };
      el.querySelector('#bp-clear').onclick = clearSel;
      return;
    }

    // ничего не выбрано → добавление блока
    el.innerHTML = `
      <div class="bp-group"><span class="bp-label">Тип кресла</span>${typeSelect('np-type', S.newType)}</div>
      <div class="bp-group"><span class="bp-label">Цвет</span><input class="bp-color" id="np-color" type="color" value="${toHex(S.newColor)}"><input class="bp-field" id="np-color-hex" style="width:88px" value="${S.newColor}"></div>
      <div class="bp-group"><span class="bp-label">Цена</span><input class="bp-field" id="np-price" type="number" value="${S.newPrice}" style="width:90px"></div>
      <div class="bp-group"><span class="bp-label">Описание</span><input class="bp-field" id="np-desc" value="${S.newDesc || ''}" placeholder="необязательно"></div>
      <div class="bp-spacer"></div>
      <button class="btn btn-primary" id="np-add">＋ Добавить блок</button>`;
    el.querySelector('#np-type').onchange = (e) => S.newType = e.target.value;
    const npc = el.querySelector('#np-color'), nph = el.querySelector('#np-color-hex');
    npc.oninput = (e) => { S.newColor = e.target.value; nph.value = e.target.value; };
    nph.oninput = (e) => { S.newColor = e.target.value; if (/^#[0-9a-f]{6}$/i.test(e.target.value)) npc.value = e.target.value; };
    el.querySelector('#np-price').oninput = (e) => S.newPrice = +e.target.value || 0;
    el.querySelector('#np-desc').oninput = (e) => S.newDesc = e.target.value;
    el.querySelector('#np-add').onclick = () => {
      S.tool = 'add'; S.canvas.classList.add('mode-add');
      UI.toast('Растяните прямоугольник на холсте');
    };
  }

  function typeSelect(id, val) {
    return `<select class="bp-field" id="${id}">` +
      SEAT_TYPES.map(t => `<option value="${t}" ${t === val ? 'selected' : ''}>${TYPE_RU[t]}</option>`).join('') +
      `</select>`;
  }

  function wireBlockPanel(b) {
    const el = S.dom.panel;
    el.querySelector('#bp-type').onchange = (e) => { b.seatType = e.target.value; b.seats.forEach(s => s.seatType = e.target.value); render(); };
    const col = el.querySelector('#bp-color'), hex = el.querySelector('#bp-color-hex');
    const applyColor = (v) => { b.defaultColor = v; b.seats.forEach(s => s.color = v); render(); };
    col.oninput = (e) => { hex.value = e.target.value; applyColor(e.target.value); };
    hex.oninput = (e) => { if (/^#[0-9a-f]{6}$/i.test(e.target.value)) { col.value = e.target.value; applyColor(e.target.value); } };
    el.querySelector('#bp-price').oninput = (e) => { b.defaultPrice = +e.target.value || 0; b.seats.forEach(s => s.price = b.defaultPrice); };
    el.querySelector('#bp-desc').oninput = (e) => { b.defaultDescription = e.target.value; b.seats.forEach(s => s.description = e.target.value); };
    el.querySelector('#bp-rot').oninput = (e) => { b.rotationDeg = +e.target.value || 0; applyBlockTransform(b); render(); };
    el.querySelector('#bp-del').onclick = () => {
      UI.confirm(`Удалить блок (${b.seats.length} мест)?`, () => {
        floor().blocks = floor().blocks.filter(x => x.id !== b.id);
        renumberFloor(floor()); clearSel();
      });
    };
    el.querySelector('#bp-clear').onclick = clearSel;
  }

  function wireSeatsPanel() {
    const el = S.dom.panel;
    el.querySelector('#bp-apply').onclick = () => {
      const type = el.querySelector('#bp-type').value;
      const color = el.querySelector('#bp-color-hex').value;
      const price = el.querySelector('#bp-price').value;
      const desc = el.querySelector('#bp-desc').value;
      for (const s of allSelectedSeats()) {
        s.seatType = type;
        if (/^#[0-9a-f]{6}$/i.test(color)) s.color = color;
        if (price !== '') s.price = +price;
        s.description = desc;
      }
      UI.toast('Применено к выбранным', 'ok'); render();
    };
    el.querySelector('#bp-del-seats').onclick = () => {
      const n = S.sel.seatIds.size;
      UI.confirm(`Удалить ${n} мест?`, () => {
        for (const s of allSelectedSeats()) s.isActive = false;
        renumberFloor(floor()); clearSel();
      });
    };
  }

  function clearSel() { S.sel = { type: 'none', blockId: null, seatIds: new Set() }; renderPanel(); render(); }

  const toHex = (c) => (/^#[0-9a-f]{6}$/i.test(c) ? c : DEFAULT_COLOR);

  // ── Этажи ──────────────────────────────────────────────────────────
  function renderFloorTabs() {
    const el = S.dom.tabs;
    el.innerHTML = '';
    S.floors.forEach((f, i) => {
      const b = document.createElement('button');
      b.className = 'floor-tab' + (i === S.activeFloor ? ' active' : '');
      b.innerHTML = `<span>${f.name}</span>` + (S.floors.length > 1 ? ` <span class="x">✕</span>` : '');
      b.querySelector('span').ondblclick = () => renameFloor(i);
      b.onclick = (e) => {
        if (e.target.classList.contains('x')) { removeFloor(i); return; }
        S.activeFloor = i; clearSel(); renderFloorTabs(); render();
      };
      el.appendChild(b);
    });
    const add = document.createElement('button');
    add.className = 'floor-tab add-floor'; add.textContent = '＋';
    add.onclick = addFloor;
    el.appendChild(add);
  }

  function newFloor(name, order) {
    return { id: uid(), name, order, stage: { x: 0, y: -220, width: 240, height: 64, label: 'СЦЕНА' }, blocks: [] };
  }
  function addFloor() {
    UI.prompt('Название этажа', `Этаж ${S.floors.length + 1}`, (name) => {
      if (!name) return;
      S.floors.push(newFloor(name, S.floors.length));
      S.activeFloor = S.floors.length - 1; clearSel(); renderFloorTabs(); render();
    });
  }
  function renameFloor(i) {
    UI.prompt('Название этажа', S.floors[i].name, (name) => {
      if (name) { S.floors[i].name = name; renderFloorTabs(); }
    });
  }
  function removeFloor(i) {
    if (S.floors.length <= 1) { UI.toast('Нужен хотя бы один этаж', 'err'); return; }
    UI.confirm(`Удалить этаж «${S.floors[i].name}»?`, () => {
      S.floors.splice(i, 1);
      S.floors.forEach((f, idx) => f.order = idx);
      S.activeFloor = Math.max(0, S.activeFloor - (i <= S.activeFloor ? 1 : 0));
      clearSel(); renderFloorTabs(); render();
    });
  }

  // ── Загрузка/сериализация ────────────────────────────────────────────
  function floorsFromServer(serverFloors) {
    return (serverFloors || []).map((f, i) => {
      const blocks = (f.seatBlocks || []).map(b => {
        const block = {
          id: b.id || uid(), seatType: b.seatType, defaultPrice: b.defaultPrice,
          defaultDescription: b.defaultDescription, defaultColor: b.defaultColor,
          x: b.canvasX, y: b.canvasY, rotationDeg: b.rotationDeg,
          rows: b.rows, seatsPerRow: b.seatsPerRow, gapX: 8, gapY: 8,
          seats: (b.seats || []).map(s => ({
            id: s.id || uid(), row: s.row, number: s.number, seatType: s.seatType,
            price: s.price, description: s.description, color: s.color,
            x: s.canvasX, y: s.canvasY, isActive: s.isActive !== false, lx: 0, ly: 0,
          })),
        };
        deriveLocal(block);
        return block;
      });
      const st = f.stage;
      return {
        id: f.id || uid(), name: f.name, order: f.order ?? i,
        stage: st ? { x: st.canvasX, y: st.canvasY, width: st.width, height: st.height, label: st.label }
                  : { x: 0, y: -220, width: 240, height: 64, label: 'СЦЕНА' },
        blocks,
      };
    });
  }

  function serialize() {
    // Пересчитать нумерацию перед сохранением на всех этажах
    S.floors.forEach(renumberFloor);
    return {
      name: S.dom.nameInput.value.trim(),
      venueId: S.venueId,
      floors: S.floors.map(f => ({
        id: null, name: f.name, order: f.order,
        stage: { canvasX: f.stage.x, canvasY: f.stage.y, width: f.stage.width, height: f.stage.height, label: f.stage.label },
        seatBlocks: f.blocks.map(b => ({
          id: null, seatType: b.seatType, defaultPrice: b.defaultPrice,
          defaultDescription: b.defaultDescription || null, defaultColor: b.defaultColor,
          canvasX: b.x, canvasY: b.y, rotationDeg: b.rotationDeg,
          rows: b.rows, seatsPerRow: b.seatsPerRow,
          seats: b.seats.filter(s => s.isActive).map(s => ({
            id: null, row: s.row, number: s.number, seatType: s.seatType,
            price: s.price, description: s.description || null, color: s.color,
            canvasX: s.x, canvasY: s.y, isActive: true,
          })),
        })),
      })),
    };
  }

  // ── Публичный open() ─────────────────────────────────────────────────
  function open(container, opts) {
    const { layout, mode = 'venue', onSave, venues = [], title = 'Новый зал' } = opts;

    container.innerHTML = `
      <div class="editor">
        <div class="editor-top">
          <button class="btn btn-ghost btn-sm" id="ed-back">← Назад</button>
          <input class="layout-name" id="ed-name" placeholder="Название зала" />
          ${mode === 'venue' ? `<select class="bp-field" id="ed-venue"></select>` : ''}
          <div class="spacer"></div>
          <div class="floor-tabs" id="ed-tabs"></div>
          <div class="spacer"></div>
          <button class="btn btn-primary" id="ed-save">Сохранить</button>
        </div>
        <div class="editor-stage">
          <canvas id="canvas"></canvas>
          <div class="editor-hint">Колесо — панорама · Ctrl+колесо — зум · Пробел+перетаскивание — панорама<br>Клик по блоку — выделить · Перетащить пустое место — лассо</div>
          <div class="zoom-controls">
            <button id="ed-zin">＋</button>
            <button id="ed-zout">−</button>
            <button id="ed-zreset" class="zoom-reset">1:1</button>
          </div>
        </div>
        <div class="bottom-panel" id="ed-panel"></div>
      </div>`;

    const canvas = container.querySelector('#canvas');
    S = {
      mode, onSave, venueId: (layout && layout.venueId) || (venues[0] && venues[0].id) || null,
      canvas, ctx: canvas.getContext('2d'),
      camera: { panX: -canvas.clientWidth / 2 || -400, panY: -60, zoom: 1 },
      tool: 'select', sel: { type: 'none', blockId: null, seatIds: new Set() }, drag: null, space: false,
      newType: 'Standard', newColor: DEFAULT_COLOR, newPrice: 5000, newDesc: '',
      dom: {
        nameInput: container.querySelector('#ed-name'),
        tabs: container.querySelector('#ed-tabs'),
        panel: container.querySelector('#ed-panel'),
      },
      floors: [],
    };

    S.dom.nameInput.value = (layout && layout.name) || '';

    // Площадки (только для шаблона)
    if (mode === 'venue') {
      const vsel = container.querySelector('#ed-venue');
      vsel.innerHTML = venues.map(v => `<option value="${v.id}">${v.name}</option>`).join('');
      if (S.venueId) vsel.value = S.venueId;
      vsel.onchange = (e) => S.venueId = e.target.value;
    }

    // Этажи
    if (layout && layout.floors && layout.floors.length) {
      S.floors = floorsFromServer(layout.floors);
    } else {
      S.floors = [newFloor('Партер', 0)];
    }
    S.activeFloor = 0;

    // Кнопки
    container.querySelector('#ed-back').onclick = () => location.hash = mode === 'venue' ? '#/layouts' : '#/events';
    container.querySelector('#ed-zin').onclick = () => zoomAt(canvas.clientWidth / 2, canvas.clientHeight / 2, 1.15);
    container.querySelector('#ed-zout').onclick = () => zoomAt(canvas.clientWidth / 2, canvas.clientHeight / 2, 1 / 1.15);
    container.querySelector('#ed-zreset').onclick = () => { cam().zoom = 1; render(); };
    container.querySelector('#ed-save').onclick = onSaveClick;

    bindInput();
    renderFloorTabs();
    renderPanel();
    // центрируем камеру на сцене
    S.camera.panX = -canvas.clientWidth / 2;
    render();

    window.addEventListener('resize', render);
  }

  function onSaveClick() {
    const name = S.dom.nameInput.value.trim();
    if (!name) {
      UI.prompt('Название зала', '', (n) => {
        if (!n) return;
        S.dom.nameInput.value = n;
        doSave();
      });
      return;
    }
    doSave();
  }

  async function doSave() {
    try {
      const data = serialize();
      await S.onSave(data);
      UI.toast('Зал сохранён', 'ok');
    } catch (e) {
      UI.toast(e.message || 'Ошибка сохранения', 'err');
    }
  }

  return { open };
})();
