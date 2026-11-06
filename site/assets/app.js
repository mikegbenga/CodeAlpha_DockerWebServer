(async () => {
  const el = document.getElementById('health');
  try {
    const t0 = performance.now();
    const res = await fetch('/healthz', { cache: 'no-store' });
    const body = await res.json();
    const ms = Math.round(performance.now() - t0);
    el.className = res.ok ? 'ok' : 'bad';
    el.textContent = `● ${body.status.toUpperCase()} · served by ${body.server} · ${ms} ms · request id ${res.headers.get('x-request-id') || 'n/a'}`;
  } catch (e) {
    el.className = 'bad';
    el.textContent = '● health endpoint unreachable';
  }
})();
