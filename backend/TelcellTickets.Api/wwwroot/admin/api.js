// ── Клиент REST API. Админка отдаётся тем же C# бэкендом, поэтому base = '' ──
const API = (() => {
  const base = ''; // тот же origin

  async function req(method, url, body) {
    const opts = { method, headers: {} };
    if (body !== undefined) {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(base + url, opts);
    if (!res.ok) {
      let msg = `Ошибка ${res.status}`;
      try { const j = await res.json(); if (j.error) msg = j.error; } catch {}
      throw new Error(msg);
    }
    if (res.status === 204) return null;
    const ct = res.headers.get('content-type') || '';
    return ct.includes('application/json') ? res.json() : null;
  }

  return {
    // Площадки
    venues: () => req('GET', '/api/venues'),

    // Шаблоны залов
    listLayouts: (search = '', venueId = '') => {
      const p = new URLSearchParams();
      if (search) p.set('search', search);
      if (venueId) p.set('venueId', venueId);
      const qs = p.toString();
      return req('GET', '/api/venue-layouts' + (qs ? '?' + qs : ''));
    },
    getLayout: (id) => req('GET', `/api/venue-layouts/${id}`),
    createLayout: (dto) => req('POST', '/api/venue-layouts', dto),
    updateLayout: (id, dto) => req('PUT', `/api/venue-layouts/${id}`, dto),
    deleteLayout: (id) => req('DELETE', `/api/venue-layouts/${id}`),

    // Мероприятия
    listEvents: () => req('GET', '/api/events'),
    getEventLayout: (eventId) => req('GET', `/api/events/${eventId}/layout`).catch(() => null),
    saveEventLayout: (eventId, dto) => req('POST', `/api/events/${eventId}/layout`, dto),
    updateEventLayout: (eventId, dto) => req('PUT', `/api/events/${eventId}/layout`, dto),

    // Отмена / перенос события
    cancelEvent: (eventId) => req('POST', `/api/admin/events/${eventId}/cancel`),
    rescheduleEvent: (eventId, dto) => req('POST', `/api/admin/events/${eventId}/reschedule`, dto),
  };
})();
