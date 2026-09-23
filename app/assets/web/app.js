// Suvi Share — browser client. Talks to the same JSON API the native apps use.
// No frameworks, no external requests: this must load instantly over a LAN.
(() => {
  'use strict';

  const API = '/api/suvi/v1';
  const $ = (id) => document.getElementById(id);

  const el = {
    peerLine: $('peer-line'),
    pinCard: $('pin-card'),
    pinForm: $('pin-form'),
    pinInput: $('pin-input'),
    pinError: $('pin-error'),
    downloadCard: $('download-card'),
    downloadList: $('download-list'),
    downloadSummary: $('download-summary'),
    downloadAll: $('download-all'),
    drop: $('drop'),
    fileInput: $('file-input'),
    textInput: $('text-input'),
    uploadList: $('upload-list'),
    sendBtn: $('send-btn'),
    clearBtn: $('clear-btn'),
    status: $('upload-status'),
  };

  let pin = '';
  let offer = null;          // {sessionId, files}
  let queued = [];           // File objects staged for upload
  let sending = false;

  // ------------------------------------------------------------- helpers

  function formatBytes(n) {
    if (n < 1024) return n + ' B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    let v = n / 1024, i = 0;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return (v >= 100 ? v.toFixed(0) : v.toFixed(1)) + ' ' + units[i];
  }

  function uid() {
    if (crypto.randomUUID) return crypto.randomUUID();
    return 'f' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  }

  async function getJson(url) {
    const res = await fetch(url, { cache: 'no-store' });
    const body = await res.json().catch(() => ({}));
    return { status: res.status, body };
  }

  function withPin(url) {
    return pin ? url + (url.includes('?') ? '&' : '?') + 'pin=' + encodeURIComponent(pin) : url;
  }

  function setStatus(text, isError) {
    el.status.textContent = text || '';
    el.status.className = isError ? 'error status' : 'muted status';
  }

  // ------------------------------------------------------------- startup

  async function init() {
    try {
      const { body } = await getJson(API + '/web-info');
      el.peerLine.textContent = 'Connected to ' + (body.alias || 'this device');
      if (body.pinRequired) {
        el.pinCard.classList.remove('hidden');
        el.pinInput.focus();
      }
      if (body.hasOffer) await loadOffer();
    } catch (e) {
      el.peerLine.textContent = 'Could not reach the device.';
    }
  }

  async function loadOffer() {
    const { status, body } = await getJson(withPin(API + '/prepare-download'));
    if (status === 401) {
      el.pinCard.classList.remove('hidden');
      if (pin) el.pinError.classList.remove('hidden');
      return false;
    }
    if (status !== 200) {           // 404 = nothing shared right now
      el.downloadCard.classList.add('hidden');
      return true;
    }
    offer = body;
    renderOffer();
    el.pinCard.classList.add('hidden');
    return true;
  }

  function renderOffer() {
    const files = Object.values(offer.files || {});
    el.downloadList.innerHTML = '';
    let total = 0;
    for (const f of files) {
      total += f.size;
      const li = document.createElement('li');
      li.className = 'item';
      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = f.fileName;
      const size = document.createElement('span');
      size.className = 'size';
      size.textContent = formatBytes(f.size);
      const btn = document.createElement('button');
      btn.className = 'act';
      btn.type = 'button';
      btn.textContent = 'Save';
      btn.addEventListener('click', () => downloadOne(f));
      li.append(name, size, btn);
      el.downloadList.appendChild(li);
    }
    el.downloadSummary.textContent =
      files.length + (files.length === 1 ? ' file · ' : ' files · ') + formatBytes(total);
    el.downloadCard.classList.toggle('hidden', files.length === 0);
    el.downloadAll.classList.toggle('hidden', files.length < 2);
  }

  function downloadOne(f) {
    const url = withPin(
      API + '/download?sessionId=' + encodeURIComponent(offer.sessionId) +
      '&fileId=' + encodeURIComponent(f.id));
    // Navigating triggers the browser's own download manager, which handles
    // huge files and resume far better than anything we could do in JS.
    const a = document.createElement('a');
    a.href = url;
    a.download = f.fileName;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  el.downloadAll.addEventListener('click', () => {
    const files = Object.values(offer.files || {});
    files.forEach((f, i) => setTimeout(() => downloadOne(f), i * 350));
  });

  // ----------------------------------------------------------- PIN gate

  el.pinForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    pin = el.pinInput.value.trim();
    el.pinError.classList.add('hidden');
    await loadOffer();
  });

  // ------------------------------------------------------------- upload

  function stage(files) {
    for (const f of files) queued.push(f);
    renderQueue();
  }

  function renderQueue() {
    el.uploadList.innerHTML = '';
    queued.forEach((f, idx) => {
      const li = document.createElement('li');
      li.className = 'item';
      li.dataset.idx = String(idx);

      const wrap = document.createElement('div');
      wrap.className = 'name';
      const name = document.createElement('div');
      name.className = 'filename';
      name.textContent = f.name;
      const bar = document.createElement('progress');
      bar.className = 'bar';
      bar.max = 100;
      bar.value = 0;
      wrap.append(name, bar);

      const size = document.createElement('span');
      size.className = 'size';
      size.textContent = formatBytes(f.size);

      const state = document.createElement('span');
      state.className = 'state';

      li.append(wrap, size, state);
      if (!sending) {
        const rm = document.createElement('button');
        rm.className = 'act';
        rm.type = 'button';
        rm.setAttribute('aria-label', 'Remove ' + f.name);
        rm.textContent = '✕';
        rm.addEventListener('click', () => { queued.splice(idx, 1); renderQueue(); });
        li.appendChild(rm);
      }
      el.uploadList.appendChild(li);
    });
    updateSendState();
  }

  function updateSendState() {
    const hasText = el.textInput.value.trim().length > 0;
    el.sendBtn.disabled = sending || (queued.length === 0 && !hasText);
    el.clearBtn.hidden = sending || (queued.length === 0 && !hasText);
  }

  el.textInput.addEventListener('input', updateSendState);

  el.clearBtn.addEventListener('click', () => {
    queued = [];
    el.textInput.value = '';
    renderQueue();
    setStatus('');
  });

  el.drop.addEventListener('click', () => el.fileInput.click());
  el.drop.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); el.fileInput.click(); }
  });
  el.fileInput.addEventListener('change', () => {
    stage(el.fileInput.files);
    el.fileInput.value = '';
  });

  ['dragenter', 'dragover'].forEach((ev) =>
    el.drop.addEventListener(ev, (e) => { e.preventDefault(); el.drop.classList.add('over'); }));
  ['dragleave', 'drop'].forEach((ev) =>
    el.drop.addEventListener(ev, (e) => { e.preventDefault(); el.drop.classList.remove('over'); }));
  el.drop.addEventListener('drop', (e) => {
    if (e.dataTransfer && e.dataTransfer.files.length) stage(e.dataTransfer.files);
  });
  // Don't let a stray drop outside the zone navigate away from the page.
  window.addEventListener('dragover', (e) => e.preventDefault());
  window.addEventListener('drop', (e) => e.preventDefault());

  el.sendBtn.addEventListener('click', send);

  async function send() {
    if (sending) return;
    const text = el.textInput.value.trim();
    if (!queued.length && !text) return;

    sending = true;
    renderQueue();
    setStatus('Waiting for the device to accept…');

    const ids = queued.map(() => uid());
    const payload = {
      info: {
        alias: navigator.platform ? ('Browser · ' + navigator.platform) : 'Browser',
        version: '1.0',
        deviceType: 'web',
        deviceModel: 'Web browser',
        fingerprint: 'web-' + uid(),
        port: 0,
        protocol: 'http',
        download: false,
      },
      files: {},
    };
    queued.forEach((f, i) => {
      payload.files[ids[i]] = {
        id: ids[i],
        fileName: f.name,
        size: f.size,
        fileType: f.type || 'application/octet-stream',
      };
    });
    if (text) payload.text = text;

    let prep;
    try {
      const res = await fetch(withPin(API + '/prepare-upload'), {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (res.status === 204) { finish('Nothing to send.', false); return; }
      if (res.status === 401) { finish('PIN required or incorrect.', true); return; }
      if (res.status === 403) { finish('The device declined.', true); return; }
      if (res.status === 409) { finish('The device is busy with another transfer.', true); return; }
      if (!res.ok) {
        const b = await res.json().catch(() => ({}));
        finish(b.message || ('Failed (HTTP ' + res.status + ')'), true);
        return;
      }
      prep = await res.json();
    } catch (e) {
      finish('Could not reach the device.', true);
      return;
    }

    let failed = 0;
    for (let i = 0; i < queued.length; i++) {
      const token = prep.files[ids[i]];
      const li = el.uploadList.querySelector('[data-idx="' + i + '"]');
      if (!token) { mark(li, 'skipped'); continue; }
      setStatus('Sending ' + (i + 1) + ' of ' + queued.length + '…');
      try {
        await upload(prep.sessionId, ids[i], token, queued[i], li);
        mark(li, 'done');
      } catch (e) {
        failed++;
        mark(li, 'failed');
      }
    }

    if (failed) finish(failed + ' file(s) failed to send.', true);
    else {
      queued = [];
      el.textInput.value = '';
      finish('Sent ✓', false);
      el.uploadList.innerHTML = '';
    }
  }

  function upload(sessionId, fileId, token, file, li) {
    // XHR rather than fetch: upload progress events are still the only
    // reliable way to drive a progress bar in every browser.
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      const url = API + '/upload?sessionId=' + encodeURIComponent(sessionId) +
        '&fileId=' + encodeURIComponent(fileId) + '&token=' + encodeURIComponent(token);
      xhr.open('POST', url, true);
      xhr.setRequestHeader('content-type', 'application/octet-stream');
      const meter = li && li.querySelector('progress.bar');
      xhr.upload.onprogress = (e) => {
        if (meter && e.lengthComputable) {
          meter.value = Math.round((e.loaded / e.total) * 100);
        }
      };
      xhr.onload = () => (xhr.status >= 200 && xhr.status < 300)
        ? resolve()
        : reject(new Error('HTTP ' + xhr.status));
      xhr.onerror = () => reject(new Error('network'));
      xhr.onabort = () => reject(new Error('aborted'));
      xhr.send(file);
    });
  }

  function mark(li, state) {
    if (!li) return;
    li.classList.add(state);
    const s = li.querySelector('.state');
    if (s) s.textContent = state === 'done' ? '✓' : state === 'failed' ? '!' : '–';
  }

  function finish(message, isError) {
    sending = false;
    setStatus(message, isError);
    renderQueue();
  }

  // Keep the offer fresh: the device may start or stop sharing at any time.
  setInterval(() => { if (!sending) loadOffer(); }, 5000);

  init();
})();
