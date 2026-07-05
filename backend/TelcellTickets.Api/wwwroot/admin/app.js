// ══════════════════════════════════════════════════════════════════════════
//  UI-хелперы: тосты, модалки, confirm, prompt
// ══════════════════════════════════════════════════════════════════════════
const UI = (() => {
  const host = () => document.getElementById('overlay-host');

  function toast(text, kind = '') {
    let box = document.getElementById('toasts');
    if (!box) { box = document.createElement('div'); box.id = 'toasts'; document.body.appendChild(box); }
    const t = document.createElement('div');
    t.className = 'toast ' + kind; t.textContent = text;
    box.appendChild(t);
    setTimeout(() => t.remove(), 2600);
  }

  function modal({ title, body, okText = 'ОК', cancelText = 'Отмена', onOk, onMount }) {
    const back = document.createElement('div');
    back.className = 'modal-backdrop';
    back.innerHTML = `
      <div class="modal">
        <h3>${title}</h3>
        <div class="modal-body">${body || ''}</div>
        <div class="modal-actions">
          <button class="btn btn-ghost" data-cancel>${cancelText}</button>
          <button class="btn btn-primary" data-ok>${okText}</button>
        </div>
      </div>`;
    host().appendChild(back);
    const root = back.querySelector('.modal');
    const close = () => back.remove();
    back.querySelector('[data-cancel]').onclick = close;
    back.onclick = (e) => { if (e.target === back) close(); };
    back.querySelector('[data-ok]').onclick = () => {
      const keep = onOk ? onOk(root) : true;
      if (keep !== false) close();
    };
    if (onMount) onMount(root);
    return { close, root };
  }

  function confirm(text, onYes) {
    modal({
      title: 'Подтверждение', body: `<p style="margin:0;color:#555">${text}</p>`,
      okText: 'Да', onOk: () => { onYes(); return true; }
    });
  }

  function prompt(title, value, onOk) {
    modal({
      title,
      body: `<div class="row"><input id="prompt-input" type="text" value="${(value || '').replace(/"/g, '&quot;')}" style="flex:1"></div>`,
      onMount: (r) => { const i = r.querySelector('#prompt-input'); i.focus(); i.select(); i.onkeydown = (e) => { if (e.key === 'Enter') r.querySelector('[data-ok]').click(); }; },
      onOk: (r) => { onOk(r.querySelector('#prompt-input').value.trim()); return true; }
    });
  }

  return { toast, modal, confirm, prompt };
})();

// ══════════════════════════════════════════════════════════════════════════
//  Роутер
// ══════════════════════════════════════════════════════════════════════════
const view = () => document.getElementById('view');
let VENUES = [];

async function ensureVenues() {
  if (VENUES.length) return VENUES;
  try { VENUES = await API.venues(); } catch { VENUES = []; }
  return VENUES;
}

function setActiveTab(tab) {
  document.querySelectorAll('.topnav a').forEach(a => a.classList.toggle('active', a.dataset.tab === tab));
}

async function route() {
  const hash = location.hash || '#/layouts';
  view().classList.toggle('editor-view', hash.startsWith('#/editor') || hash.startsWith('#/event-editor'));

  if (hash.startsWith('#/editor')) {
    setActiveTab('layouts');
    const id = hash.split('/')[2];
    await openLayoutEditor(id);
  } else if (hash.startsWith('#/event-editor/')) {
    setActiveTab('events');
    const eventId = hash.split('/')[2];
    await openEventEditor(eventId);
  } else if (hash.startsWith('#/events')) {
    setActiveTab('events');
    await renderEvents();
  } else {
    setActiveTab('layouts');
    await renderLayouts();
  }
}

// ── Список шаблонов ─────────────────────────────────────────────────────
async function renderLayouts() {
  const v = view();
  v.innerHTML = `
    <div class="page">
      <div class="page-head">
        <h1>Шаблоны залов</h1>
        <button class="btn btn-primary" id="new-layout">＋ Создать новый зал</button>
      </div>
      <div class="searchbar"><input id="layout-search" placeholder="Поиск по названию…"></div>
      <div class="cards" id="layout-cards"><div class="empty">Загрузка…</div></div>
    </div>`;
  v.querySelector('#new-layout').onclick = () => location.hash = '#/editor';

  const cards = v.querySelector('#layout-cards');
  const load = async (search) => {
    try {
      const list = await API.listLayouts(search || '');
      if (!list.length) { cards.innerHTML = `<div class="empty">Шаблонов пока нет. Создайте первый зал.</div>`; return; }
      cards.innerHTML = list.map(l => `
        <div class="card" data-id="${l.id}">
          <div class="card-title">${l.name}</div>
          <div class="card-meta"><span><b>${l.floorCount}</b> эт.</span><span><b>${l.seatCount}</b> мест</span><span>${l.venueName || ''}</span></div>
          <div class="card-date">Создан ${new Date(l.createdAt).toLocaleDateString('ru-RU')}</div>
        </div>`).join('');
      cards.querySelectorAll('.card').forEach(c => c.onclick = () => location.hash = '#/editor/' + c.dataset.id);
    } catch (e) { cards.innerHTML = `<div class="empty">Ошибка: ${e.message}</div>`; }
  };
  let timer;
  v.querySelector('#layout-search').oninput = (e) => { clearTimeout(timer); timer = setTimeout(() => load(e.target.value), 250); };
  load('');
}

// ── Редактор шаблона ────────────────────────────────────────────────────
async function openLayoutEditor(id) {
  await ensureVenues();
  if (!VENUES.length) { view().innerHTML = `<div class="page"><div class="empty">Нет площадок в базе — сначала добавьте Venue.</div></div>`; return; }

  let layout = null;
  if (id) {
    try { layout = await API.getLayout(id); }
    catch (e) { UI.toast('Не удалось загрузить шаблон', 'err'); location.hash = '#/layouts'; return; }
  }

  Editor.open(view(), {
    mode: 'venue',
    venues: VENUES,
    layout,
    onSave: async (data) => {
      const dto = { venueId: data.venueId, name: data.name, floors: data.floors };
      if (id) { await API.updateLayout(id, dto); }
      else {
        const created = await API.createLayout(dto);
        location.hash = '#/editor/' + created.id; // перейти в режим редактирования
      }
    }
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  Мероприятия (3.3)
// ════════════════════════════��═════════════════════════════════════════════
async function renderEvents() {
  const v = view();
  v.innerHTML = `<div class="page"><div class="page-head"><h1>Мероприятия</h1></div><div id="events-list"><div class="empty">Загрузка…</div></div></div>`;
  const list = v.querySelector('#events-list');
  try {
    const events = await API.listEvents();
    if (!events.length) { list.innerHTML = `<div class="empty">Мероприятий нет.</div>`; return; }
    // Подтягиваем статус схемы по каждому событию
    const layouts = await Promise.all(events.map(e => API.getEventLayout(e.id)));
    list.innerHTML = events.map((e, i) => {
      const lay = layouts[i];
      const hasPlan = lay && lay.hasSeatingPlan;
      const st = e.status || 'Active';
      const stBadge = st === 'Cancelled'
        ? `<span class="badge" style="background:#fdecea;color:#c0392b">Отменено</span>`
        : st === 'Rescheduled'
          ? `<span class="badge" style="background:#fef5e7;color:#b9770e">Перенесено → ${e.newStartsAt ? new Date(e.newStartsAt).toLocaleDateString('ru-RU') : ''}</span>`
          : '';
      return `
        <div class="event-row" data-id="${e.id}">
          <div>
            <div class="ev-title">${e.title}</div>
            <div class="ev-meta">${e.venue?.name || ''} · ${new Date(e.startsAt).toLocaleDateString('ru-RU')}</div>
          </div>
          <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap">
            ${stBadge}
            <span class="badge ${hasPlan ? 'plan' : 'plus'}">${hasPlan ? 'Схема зала' : 'Плюсики'}</span>
            <button class="btn btn-outline btn-sm" data-config="${e.id}">Схема зала…</button>
            ${st !== 'Cancelled' ? `<button class="btn btn-outline btn-sm" data-reschedule="${e.id}">Перенести…</button>
            <button class="btn btn-outline btn-sm" style="color:#c0392b;border-color:#c0392b" data-cancel="${e.id}">Отменить…</button>` : ''}
          </div>
        </div>`;
    }).join('');
    list.querySelectorAll('[data-config]').forEach(btn => btn.onclick = () => {
      const ev = events.find(x => x.id === btn.dataset.config);
      configureEventSeating(ev, layouts[events.indexOf(ev)]);
    });
    list.querySelectorAll('[data-cancel]').forEach(btn => btn.onclick = () => {
      const ev = events.find(x => x.id === btn.dataset.cancel);
      cancelEventDialog(ev);
    });
    list.querySelectorAll('[data-reschedule]').forEach(btn => btn.onclick = () => {
      const ev = events.find(x => x.id === btn.dataset.reschedule);
      rescheduleEventDialog(ev);
    });
  } catch (e) { list.innerHTML = `<div class="empty">Ошибка: ${e.message}</div>`; }
}

// Диалог отмены события: все активные билеты → авто-возврат.
function cancelEventDialog(ev) {
  UI.modal({
    title: `Отменить событие — ${ev.title}`,
    okText: 'Отменить событие',
    body: `<p style="margin:0;color:#555">Все активные билеты будут аннулированы, покупателям начислен автоматический возврат средств. Действие необратимо.</p>`,
    onOk: async () => {
      try {
        const r = await API.cancelEvent(ev.id);
        UI.toast(`Событие отменено, возвратов: ${r.refundedTickets}`, 'ok');
        renderEvents();
      } catch (e) { UI.toast(e.message, 'err'); }
    },
  });
}

// Диалог переноса события: новая дата + дедлайн решения покупателя (72ч по умолчанию).
function rescheduleEventDialog(ev) {
  UI.modal({
    title: `Перенести событие — ${ev.title}`,
    okText: 'Перенести',
    body: `
      <p style="margin:0 0 12px;color:#555">Билеты перейдут в статус «ожидает решения»: покупатель подтверждает участие или получает возврат (72 часа на решение).</p>
      <label style="display:block;margin-bottom:6px;font-weight:600">Новая дата и время</label>
      <input type="datetime-local" id="resched-date" style="width:100%;padding:8px;border:1px solid #ccc;border-radius:8px" />`,
    onOk: async () => {
      const val = document.getElementById('resched-date')?.value;
      if (!val) { UI.toast('Укажите новую дату', 'err'); return; }
      try {
        const r = await API.rescheduleEvent(ev.id, { newStartsAt: new Date(val).toISOString() });
        UI.toast(`Перенесено, билетов в ожидании: ${r.pendingTickets}`, 'ok');
        renderEvents();
      } catch (e) { UI.toast(e.message, 'err'); }
    },
  });
}

// Диалог настройки схемы для мероприятия
function configureEventSeating(ev, currentLayout) {
  const hasPlan = currentLayout && currentLayout.hasSeatingPlan;
  UI.modal({
    title: `Схема зала — ${ev.title}`,
    okText: 'Готово',
    body: `
      <p style="margin:0 0 14px;color:#555">Выберите способ продажи билетов:</p>
      <div class="seg" id="seat-seg" style="margin-bottom:16px">
        <button data-mode="plus" class="${!hasPlan ? 'active' : ''}">Без схемы (плюсики)</button>
        <button data-mode="plan" class="${hasPlan ? 'active' : ''}">Со схемой зала</button>
      </div>
      <div id="plan-actions" style="display:${hasPlan ? 'flex' : 'none'};gap:10px">
        <button class="btn btn-ghost" id="ev-new">Создать новый зал</button>
        <button class="btn btn-ghost" id="ev-pick">Выбрать из созданных</button>
        ${currentLayout && currentLayout.floors?.length ? `<button class="btn btn-outline" id="ev-edit">Редактировать схему</button>` : ''}
      </div>`,
    onMount: (root) => {
      let mode = hasPlan ? 'plan' : 'plus';
      const actions = root.querySelector('#plan-actions');
      root.querySelectorAll('#seat-seg button').forEach(b => b.onclick = async () => {
        root.querySelectorAll('#seat-seg button').forEach(x => x.classList.remove('active'));
        b.classList.add('active'); mode = b.dataset.mode;
        actions.style.display = mode === 'plan' ? 'flex' : 'none';
        if (mode === 'plus') {
          try { await API.saveEventLayout(ev.id, { venueLayoutId: null, hasSeatingPlan: false, floors: null }); UI.toast('Режим «плюсики» сохранён', 'ok'); }
          catch (e) { UI.toast(e.message, 'err'); }
        }
      });
      const ne = root.querySelector('#ev-new'); if (ne) ne.onclick = () => { root.closest('.modal-backdrop').remove(); location.hash = '#/event-editor/' + ev.id; };
      const ed = root.querySelector('#ev-edit'); if (ed) ed.onclick = () => { root.closest('.modal-backdrop').remove(); location.hash = '#/event-editor/' + ev.id; };
      const pk = root.querySelector('#ev-pick'); if (pk) pk.onclick = () => pickTemplate(ev, () => root.closest('.modal-backdrop').remove());
    }
  });
}

// Попап выбора готового шаблона
async function pickTemplate(ev, closeParent) {
  const templates = await API.listLayouts('');
  let selected = null;
  const m = UI.modal({
    title: 'Выбрать зал из созданных',
    okText: 'Добавить этот зал',
    body: `
      <div class="searchbar" style="margin-bottom:12px"><input id="tpl-search" placeholder="Поиск по названию…"></div>
      <div class="tpl-list" id="tpl-list"></div>`,
    onOk: async () => {
      if (!selected) { UI.toast('Выберите шаблон', 'err'); return false; }
      try {
        await API.saveEventLayout(ev.id, { venueLayoutId: selected, hasSeatingPlan: true, floors: null });
        UI.toast('Зал добавлен к мероприятию', 'ok');
        if (closeParent) closeParent();
        setTimeout(() => location.hash = '#/event-editor/' + ev.id, 200);
        return true;
      } catch (e) { UI.toast(e.message, 'err'); return false; }
    },
    onMount: (root) => {
      const listEl = root.querySelector('#tpl-list');
      const draw = (arr) => {
        listEl.innerHTML = arr.length ? arr.map(t => `
          <div class="tpl-row" data-id="${t.id}">
            <div><div class="t">${t.name}</div><div class="m">${t.floorCount} эт. · ${t.seatCount} мест · ${t.venueName || ''}</div></div>
            <div class="m">${new Date(t.createdAt).toLocaleDateString('ru-RU')}</div>
          </div>`).join('') : `<div class="empty">Ничего не найдено</div>`;
        listEl.querySelectorAll('.tpl-row').forEach(r => r.onclick = () => {
          listEl.querySelectorAll('.tpl-row').forEach(x => x.classList.remove('sel'));
          r.classList.add('sel'); selected = r.dataset.id;
        });
      };
      draw(templates);
      root.querySelector('#tpl-search').oninput = (e) => {
        const q = e.target.value.toLowerCase();
        draw(templates.filter(t => t.name.toLowerCase().includes(q)));
      };
    }
  });
}

// Редактор схемы конкретного мероприятия
async function openEventEditor(eventId) {
  let layout = null;
  try { layout = await API.getEventLayout(eventId); } catch {}

  // Приводим схему события к формату редактора (seatBlocks/seats уже те же имена)
  const editable = layout ? { name: '', venueId: null, floors: layout.floors } : null;

  Editor.open(view(), {
    mode: 'event',
    layout: editable,
    onSave: async (data) => {
      // POST заменяет/создаёт схему события (работает и когда схемы ещё не было).
      await API.saveEventLayout(eventId, { venueLayoutId: null, hasSeatingPlan: true, floors: data.floors });
    }
  });
}

// ── навигация ────────────────────────────────────────────────────────
document.addEventListener('click', (e) => {
  const nav = e.target.closest('[data-nav]');
  if (nav) location.hash = nav.dataset.nav;
});
window.addEventListener('hashchange', route);
window.addEventListener('DOMContentLoaded', route);
route();
