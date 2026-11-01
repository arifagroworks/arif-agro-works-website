/* Public presentation only; shared with the Android WebView homepage. */
(() => {
  'use strict';
  const body = document.body, hero = document.querySelector('.aaw-public .hero');
  if (!hero || body.dataset.motionReady) return;
  body.dataset.motionReady = 'true';
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  let paused = false, timer = null, active = 0, inView = true;
  const stage = document.createElement('div');
  stage.className = 'aaw-motion-stage'; stage.setAttribute('aria-hidden', 'true');
  const images = ['welding', 'shed', 'tanks'].map((name, i) => {
    const img = document.createElement('img');
    img.src = `assets/public-${name}-hd.webp`; img.alt = '';
    img.decoding = 'async'; img.className = i === 0 ? 'is-current' : '';
    stage.append(img); return img;
  });
  const sparks = document.createElement('div'); sparks.className = 'aaw-sparks';
  for (let i = 0; i < 18; i++) {
    const spark = document.createElement('i');
    spark.style.setProperty('--n', i); sparks.append(spark);
  }
  stage.append(sparks); hero.prepend(stage);
  const button = document.createElement('button');
  button.type = 'button'; button.className = 'aaw-motion-toggle';
  button.setAttribute('aria-pressed', 'false');
  hero.append(button);
  const language = () => {
    const hi = document.documentElement.lang === 'hi';
    button.textContent = paused ? (hi ? '▶ मोशन चलाएँ' : '▶ Play motion') : (hi ? 'Ⅱ मोशन रोकें' : 'Ⅱ Pause motion');
    button.setAttribute('aria-pressed', String(paused));
  };
  function sync() {
    const running = !paused && !reduced.matches && !document.hidden && inView;
    body.classList.toggle('aaw-motion-running', running);
    button.hidden = reduced.matches;
    clearInterval(timer); timer = null;
    if (running) timer = setInterval(() => {
      const next = (active + 1) % images.length;
      if (!images[next].complete || !images[next].naturalWidth) return;
      images[active].classList.remove('is-current');
      images[next].classList.add('is-current'); active = next;
    }, 6500);
  }
  button.addEventListener('click', () => { paused = !paused; language(); sync(); });
  document.addEventListener('visibilitychange', sync);
  reduced.addEventListener('change', sync);
  new MutationObserver(language).observe(document.documentElement, { attributes: true, attributeFilter: ['lang'] });
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (entry.target === hero) { inView = entry.isIntersecting; sync(); }
        else if (entry.isIntersecting) { entry.target.classList.add('aaw-revealed'); observer.unobserve(entry.target); }
      }
    }, { threshold: 0.08 });
    observer.observe(hero);
    document.querySelectorAll('.aaw-public .section .heading, .aaw-public .photo-card, .aaw-public .service, .aaw-public .aaw-about-visual').forEach((el, i) => {
      el.classList.add('aaw-reveal'); el.style.setProperty('--delay', `${i % 3 * 90}ms`); observer.observe(el);
    });
  }
  language(); sync();
})();
