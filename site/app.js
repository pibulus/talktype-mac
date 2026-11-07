// TalkType for Mac — the shop as an instrument.
//
// Plate 01 is three scenes on one stage. Each scene demonstrates a different
// piece of the real app: hold-to-catch, tap-and-keep-talking, and the messy
// sentence that arrives tidied. Plate 02 is copy and a checkout link.
//
// Speech comes from the browser first (no key, no server, nothing stored). The
// proxy lane is written and waiting behind DEMO_ENGINE for the day a keyed
// Deepgram path exists on this origin; see docs/SITE.md before flipping it.
(function () {
  'use strict';

  const DEMO_ENGINE = 'browser'; // 'browser' | 'proxy'

  const reducedMotion = window.matchMedia
    ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
    : false;

  // ------------------------------------------------------------------ scenes

  const SCENES = {
    catch: {
      app: 'Messages',
      context: 'Mum, 6:02 pm · Dinner at 7?',
      caption: 'A message home, sent from the kitchen while the kettle goes.',
      hint: 'Hold <kbd>⌥</kbd> Option, or press the ghost',
      chip: {
        pending: 'Nothing sent yet',
        listening: 'Listening, holding the thread',
        processing: 'Writing it down',
        landed: 'Message landed'
      },
      demo: 'Running ten minutes late, start without me.',
      timer: false,
      prompts: [
        ['Try this out loud', '“Twinkle, twinkle, little star, how I wonder what you are.”'],
        ['One more easy', '“Row, row, row your boat, gently down the stream.”'],
        ['An ordinary morning', '“Running ten minutes late, start without me.”'],
        ['Never heard before', '“pibulus”']
      ]
    },
    handsfree: {
      app: 'Mail',
      context: 'Priya, this morning · Can we still do Friday?',
      caption: 'A reply that starts before the blank page gets a vote.',
      hint: 'Tap the ghost once, then keep talking',
      chip: {
        pending: 'Reply not started',
        listening: 'Paused, no hurry',
        processing: 'Writing it down',
        landed: 'Reply ready'
      },
      demo: 'Thanks for the note. Friday works, and the deck can wait until Monday so nobody is writing slides at midnight.',
      timer: true,
      prompts: [
        ['The hard one', '“Worcestershire sauce and a glass of water.”'],
        ['Two tricky names', '“Statler and Waldorf, heckling from the balcony.”'],
        ['Local knowledge', '“Melbourne, then a flat white in Carlton.”'],
        ['Real work, dictated', '“Email Sam that the doctype is fixed and the invoice went out.”']
      ]
    },
    polish: {
      app: 'Notes',
      context: 'Friday plan · last edited Tuesday',
      caption: 'A note caught mid thought, before it wanders off.',
      hint: 'Say it messy. The tidying happens after',
      chip: {
        pending: 'Blank note',
        listening: 'Mid thought',
        processing: 'Tidying',
        landed: 'Tidied and landed'
      },
      demo: 'so um I was thinking we could maybe push it to like half past',
      clean: 'Push it to half past and see how it goes.',
      timer: false,
      prompts: [
        ['Say it messy', '“so um I was thinking we could maybe push it to like half past”'],
        ['Say it twice', '“Can we can we move the thing, the meeting, to after lunch”'],
        ['Think out loud', '“I reckon the invoice is done but I should double check it”'],
        ['Fill the pause', '“Right so the plan is, is to send it Friday”']
      ]
    }
  };

  const SCENE_ORDER = ['catch', 'handsfree', 'polish'];

  const STRINGS = {
    pending: 'Nothing said yet. The capsule is holding the pen.',
    listening: 'Listening, and in no hurry.',
    landed: 'Words landed at the cursor, already yours to send.',
    micFallback:
      'This browser cannot hear, or the mic is blocked. Nothing broken, just a demo with no ears. The Mac version listens on the device itself, offline, and asks for the microphone and nothing else.',
    demoNote: 'The demo listens in this tab and keeps nothing.'
  };

  // ------------------------------------------------------------------ nodes

  const tabs = Array.from(document.querySelectorAll('.mode'));
  const thumb = document.getElementById('modes-thumb');
  const stage = document.getElementById('stage');
  const capsule = document.getElementById('live-hud');
  const capsuleText = document.getElementById('capsule-text');
  const capsuleMask = document.getElementById('capsule-mask');
  const capsuleTrack = document.getElementById('capsule-track');
  const capsuleGhost = document.getElementById('hud-trigger');
  const sticker = document.getElementById('sticker');
  const surfaceText = document.getElementById('surface-text');
  const surfaceApp = document.getElementById('surface-app');
  const surfaceContext = document.getElementById('surface-context');
  const surfaceChip = document.getElementById('surface-chip');
  const promptLead = document.getElementById('prompt-lead');
  const promptLine = document.getElementById('prompt-line');
  const promptNext = document.getElementById('prompt-next');
  const captionEl = document.getElementById('stage-caption');
  const hint = document.getElementById('hud-hint');

  if (!stage || !capsule || !surfaceText) return; // secondary pages only load the checkout

  // ------------------------------------------------------------------ state

  let scene = 'catch';
  let promptIndex = { catch: 0, handsfree: 0, polish: 0 };
  let phase = 'pending';
  let shown = '';           // what the capsule is currently showing
  let wordTimer = null;
  let holdTimer = null;
  let tickTimer = null;
  let startedAt = 0;
  let recognition = null;
  let live = false;         // a real microphone session is running
  let hasLanded = false;    // the opening demonstration already played
  let demoNoteShown = false;

  const sceneOf = (key) => SCENES[key];

  function setPhase(next) {
    phase = next;
    capsule.dataset.phase = next === 'pending' ? 'ready' : next;
    stage.dataset.phase = next;
    updateChip();
  }

  function updateChip() {
    const cfg = sceneOf(scene);
    if (!cfg || !surfaceChip) return;
    const label = phase === 'pending' ? cfg.chip.pending
      : phase === 'landed' ? cfg.chip.landed
      : phase === 'processing' ? (cfg.chip.processing || cfg.chip.listening)
      : cfg.chip.listening;
    let text = label;
    if (cfg.timer && phase === 'listening') text = fmt(clock()) + ' · ' + label;
    surfaceChip.textContent = text;
    surfaceChip.classList.toggle('is-quiet', phase === 'pending');
  }

  function clock() {
    return startedAt ? Date.now() - startedAt : 0;
  }
  function fmt(ms) {
    const total = Math.floor(ms / 1000);
    return Math.floor(total / 60) + ':' + String(total % 60).padStart(2, '0');
  }

  // ---- the capsule line -----------------------------------------------------

  function paintCapsule(text, placeholder) {
    shown = text;
    capsuleText.textContent = text;
    capsuleText.classList.toggle('is-placeholder', !!placeholder);
    const overflow = capsuleTrack && capsuleMask && capsuleTrack.scrollWidth > capsuleMask.clientWidth + 2;
    capsuleMask.classList.toggle('masked', !placeholder && !!overflow);
    if (capsuleTrack) capsuleTrack.scrollLeft = placeholder ? 0 : capsuleTrack.scrollWidth;
    if (!reducedMotion) {
      capsule.classList.add('word-bounce');
      setTimeout(() => capsule.classList.remove('word-bounce'), 130);
    }
  }

  function clearCapsule(placeholderText) {
    paintCapsule(placeholderText || 'Hold ⌥ and the ghost starts listening.', true);
  }

  // ---- the surface ---------------------------------------------------------

  function paintSurface(text, opts) {
    const caret = !!(opts && opts.caret);
    const empty = !text && !caret;
    surfaceText.textContent = text || (empty ? 'Words land here.' : '');
    surfaceText.classList.toggle('is-empty', empty);
    surfaceText.classList.toggle('is-caret', caret);
  }

  function blankSurface() {
    paintSurface('', { caret: false });
    setPhase('pending');
  }

  // A small, honest tidy for the note scene: drop the fillers, keep the words.
  function tidy(text) {
    let out = String(text || '')
      .replace(/\b(?:um+|uh+|erm+|hmm+)\b[ ,]*/gi, ' ')
      .replace(/\byou know\b[ ,]*/gi, ' ')
      .replace(/\bI mean\b[ ,]*/gi, ' ')
      .replace(/\b(\w+)\s+\1\b/gi, '$1')
      .replace(/\s+/g, ' ')
      .replace(/\s+([,.!?])/g, '$1')
      .replace(/,\s*,/g, ',')
      .trim()
      .replace(/^so\s+/i, '');
    if (!out) return out;
    out = out.charAt(0).toUpperCase() + out.slice(1);
    if (!/[.!?]$/.test(out)) out += '.';
    return out;
  }

  // ---- the demonstration take ---------------------------------------------

  function stopTimers() {
    if (wordTimer) { clearInterval(wordTimer); wordTimer = null; }
    if (holdTimer) { clearTimeout(holdTimer); holdTimer = null; }
    if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }
  }

  function tickTimerOn() {
    const cfg = sceneOf(scene);
    if (!cfg.timer) return;
    if (tickTimer) clearInterval(tickTimer);
    tickTimer = setInterval(updateChip, 500);
  }

  function playTake(sentence, opts) {
    const cfg = sceneOf(scene);
    const done = (opts && opts.done) || function () {};
    const polish = !!(opts && opts.polish);

    stopTimers();
    startedAt = Date.now();
    setPhase('listening');
    tickTimerOn();

    const words = sentence.split(' ');
    let i = 0;
    paintSurface('', { caret: true });
    paintCapsule(words[0] || '', false);

    wordTimer = setInterval(function () {
      i += 1;
      if (i < words.length) {
        const partial = words.slice(0, i + 1).join(' ');
        paintCapsule(partial, false);
        if (polish) paintSurface(partial, { caret: true });
        return;
      }
      clearInterval(wordTimer);
      wordTimer = null;
      if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }

      // pause for a beat, the way a real take settles
      setPhase('processing');
      paintCapsule(polish ? 'Tidying…' : 'Writing it down…', true);

      holdTimer = setTimeout(function () {
        setPhase('landed');
        const finalText = polish && cfg.clean ? cfg.clean : sentence;
        paintSurface(finalText, { caret: polish });
        clearCapsule('Hold ⌥ and the ghost starts listening.');
        done();
      }, polish ? 1500 : 620);
    }, 120);
  }

  // ---- the opening demo: type it out, then hand over the empty page --------

  function openingDemo() {
    if (hasLanded) return;
    if (phase === 'listening' || phase === 'processing') return;
    hasLanded = true;
    const cfg = sceneOf(scene);
    playTake(cfg.demo, {
      polish: scene === 'polish',
      done: function () {
        // show the result, then blank it: the empty field is the invitation.
        holdTimer = setTimeout(function () {
          if (live) return;
          blankSurface();
          clearCapsule('The pen is out. Say something.');
        }, reducedMotion ? 3000 : 2600);
      }
    });
  }

  // ---- prompt deck --------------------------------------------------------

  function paintPrompt() {
    const cfg = sceneOf(scene);
    const list = cfg.prompts;
    const idx = promptIndex[scene] || 0;
    const item = list[idx % list.length];
    promptLead.textContent = item[0];
    promptLine.textContent = item[1];
  }

  function nextPrompt() {
    const list = sceneOf(scene).prompts;
    promptIndex[scene] = ((promptIndex[scene] || 0) + 1) % list.length;
    paintPrompt();
  }

  // ---- live microphone ----------------------------------------------------

  function speechEngine() {
    return window.SpeechRecognition || window.webkitSpeechRecognition || null;
  }

  function startLive() {
    if (live) { finishLive(); return; }

    stopTimers();
    live = true;
    startedAt = Date.now();
    setPhase('listening');
    tickTimerOn();
    paintSurface('', { caret: true });
    paintCapsule('Listening, and in no hurry.', true);

    if (hint && !demoNoteShown) {
      demoNoteShown = true;
    }

    const Engine = DEMO_ENGINE === 'browser' ? speechEngine() : null;
    if (!Engine) {
      // no ears: play the scene's own take and say plainly why
      live = false;
      playTake(sceneOf(scene).demo, {
        polish: scene === 'polish',
        done: function () {
          if (hint) hint.textContent = STRINGS.micFallback;
          setTimeout(function () { if (hint) hint.innerHTML = sceneOf(scene).hint; }, 9000);
        }
      });
      return;
    }

    let latest = '';
    let stopped = false;

    const stop = function () {
      if (stopped) return;
      stopped = true;
      try { recognition && recognition.stop(); } catch (_) {}
    };

    try {
      recognition = new Engine();
      recognition.continuous = false;
      recognition.interimResults = true;
      recognition.lang = 'en-AU';

      recognition.onresult = function (event) {
        let combined = '';
        for (let r = 0; r < event.results.length; r++) {
          combined += event.results[r][0].transcript;
        }
        latest = combined.trim().slice(0, 240);
        if (latest) paintCapsule(latest, false);
      };

      recognition.onerror = function () { stop(); };

      recognition.onend = function () {
        recognition = null;
        if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }
        const text = latest || sceneOf(scene).demo;
        setPhase('processing');
        paintCapsule(scene === 'polish' ? 'Tidying…' : 'Writing it down…', true);
        if (scene === 'polish') paintSurface(text, { caret: true });
        setTimeout(function () {
          const cfg = sceneOf(scene);
          setPhase('landed');
          const spoken = latest || cfg.demo;
          paintSurface(scene === 'polish' ? tidy(spoken) : spoken, { caret: scene === 'polish' });
          clearCapsule('Hold ⌥ and the ghost starts listening.');
          live = false;
          if (hint) hint.innerHTML = sceneOf(scene).hint;
        }, scene === 'polish' ? 1400 : 560);
      };

      recognition.start();
      setTimeout(stop, 15000);
    } catch (_) {
      live = false;
      recognition = null;
      playTake(sceneOf(scene).demo, { polish: scene === 'polish' });
    }
  }

  function finishLive() {
    if (recognition) {
      try { recognition.stop(); } catch (_) {}
    }
  }

  // ---- scenes -------------------------------------------------------------

  function setScene(key, opts) {
    if (!SCENES[key]) return;
    const changed = key !== scene;
    scene = key;

    stage.dataset.mode = key;
    stage.dataset.app = SCENES[key].app;
    surfaceApp.textContent = SCENES[key].app;
    if (surfaceContext) surfaceContext.textContent = SCENES[key].context;
    captionEl.textContent = SCENES[key].caption;
    hint.innerHTML = SCENES[key].hint;

    tabs.forEach(function (tab) {
      const on = tab.dataset.mode === key;
      tab.setAttribute('aria-selected', on ? 'true' : 'false');
      tab.tabIndex = on ? 0 : -1;
      tab.classList.toggle('is-on', on);
      if (on) stage.setAttribute('aria-labelledby', tab.id);
    });

    paintPrompt();

    if (changed) {
      stopTimers();
      if (recognition) { try { recognition.stop(); } catch (_) {} recognition = null; }
      live = false;
      paintSurface('', { caret: false });
      setPhase('pending');
      clearCapsule('The pen is out. Say something.');
    }

    if (!(opts && opts.silent) && changed) {
      playTake(SCENES[key].demo, { polish: key === 'polish', done: function () {} });
    }
    placeThumb();
  }

  // ---- the sliding thumb --------------------------------------------------

  function placeThumb() {
    if (!thumb) return;
    const on = tabs.find(function (t) { return t.dataset.mode === scene; }) || tabs[0];
    if (!on) return;
    thumb.style.width = on.offsetWidth + 'px';
    thumb.style.setProperty('--thumb-x', on.offsetLeft + 'px');
  }

  // ---- wiring -------------------------------------------------------------

  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () {
      const key = tab.dataset.mode;
      const atTop = window.scrollY < window.innerHeight * 0.5;
      setScene(key);
      if (!atTop) window.scrollTo({ top: 0, behavior: reducedMotion ? 'auto' : 'smooth' });
    });

    tab.addEventListener('keydown', function (e) {
      let next = null;
      if (e.key === 'ArrowRight') next = (i + 1) % tabs.length;
      else if (e.key === 'ArrowLeft') next = (i - 1 + tabs.length) % tabs.length;
      else if (e.key === 'Home') next = 0;
      else if (e.key === 'End') next = tabs.length - 1;
      if (next === null) return;
      e.preventDefault();
      tabs[next].focus();
      setScene(tabs[next].dataset.mode);
    });
  });

  if (promptNext) promptNext.addEventListener('click', nextPrompt);
  if (capsuleGhost) capsuleGhost.addEventListener('click', startLive);
  if (sticker) sticker.addEventListener('click', startLive);

  // holding Option on the page runs the scene's take, like the real shortcut
  window.addEventListener('keydown', function (e) {
    if (e.key !== 'Alt' || e.repeat || live) return;
    if (document.activeElement === promptNext) return;
    playTake(sceneOf(scene).demo, { polish: scene === 'polish' });
  });

  window.addEventListener('keyup', function (e) {
    if (e.key !== 'Alt') return;
    if (wordTimer) {
      clearInterval(wordTimer);
      wordTimer = null;
    }
  });

  window.addEventListener('resize', placeThumb);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(placeThumb);

  // first paint
  setScene('catch', { silent: true });
  paintSurface('', { caret: false });
  setPhase('pending');
  placeThumb();
  requestAnimationFrame(placeThumb);

  if (reducedMotion) {
    // no auto-play for anyone who asked the room to sit still: land it at rest
    paintCapsule('Hold ⌥ and the ghost starts listening.', true);
    paintSurface(sceneOf(scene).demo, { caret: false });
    setPhase('landed');
  } else {
    setTimeout(openingDemo, 650);
  }

  // ------------------------------------------------------------------ checkout

  const checkout = document.getElementById('checkout');
  if (checkout) {
    const label = checkout.querySelector('.label');
    const error = document.getElementById('checkout-error');

    const reset = function () {
      checkout.dataset.state = 'idle';
      checkout.removeAttribute('aria-disabled');
      checkout.removeAttribute('aria-busy');
      if (label) label.textContent = 'Pay A$29';
    };

    addEventListener('pageshow', function (e) { if (e.persisted) reset(); });

    checkout.addEventListener('click', async function () {
      if (checkout.dataset.state === 'busy') return;
      checkout.dataset.state = 'busy';
      checkout.setAttribute('aria-disabled', 'true');
      checkout.setAttribute('aria-busy', 'true');
      if (label) label.textContent = 'Opening Square…';
      if (error) error.hidden = true;

      const request = {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{}'
      };
      if (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) {
        request.signal = AbortSignal.timeout(12000);
      }

      try {
        const res = await fetch('/api/checkout', request);
        const data = await res.json().catch(function () { return {}; });
        if (!res.ok || !data.checkoutUrl) throw new Error(data.error || 'no checkout');
        window.location.assign(data.checkoutUrl);
      } catch (_) {
        reset();
        if (error) { error.hidden = false; error.tabIndex = -1; error.focus(); }
      }
    });
  }

  // ------------------------------------------------------------------ confetti

  const params = new URLSearchParams(location.search);
  if (params.has('checkout_id')) {
    const note = document.getElementById('paid-note');
    if (note) note.hidden = false;
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) confetti();
  }

  function confetti() {
    const canvas = document.createElement('canvas');
    canvas.setAttribute('aria-hidden', 'true');
    Object.assign(canvas.style, {
      position: 'fixed', inset: '0', width: '100%', height: '100%',
      pointerEvents: 'none', zIndex: '9999'
    });
    document.body.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const resize = function () {
      canvas.width = innerWidth * dpr;
      canvas.height = innerHeight * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    addEventListener('resize', resize);

    const colours = ['#ff60e0', '#ff82ca', '#ff9a85', '#ffb060', '#ffcf40', '#2bb59a'];
    const pieces = Array.from({ length: 110 }, function () {
      return {
        x: innerWidth / 2 + (Math.random() - 0.5) * innerWidth * 0.55,
        y: -20 - Math.random() * innerHeight * 0.35,
        w: 5 + Math.random() * 7,
        h: 8 + Math.random() * 10,
        vx: (Math.random() - 0.5) * 2.4,
        vy: 2.6 + Math.random() * 3.4,
        rot: Math.random() * Math.PI,
        vr: (Math.random() - 0.5) * 0.22,
        colour: colours[(Math.random() * colours.length) | 0],
        sway: Math.random() * Math.PI * 2
      };
    });

    const started = performance.now();
    const tick = function (now) {
      ctx.clearRect(0, 0, innerWidth, innerHeight);
      const life = (now - started) / 3600;
      for (const p of pieces) {
        p.sway += 0.03;
        p.x += p.vx + Math.sin(p.sway) * 0.8;
        p.y += p.vy;
        p.vy += 0.035;
        p.rot += p.vr;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.globalAlpha = Math.max(0, 1 - life * 0.9);
        ctx.fillStyle = p.colour;
        ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        ctx.restore();
      }
      if (life < 1.05) requestAnimationFrame(tick);
      else {
        canvas.remove();
        removeEventListener('resize', resize);
      }
    };
    requestAnimationFrame(tick);
  }

  // ------------------------------------------------------------------ stamp

  fetch('/version.json')
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(function (v) {
      const el = document.getElementById('version');
      if (el && v && v.version) el.textContent = 'v' + v.version;
    })
    .catch(function () {});
})();
