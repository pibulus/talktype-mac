// TalkType for Mac — the site's only script. Small on purpose.
(function () {
  // The HUD strip in the hero re-reads like a live take.
  const reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const hud = document.querySelector('[data-hud-text]');
  if (hud && !reducedMotion) {
    const lines = [
      'and the questionable playlist…',
      'ship it friday, not monday…',
      'two coffees, one idea, go…',
      'note to self: breathe…'
    ];
    let i = 0;
    setInterval(() => {
      if (document.hidden) return; // no repaints while the tab is backgrounded
      i = (i + 1) % lines.length;
      hud.style.opacity = '0';
      setTimeout(() => {
        hud.textContent = lines[i];
        hud.style.opacity = '1';
      }, 220);
    }, 4200);
    hud.style.transition = 'opacity 0.22s ease';
  }

  // Checkout: ask our function for a Square payment link, then hand the buyer
  // to Square. Card details never touch this page.
  const checkout = document.getElementById('checkout');
  if (checkout) {
    const label = checkout.querySelector('.label');
    const error = document.getElementById('checkout-error');

    const reset = () => {
      checkout.dataset.state = 'idle';
      checkout.disabled = false;
      checkout.removeAttribute('aria-busy');
      label.textContent = 'Continue to secure payment';
    };

    // Returning from Square can restore this page from bfcache with the button
    // still disabled and the label stuck on "Opening Square…".
    addEventListener('pageshow', (e) => { if (e.persisted) reset(); });

    checkout.addEventListener('click', async () => {
      if (checkout.dataset.state === 'busy') return;
      checkout.dataset.state = 'busy';
      checkout.disabled = true;
      checkout.setAttribute('aria-busy', 'true');
      label.textContent = 'Opening Square…';
      if (error) error.hidden = true;

      const request = {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{}'
      };
      // A stalled Square call must never leave the button disabled forever.
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
        if (error) error.hidden = false;
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

  // Soft reveal for sections. Off by default without IntersectionObserver.
  if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const targets = document.querySelectorAll('.step, .feature, .engine-row, .pricing-card, .faq details');
    targets.forEach((el) => {
      el.style.opacity = '0';
      el.style.transform = 'translateY(14px)';
      el.style.transition = 'opacity 0.6s ease, transform 0.6s cubic-bezier(0.22, 0.61, 0.36, 1)';
    });
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'none';
            io.unobserve(entry.target);
          }
        });
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.05 }
    );
    targets.forEach((el) => io.observe(el));

    // Failsafe: a section must never stay invisible because an observer
    // callback was missed (an odd viewport, a bfcache restore, a headless
    // screenshot). Everything is revealed after a few seconds regardless.
    setTimeout(() => {
      targets.forEach((el) => {
        el.style.opacity = '1';
        el.style.transform = 'none';
      });
    }, 2500);
  }
})();
