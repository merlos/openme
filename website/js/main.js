// openme website — main.js
// Minimal JS: smooth active nav, no heavy frameworks.

(function () {
  'use strict';

  // ── Active nav link on scroll ──────────────────────────────
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav__links a[href^="#"]');

  function updateActiveNav() {
    let current = '';
    sections.forEach(function (section) {
      const top = section.getBoundingClientRect().top;
      if (top <= 80) current = section.id;
    });
    navLinks.forEach(function (link) {
      link.classList.toggle('active', link.getAttribute('href') === '#' + current);
    });
  }

  window.addEventListener('scroll', updateActiveNav, { passive: true });
  updateActiveNav();

  // ── Copy code blocks on click ──────────────────────────────
  document.querySelectorAll('.codeblock pre').forEach(function (pre) {
    pre.style.position = 'relative';
    pre.style.cursor = 'pointer';

    const tip = document.createElement('span');
    tip.textContent = 'Copy';
    tip.style.cssText = [
      'position:absolute', 'top:10px', 'right:12px',
      'font-size:11px', 'font-family:var(--font-mono)',
      'color:var(--c-text-muted)', 'background:var(--c-surface)',
      'padding:2px 8px', 'border-radius:4px',
      'border:1px solid var(--c-border)',
      'pointer-events:none', 'opacity:0',
      'transition:opacity .15s'
    ].join(';');
    pre.appendChild(tip);

    pre.addEventListener('mouseenter', function () { tip.style.opacity = '1'; });
    pre.addEventListener('mouseleave', function () {
      tip.style.opacity = '0';
      tip.textContent = 'Copy';
    });

    pre.addEventListener('click', function () {
      const text = pre.querySelector('code').innerText;
      navigator.clipboard.writeText(text).then(function () {
        tip.textContent = 'Copied!';
        tip.style.opacity = '1';
      });
    });
  });

})();
