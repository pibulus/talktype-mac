// TalkType for Mac — the site's only script. Small on purpose.
(function () {
  // The HUD strip in the hero re-reads like a live take.
  const hud = document.querySelector('[data-hud-text]');
  if (hud) {
    const lines = [
      'and the questionable playlist…',
      'ship it friday, not monday…',
      'two coffees, one idea, go…',
      'note to self: breathe…'
    ];
    let i = 0;
    setInterval(() => {
      i = (i + 1) % lines.length;
      hud.style.opacity = '0';
      setTimeout(() => {
        hud.textContent = lines[i];
        hud.style.opacity = '1';
      }, 220);
    }, 4200);
    hud.style.transition = 'opacity 0.22s ease';
  }

  // Version stamp: the artifact should be able to answer what it is.
  fetch('version.json')
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
