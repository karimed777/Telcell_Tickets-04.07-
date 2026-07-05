const API = (() => {
  const base = '';
  const TOKEN_KEY = 'tt_org_token';

  const getToken = () => localStorage.getItem(TOKEN_KEY) || '';
  const setToken = (t) => t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY);

  async function req(method, url, body) {
    const opts = { method, headers: {} };
    const token = getToken();
    if (token) opts.headers['Authorization'] = 'Bearer ' + token;
    if (body !== undefined) {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(base + url, opts);
    if (res.status === 401) {
      setToken(null);
      window.dispatchEvent(new Event('tt-unauthorized'));
      throw new Error('Требуется вход.');
    }
    if (!res.ok) {
      let msg = res.status === 403 ? 'Нет доступа к этому мероприятию.' : `Ошибка ${res.status}`;
      try { const j = await res.json(); if (j.error) msg = j.error; } catch {}
      throw new Error(msg);
    }
    if (res.status === 204) return null;
    const ct = res.headers.get('content-type') || '';
    return ct.includes('application/json') ? res.json() : null;
  }

  async function upload(file) {
    const fd = new FormData();
    fd.append('file', file);
    const opts = { method: 'POST', headers: {}, body: fd };
    const token = getToken();
    if (token) opts.headers['Authorization'] = 'Bearer ' + token;
    const res = await fetch(base + '/api/uploads', opts);
    if (!res.ok) {
      let msg = `Ошибка ${res.status}`;
      try { const j = await res.json(); if (j.error) msg = j.error; } catch {}
      throw new Error(msg);
    }
    return res.json();
  }

  return {
    getToken, setToken, upload,

    register: (dto) => req('POST', '/api/organizer/register', dto),
    login: (dto) => req('POST', '/api/organizer/login', dto),
    me: () => req('GET', '/api/organizer/me'),

    venues: () => req('GET', '/api/venues'),

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

    orgEvents: (filters = {}) => {
      const p = new URLSearchParams();
      for (const [k, v] of Object.entries(filters)) if (v !== '' && v != null) p.set(k, v);
      const qs = p.toString();
      return req('GET', '/api/organizer/events' + (qs ? '?' + qs : ''));
    },
    orgEvent: (id) => req('GET', `/api/organizer/events/${id}`),
    createEvent: (dto) => req('POST', '/api/organizer/events', dto),
    updateEvent: (id, dto) => req('PUT', `/api/organizer/events/${id}`, dto),
    eventOnline: (id) => req('GET', `/api/organizer/events/${id}/online`),
    eventBuyers: (id, q = '', page = 1) => {
      const p = new URLSearchParams();
      if (q) p.set('q', q);
      p.set('page', page);
      return req('GET', `/api/organizer/events/${id}/buyers?` + p.toString());
    },

    getEventLayout: (eventId) => req('GET', `/api/events/${eventId}/layout`).catch(() => null),
    saveEventLayout: (eventId, dto) => req('POST', `/api/events/${eventId}/layout`, dto),
    updateEventLayout: (eventId, dto) => req('PUT', `/api/events/${eventId}/layout`, dto),
  };
})();
