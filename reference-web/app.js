/* Menu Bar To-Do — logic ported from "Menu Bar To-Do.dc.html" (Component class). */
(() => {
  'use strict';

  // Design-time props from the .dc.html, kept as runtime config.
  const CONFIG = {
    dateFormat: 'Relativ',            // 'Relativ' | 'Absolut'
    showDescriptions: true,
    dropZoneStyle: 'Einfügelinie'     // 'Einfügelinie' | 'Gestrichelter Rahmen' | 'Kopfzeile' | 'Leerer Slot'
  };

  const STORAGE_KEY = 'menu-bar-todo/v1';
  const WD = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  const MO = ['Jan', 'Feb', 'März', 'Apr', 'Mai', 'Juni', 'Juli', 'Aug', 'Sept', 'Okt', 'Nov', 'Dez'];
  const MO_FULL = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  const WEEKDAYS_HEAD = ['MO', 'DI', 'MI', 'DO', 'FR', 'SA', 'SO'];

  // ---------- date helpers ----------
  const pad = (n) => String(n).padStart(2, '0');
  const localIso = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  const todayIso = () => localIso(new Date());
  const isoOff = (off) => { const d = new Date(); d.setDate(d.getDate() + off); return localIso(d); };
  const parseIso = (iso) => new Date(iso + 'T00:00:00');
  const dayDiff = (iso) => Math.round((parseIso(iso) - parseIso(todayIso())) / 864e5);

  function rangeText(a, b) {
    const d1 = parseIso(a);
    if (!b || b === a) {
      const dd = dayDiff(a);
      return dd === 0 ? 'Heute' : dd === 1 ? 'Morgen' : d1.getDate() + '. ' + MO[d1.getMonth()];
    }
    const d2 = parseIso(b);
    const same = d1.getMonth() === d2.getMonth();
    return d1.getDate() + (same ? '.' : '. ' + MO[d1.getMonth()]) + ' – ' + d2.getDate() + '. ' + MO[d2.getMonth()];
  }

  function fmt(due) {
    const abs = CONFIG.dateFormat === 'Absolut';
    const dt = parseIso(due);
    const dd = dayDiff(due);
    const absLabel = dt.getDate() + '. ' + MO[dt.getMonth()];
    if (dd < 0) return { label: abs ? absLabel : 'Überfällig', color: '#FF3B30' };
    if (dd === 0) return { label: abs ? absLabel : 'Heute', color: '#0A84FF' };
    if (dd === 1 && !abs) return { label: 'Morgen', color: '#86868B' };
    if (dd < 7 && !abs) return { label: WD[dt.getDay()] + '.', color: '#86868B' };
    return { label: absLabel, color: '#86868B' };
  }

  function clockText() {
    const t = new Date();
    return WD[t.getDay()] + '. ' + t.getDate() + '. ' + MO[t.getMonth()] + '  ' + pad(t.getHours()) + ':' + pad(t.getMinutes());
  }

  // ---------- state ----------
  function seed() {
    return {
      items: [
        { id: 2, title: 'Steuerunterlagen einreichen', desc: '', due: isoOff(-1), due2: null },
        { id: 1, title: 'Design-Review vorbereiten', desc: 'Feedback aus Figma einarbeiten', due: isoOff(0), due2: null },
        { id: 3, title: 'Zahnarzttermin bestätigen', desc: '', due: isoOff(1), due2: null },
        { id: 4, title: 'Wochenbericht schreiben', desc: 'Zahlen aus dem Dashboard exportieren', due: isoOff(2), due2: null },
        { id: 5, title: 'Geschenk für Lena besorgen', desc: '', due: isoOff(6), due2: null }
      ],
      done: [{ id: 101, title: 'Miete überweisen' }, { id: 102, title: 'Flug einchecken' }],
      nextId: 200
    };
  }

  function load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const d = JSON.parse(raw);
      if (!d || !Array.isArray(d.items) || !Array.isArray(d.done)) return null;
      return { items: d.items, done: d.done, nextId: Number(d.nextId) || 200 };
    } catch (_) { return null; }
  }

  function save() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(data)); } catch (_) { /* storage unavailable — keep in memory */ }
  }

  let data = load() || seed();

  // Transient UI state (not persisted) — mirrors `g` in the design.
  const ui = { open: true, view: 'list', t: '', ds: '', due: todayIso(), due2: null, cal: false, ed: null };
  // Drag state — mirrors dragId / overDue / overId in the design.
  const drag = { id: null, overDue: null, overId: null };

  // ---------- mutations ----------
  function resetForm() { ui.t = ''; ui.ds = ''; ui.due2 = null; ui.cal = false; ui.ed = null; }

  function openAdd() { resetForm(); ui.due = todayIso(); ui.view = 'add'; render(); focusTitle(); }
  function openEdit(id) {
    const it = data.items.find((x) => x.id === id);
    if (!it) return;
    resetForm();
    ui.view = 'edit'; ui.ed = it.id; ui.t = it.title; ui.ds = it.desc || ''; ui.due = it.due; ui.due2 = it.due2 || null;
    render(); focusTitle();
  }
  function cancel() { resetForm(); ui.view = 'list'; render(); }
  function goList() { ui.view = 'list'; render(); }
  function goDone() { ui.view = 'done'; render(); }
  function togglePanel() { ui.open = !ui.open; render(); }

  function addTask() {
    const t = ui.t.trim();
    if (!t) return;
    data.items = data.items.concat([{ id: data.nextId, title: t, desc: ui.ds.trim(), due: ui.due, due2: ui.due2 || null }]);
    data.nextId += 1;
    resetForm(); ui.view = 'list';
    save(); render();
  }

  function saveTask() {
    const t = ui.t.trim();
    if (!t) return;
    data.items = data.items.map((x) => x.id === ui.ed ? Object.assign({}, x, { title: t, desc: ui.ds.trim(), due: ui.due, due2: ui.due2 || null }) : x);
    resetForm(); ui.view = 'list';
    save(); render();
  }

  function deleteTask() {
    data.items = data.items.filter((x) => x.id !== ui.ed);
    resetForm(); ui.view = 'list';
    save(); render();
  }

  function completeTask(id) {
    const it = data.items.find((x) => x.id === id);
    if (!it) return;
    data.items = data.items.filter((x) => x.id !== id);
    data.done = [{ id: it.id, title: it.title }].concat(data.done);
    save(); render();
  }

  function restoreTask(id) {
    const it = data.done.find((x) => x.id === id);
    if (!it) return;
    data.done = data.done.filter((x) => x.id !== id);
    data.items = data.items.concat([{ id: it.id, title: it.title, desc: '', due: todayIso(), due2: null }]);
    save(); render();
  }

  function moveItem(dragId, targetId, due) {
    const dragged = data.items.find((x) => x.id === dragId);
    clearDrag();
    if (!dragged || dragId === targetId) { render(); return; }
    const moved = Object.assign({}, dragged, { due }, dragged.due !== due ? { due2: null } : {});
    const rest = data.items.filter((x) => x.id !== dragId);
    const idx = targetId == null ? rest.length : rest.findIndex((x) => x.id === targetId);
    rest.splice(idx < 0 ? rest.length : idx, 0, moved);
    data.items = rest;
    save(); render();
  }

  function selectDue(iso) { ui.due = iso; ui.due2 = null; render(); }
  function selectDay(iso) {
    if (!ui.due2 && iso > ui.due) ui.due2 = iso; else { ui.due = iso; ui.due2 = null; }
    render();
  }
  function clearRange() { ui.due2 = null; render(); }
  function toggleCal() { ui.cal = !ui.cal; render(); }

  // ---------- derived ----------
  function sortedItems() {
    return data.items.slice().sort((x, y) => (x.due || '9999').localeCompare(y.due || '9999'));
  }

  function buildGroups() {
    const groups = []; const map = {};
    sortedItems().forEach((it) => {
      const f = fmt(it.due);
      if (!map[f.label]) { map[f.label] = { label: f.label, color: f.color, due: it.due, rows: [] }; groups.push(map[f.label]); }
      map[f.label].rows.push(it);
    });
    return groups;
  }

  function buildMonths() {
    const today = todayIso();
    const b = parseIso(today);
    const months = [];
    for (let m = 0; m < 5; m++) {
      const first = new Date(b.getFullYear(), b.getMonth() + m, 1);
      const y = first.getFullYear(); const mm = first.getMonth();
      const lead = (first.getDay() + 6) % 7;
      const dim = new Date(y, mm + 1, 0).getDate();
      const cells = [];
      for (let i = 0; i < lead; i++) cells.push({ blank: true });
      for (let n = 1; n <= dim; n++) {
        const iso = y + '-' + pad(mm + 1) + '-' + pad(n);
        const end = ui.due2 || null;
        cells.push({
          iso, label: String(n),
          sel: ui.due === iso || end === iso,
          today: iso === today,
          past: iso < today,
          inRange: !!(end && iso > ui.due && iso < end)
        });
      }
      months.push({ label: (MO_FULL[mm] + ' ' + y).toUpperCase(), cells });
    }
    return months;
  }

  // ---------- rendering ----------
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const lineHtml = (cls) => '<div class="' + cls + '"><i></i><i></i></div>';

  function listHtml() {
    const groups = buildGroups();
    const zone = CONFIG.dropZoneStyle;
    return '<div class="list">' + groups.map((gr) =>
      '<div class="grp" data-group-due="' + gr.due + '" style="--grp-color:' + gr.color + '">' +
        '<div class="grp-head"><span class="grp-label">' + esc(gr.label) + '</span><span class="grp-divider"></span></div>' +
        (zone === 'Einfügelinie' ? lineHtml('drop-line') : '') +
        gr.rows.map((it) =>
          '<div class="row" draggable="true" data-row="' + it.id + '" data-due="' + it.due + '" data-action="openEdit" data-id="' + it.id + '">' +
            lineHtml('row-line') +
            '<div class="handle" data-action="noop" title="Zum Verschieben ziehen"><span></span><span></span><span></span><span></span><span></span><span></span></div>' +
            '<button type="button" class="check" data-action="complete" data-id="' + it.id + '" aria-label="Als erledigt markieren"></button>' +
            '<div class="row-body"><div class="row-title">' + esc(it.title) + '</div>' +
              (CONFIG.showDescriptions && it.desc ? '<div class="row-desc">' + esc(it.desc) + '</div>' : '') +
            '</div>' +
          '</div>'
        ).join('') +
        (zone === 'Leerer Slot' ? '<div class="slot"><span>Hierhin verschieben</span></div>' : '') +
      '</div>'
    ).join('') + '</div>';
  }

  function emptyHtml() {
    return '<div class="empty"><div class="empty-title">Alles erledigt</div><div class="empty-sub">Nichts geplant. Genieß die Ruhe.</div></div>';
  }

  function calendarHtml() {
    const months = buildMonths();
    const hint = ui.due2 ? 'Zeitraum ' + rangeText(ui.due, ui.due2) : 'Enddatum wählen';
    return '<div class="cal">' +
      '<div class="cal-weekdays">' + WEEKDAYS_HEAD.map((w) => '<span>' + w + '</span>').join('') + '</div>' +
      '<div class="cal-scroll" data-noscroll="1">' + months.map((m) =>
        '<div class="cal-month"><div class="cal-month-label">' + esc(m.label) + '</div><div class="cal-grid">' +
          m.cells.map((c) => c.blank
            ? '<button type="button" class="day is-blank" tabindex="-1" aria-hidden="true"></button>'
            : '<button type="button" class="day' + (c.sel ? ' is-selected' : '') + (c.inRange ? ' in-range' : '') + (c.past ? ' is-past' : '') + (c.today ? ' is-today' : '') + '" data-action="selectDay" data-iso="' + c.iso + '">' + c.label + '</button>'
          ).join('') +
        '</div></div>'
      ).join('') + '</div>' +
      '<div class="cal-foot"><span class="cal-hint">' + esc(hint) + '</span>' +
        (ui.due2 ? '<button type="button" class="icon-btn cal-reset" data-action="clearRange" title="Zurücksetzen" aria-label="Zurücksetzen">↺</button>' : '') +
      '</div>' +
    '</div>';
  }

  function formHtml(mode) {
    const isEdit = mode === 'edit';
    const ready = !!ui.t.trim();
    const chips = [{ off: 0, lbl: 'Heute' }, { off: 1, lbl: 'Morgen' }]
      .map((c) => Object.assign(c, { iso: isoOff(c.off) }))
      .filter((c) => ui.due !== c.iso);
    return '' +
      '<div class="form-head"><span class="form-title">' + (isEdit ? 'Task bearbeiten' : 'Task hinzufügen') + '</span>' +
        '<button type="button" class="icon-btn" data-action="cancel" aria-label="Schließen">✕</button></div>' +
      '<div class="form">' +
        '<input id="f-title" class="input" type="text" placeholder="Titel" value="' + esc(ui.t) + '" autocomplete="off">' +
        '<textarea id="f-desc" class="textarea" rows="3" placeholder="Beschreibung (optional)">' + esc(ui.ds) + '</textarea>' +
        '<div class="field"><span class="field-label">Fällig</span>' +
          '<div class="chips">' +
            chips.map((c) => '<button type="button" class="chip" data-action="selectDue" data-iso="' + c.iso + '">' + c.lbl + '</button>').join('') +
            '<button type="button" class="chip chip-date" data-action="toggleCal" aria-expanded="' + (ui.cal ? 'true' : 'false') + '"><span>' + esc(rangeText(ui.due, ui.due2)) + '</span></button>' +
          '</div>' +
          (ui.cal ? calendarHtml() : '') +
        '</div>' +
        '<button type="button" id="f-submit" class="primary' + (ready ? '' : ' is-idle') + '" data-action="' + (isEdit ? 'saveTask' : 'addTask') + '">' + (isEdit ? 'Speichern' : 'Task hinzufügen') + '</button>' +
      '</div>';
  }

  function doneHtml() {
    return '<div class="done-wrap">' +
      '<div class="done-head"><span class="form-title">Erledigt</span><button type="button" class="icon-btn" data-action="goList" aria-label="Schließen">✕</button></div>' +
      data.done.map((it) =>
        '<div class="done-row">' +
          '<button type="button" class="done-check" data-action="restore" data-id="' + it.id + '" aria-label="Wieder öffnen">✓</button>' +
          '<span class="done-title">' + esc(it.title) + '</span>' +
        '</div>'
      ).join('') +
      (data.done.length === 0 ? '<div class="done-empty">Noch nichts erledigt.</div>' : '') +
    '</div>';
  }

  function footerHtml() {
    const view = ui.view;
    return '<div class="footer">' +
      (view !== 'edit' ? '<button type="button" class="link-btn" data-action="openAdd">+ Task hinzufügen</button>' : '') +
      (view === 'edit' ? '<button type="button" class="link-btn is-danger" data-action="deleteTask">Task löschen</button>' : '') +
      '<button type="button" class="link-btn is-muted" data-action="goDone">Erledigt (' + data.done.length + ')</button>' +
    '</div>';
  }

  function panelHtml() {
    const view = ui.view;
    let body = '';
    if (view === 'list') body = data.items.length > 0 ? listHtml() : emptyHtml();
    else if (view === 'add') body = formHtml('add');
    else if (view === 'edit') body = formHtml('edit');
    else if (view === 'done') body = doneHtml();
    return '<div class="panel" data-zone="' + esc(CONFIG.dropZoneStyle) + '">' + body + footerHtml() + '</div>';
  }

  const slot = document.getElementById('panel-slot');
  const menubarToggle = document.getElementById('menubar-toggle');
  const clockEl = document.getElementById('clock');

  function render() {
    slot.innerHTML = ui.open ? panelHtml() : '';
    menubarToggle.setAttribute('aria-expanded', ui.open ? 'true' : 'false');
  }

  function focusTitle() {
    const el = document.getElementById('f-title');
    if (el) { el.focus(); el.setSelectionRange(el.value.length, el.value.length); }
  }

  function syncSubmit() {
    const btn = document.getElementById('f-submit');
    if (btn) btn.classList.toggle('is-idle', !ui.t.trim());
  }

  // ---------- events ----------
  menubarToggle.addEventListener('click', togglePanel);

  slot.addEventListener('click', (e) => {
    const el = e.target.closest('[data-action]');
    if (!el || !slot.contains(el)) return;
    const id = Number(el.dataset.id);
    switch (el.dataset.action) {
      case 'noop': break;
      case 'openEdit': openEdit(id); break;
      case 'complete': completeTask(id); break;
      case 'restore': restoreTask(id); break;
      case 'openAdd': openAdd(); break;
      case 'cancel': cancel(); break;
      case 'goList': goList(); break;
      case 'goDone': goDone(); break;
      case 'addTask': addTask(); break;
      case 'saveTask': saveTask(); break;
      case 'deleteTask': deleteTask(); break;
      case 'selectDue': selectDue(el.dataset.iso); break;
      case 'selectDay': selectDay(el.dataset.iso); break;
      case 'clearRange': clearRange(); break;
      case 'toggleCal': toggleCal(); break;
    }
  });

  // Text inputs update state without re-rendering so focus/caret survive.
  slot.addEventListener('input', (e) => {
    if (e.target.id === 'f-title') { ui.t = e.target.value; syncSubmit(); }
    else if (e.target.id === 'f-desc') { ui.ds = e.target.value; }
  });

  slot.addEventListener('keydown', (e) => {
    if (e.target.id === 'f-title' && e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (ui.view === 'edit') saveTask(); else addTask();
    } else if (e.key === 'Escape' && (ui.view === 'add' || ui.view === 'edit')) {
      cancel();
    }
  });

  // Drag & drop — indicators are toggled directly on the DOM (no re-render mid-drag).
  function clearDrag() { drag.id = null; drag.overDue = null; drag.overId = null; }

  function applyDragClasses() {
    slot.querySelectorAll('.row').forEach((r) => {
      r.classList.toggle('is-over', drag.id != null && drag.overId === Number(r.dataset.row) && drag.overId !== drag.id);
    });
    slot.querySelectorAll('.grp').forEach((g) => {
      const active = drag.id != null && drag.overDue === g.dataset.groupDue;
      g.classList.toggle('is-active', active);
      g.classList.toggle('is-slot', active && drag.overId == null);
    });
  }

  slot.addEventListener('dragstart', (e) => {
    const row = e.target.closest('[data-row]');
    if (!row) return;
    drag.id = Number(row.dataset.row);
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', String(drag.id));
  });

  slot.addEventListener('dragend', () => { clearDrag(); applyDragClasses(); });

  slot.addEventListener('dragover', (e) => {
    if (drag.id == null) return;
    const row = e.target.closest('[data-row]');
    const grp = e.target.closest('.grp');
    if (!row && !grp) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (row) {
      const id = Number(row.dataset.row);
      if (drag.overId !== id) { drag.overId = id; drag.overDue = row.dataset.due; applyDragClasses(); }
    } else if (drag.overDue !== grp.dataset.groupDue || drag.overId != null) {
      drag.overDue = grp.dataset.groupDue; drag.overId = null; applyDragClasses();
    }
  });

  slot.addEventListener('drop', (e) => {
    const row = e.target.closest('[data-row]');
    const grp = e.target.closest('.grp');
    if (!row && !grp) return;
    e.preventDefault();
    const dragId = Number(e.dataTransfer.getData('text/plain')) || drag.id;
    if (row) moveItem(dragId, Number(row.dataset.row), row.dataset.due);
    else moveItem(dragId, null, grp.dataset.groupDue);
  });

  // ---------- clock ----------
  function tickClock() { clockEl.textContent = clockText(); }
  tickClock();
  setInterval(tickClock, 15000);

  render();
})();
