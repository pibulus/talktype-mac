// TalkType for Mac — live interactive HUD preview + Square checkout.
(function () {
  const reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const hudEl = document.getElementById('live-hud');
  const hudText = document.querySelector('[data-hud-text]');
  const hudScroll = document.getElementById('hud-scroll');
  const hudTrack = document.getElementById('hud-track');
  const hudTrigger = document.getElementById('hud-trigger');
  const hudHint = document.getElementById('hud-hint');
  const popText = document.querySelector('[data-pop-text]');
  const popGhost = document.querySelector('.pop-ghost');
  const mhRows = [
    document.querySelector('[data-mh-0]'),
    document.querySelector('[data-mh-1]'),
    document.querySelector('[data-mh-2]')
  ];

  const demoTakes = [
    'Friday works. Bring the good coffee and the questionable playlist — the demo script is already in the drive.',
    'Ship the beta Thursday, not Friday. All notarization checks passed on both Apple Silicon and Intel.',
    'Two coffees, one idea, go. No window to open, no dock icon to hunt down, just hold Option and talk.',
    'Invoice for the November workshop attached. Thanks again for having us in the studio.'
  ];

  let takeIndex = 0;
  let wordTimer = null;
  let cycleTimer = null;
  let isUserInteracting = false;
  let recognition = null;
  let historyList = [
    demoTakes[0],
    demoTakes[1],
    demoTakes[3]
  ];

  function updateHudText(text) {
    if (!hudText) return;
    hudText.textContent = text;
    if (hudScroll) {
      hudScroll.classList.toggle('masked', text.length > 28);
    }
    if (hudTrack) {
      hudTrack.scrollLeft = hudTrack.scrollWidth;
    }
    if (hudEl && !reducedMotion) {
      hudEl.classList.add('word-bounce');
      setTimeout(() => hudEl.classList.remove('word-bounce'), 130);
    }
  }

  function pushToHistory(cleanTake) {
    if (popText) popText.textContent = cleanTake;
    if (historyList[0] !== cleanTake) {
      historyList = [cleanTake, historyList[0], historyList[1]];
    }
    mhRows.forEach((row, idx) => {
      if (row && historyList[idx]) row.textContent = historyList[idx];
    });
  }

  function clearDemoTimers() {
    if (wordTimer) { clearInterval(wordTimer); wordTimer = null; }
    if (cycleTimer) { clearTimeout(cycleTimer); cycleTimer = null; }
  }

  function playSimulatedTake(sentence, onComplete) {
    clearDemoTimers();
    if (!hudEl || !hudText) return;
    const words = sentence.split(' ');
    let idx = 0;
    hudEl.dataset.phase = 'listening';
    updateHudText(words[0] || '');

    wordTimer = setInterval(() => {
      if (document.hidden && !isUserInteracting) return;
      idx += 1;
      if (idx < words.length) {
        updateHudText(words.slice(0, idx + 1).join(' '));
      } else {
        clearInterval(wordTimer);
        wordTimer = null;
        // Phase 2: processing waveform
        hudEl.dataset.phase = 'processing';
        cycleTimer = setTimeout(() => {
          // Phase 3: ready + paste into popover & recent takes
          hudEl.dataset.phase = 'ready';
          pushToHistory(sentence);
          cycleTimer = setTimeout(() => {
            if (onComplete) onComplete();
          }, 1400);
        }, 680);
      }
    }, 155);
  }

  function startAutoLoop() {
    if (reducedMotion || !hudEl) return;
    const step = () => {
      if (isUserInteracting) return;
      const sentence = demoTakes[takeIndex % demoTakes.length];
      takeIndex += 1;
      playSimulatedTake(sentence, () => {
        if (!isUserInteracting) {
          cycleTimer = setTimeout(step, 900);
        }
      });
    };
    step();
  }

  // Interactive preview: click the ghost (or hold Option) to trigger a live take.
  function triggerInteractiveDemo() {
    if (!hudEl) return;
    const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;

    if (isUserInteracting && recognition) {
      recognition.stop();
      return;
    }

    clearDemoTimers();
    isUserInteracting = true;
    hudEl.dataset.activeHold = 'true';
    hudEl.dataset.phase = 'listening';

    if (SpeechRec) {
      try {
        recognition = new SpeechRec();
        recognition.continuous = false;
        recognition.interimResults = true;
        recognition.lang = 'en-AU';
        updateHudText('Listening — speak a sentence…');
        if (hudHint) hudHint.innerHTML = 'Listening live (15s preview) · click ghost to finish';

        const stopTimeout = setTimeout(() => {
          if (recognition) recognition.stop();
        }, 15000);

        let latestTranscript = '';
        recognition.onresult = (event) => {
          let combined = '';
          for (let i = 0; i < event.results.length; i++) {
            combined += event.results[i][0].transcript;
          }
          latestTranscript = combined.slice(0, 220);
          if (latestTranscript) updateHudText(latestTranscript);
        };

        const finishLive = () => {
          clearTimeout(stopTimeout);
          recognition = null;
          hudEl.dataset.activeHold = 'false';
          const finalClean = (latestTranscript || demoTakes[takeIndex % demoTakes.length]).trim();
          hudEl.dataset.phase = 'processing';
          setTimeout(() => {
            hudEl.dataset.phase = 'ready';
            pushToHistory(finalClean);
            if (hudHint) hudHint.innerHTML = 'Hold <kbd>⌥ Option</kbd> right now or click the ghost to try it';
            setTimeout(() => {
              isUserInteracting = false;
              startAutoLoop();
            }, 2200);
          }, 550);
        };

        recognition.onend = finishLive;
        recognition.onerror = () => {
          clearTimeout(stopTimeout);
          recognition = null;
          // Graceful fallback if mic permission is declined
          const fallback = demoTakes[takeIndex % demoTakes.length];
          takeIndex += 1;
          playSimulatedTake(fallback, () => {
            hudEl.dataset.activeHold = 'false';
            isUserInteracting = false;
            if (hudHint) hudHint.innerHTML = 'Hold <kbd>⌥ Option</kbd> right now or click the ghost to try it';
            startAutoLoop();
          });
        };

        recognition.start();
        return;
      } catch (_) {
        // Fall through to simulated take
      }
    }

    const sample = demoTakes[takeIndex % demoTakes.length];
    takeIndex += 1;
    playSimulatedTake(sample, () => {
      hudEl.dataset.activeHold = 'false';
      isUserInteracting = false;
      startAutoLoop();
    });
  }

  if (hudTrigger) {
    hudTrigger.addEventListener('click', triggerInteractiveDemo);
  }
  if (popGhost) {
    popGhost.style.cursor = 'pointer';
    popGhost.addEventListener('click', triggerInteractiveDemo);
  }

  // Holding ⌥ Option on the keyboard triggers the HUD right on the page
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Alt' && !e.repeat && hudEl && !isUserInteracting) {
      isUserInteracting = true;
      hudEl.dataset.activeHold = 'true';
      if (hudHint) hudHint.innerHTML = 'Holding <kbd>⌥ Option</kbd> — release to paste at cursor';
      const sample = demoTakes[takeIndex % demoTakes.length];
      takeIndex += 1;
      playSimulatedTake(sample, () => {});
    }
  });

  window.addEventListener('keyup', (e) => {
    if (e.key === 'Alt' && hudEl && hudEl.dataset.activeHold === 'true') {
      clearDemoTimers();
      hudEl.dataset.activeHold = 'false';
      hudEl.dataset.phase = 'processing';
      setTimeout(() => {
        hudEl.dataset.phase = 'ready';
        if (hudText && hudText.textContent) {
          pushToHistory(hudText.textContent);
        }
        if (hudHint) hudHint.innerHTML = 'Hold <kbd>⌥ Option</kbd> right now or click the ghost to try it';
        setTimeout(() => {
          isUserInteracting = false;
          startAutoLoop();
        }, 1800);
      }, 420);
    }
  });

  startAutoLoop();

  // Checkout: ask our function for a Square payment link, then hand the buyer
  // to Square. Card details never touch this page.
  const checkout = document.getElementById('checkout');
  if (checkout) {
    const label = checkout.querySelector('.label');
    const error = document.getElementById('checkout-error');

    const reset = () => {
      checkout.dataset.state = 'idle';
      checkout.removeAttribute('aria-disabled');
      checkout.removeAttribute('aria-busy');
      label.textContent = 'Pay A$29';
    };

    addEventListener('pageshow', (e) => { if (e.persisted) reset(); });

    checkout.addEventListener('click', async () => {
      if (checkout.dataset.state === 'busy') return;
      checkout.dataset.state = 'busy';
      checkout.setAttribute('aria-disabled', 'true');
      checkout.setAttribute('aria-busy', 'true');
      label.textContent = 'Opening Square…';
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
        const data = await res.json().catch(() => ({}));
        if (!res.ok || !data.checkoutUrl) throw new Error(data.error || 'no checkout');
        window.location.assign(data.checkoutUrl);
      } catch (e) {
        reset();
        if (error) { error.hidden = false; error.tabIndex = -1; error.focus(); }
      }
    });
  }

  // Returning from Square: a little peach confetti, once, if motion is welcome.
  const params = new URLSearchParams(location.search);
  const paid = params.has('checkout_id');
  if (paid) {
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
    const resize = () => {
      canvas.width = innerWidth * dpr;
      canvas.height = innerHeight * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    addEventListener('resize', resize);

    const colours = ['#ff60e0', '#ff82ca', '#ff9a85', '#ffb060', '#ffcf40', '#2bb59a'];
    const pieces = Array.from({ length: 110 }, () => ({
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
    }));

    const started = performance.now();
    const tick = (now) => {
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

  // Version stamp: the artifact should be able to answer what it is.
  fetch('/version.json')
    .then((r) => (r.ok ? r.json() : null))
    .then((v) => {
      const el = document.getElementById('version');
      if (el && v && v.version) el.textContent = 'v' + v.version;
    })
    .catch(() => {});
})();
