// Small progressive enhancements: nav border, scroll reveals, tour tabs, copy button.
document.documentElement.classList.add('js');

const nav = document.querySelector('.nav');
const onScroll = () => nav.classList.toggle('scrolled', scrollY > 8);
addEventListener('scroll', onScroll, { passive: true });
onScroll();

const io = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
}, { rootMargin: '0px 0px -8% 0px' });
document.querySelectorAll('.section .display, .section .sub, .card, .minis li, .tour, .ad, .steps li, .term, .checks li, .closer-card')
  .forEach((el, i) => { el.classList.add('reveal'); el.style.transitionDelay = `${(i % 3) * 80}ms`; io.observe(el); });

const tabs = [...document.querySelectorAll('.tabs [role="tab"]')];
const img = document.getElementById('tourImg');
const select = (tab) => {
  tabs.forEach((t) => { t.setAttribute('aria-selected', String(t === tab)); t.tabIndex = t === tab ? 0 : -1; });
  img.classList.add('swap');
  const next = new Image();
  next.src = tab.dataset.src;
  next.decode().catch(() => {}).then(() => {
    Object.assign(img, { src: tab.dataset.src, width: +tab.dataset.w, height: +tab.dataset.h, alt: tab.dataset.alt });
    img.classList.remove('swap');
  });
};
tabs.forEach((t, i) => {
  t.tabIndex = i === 0 ? 0 : -1;
  t.addEventListener('click', () => select(t));
  t.addEventListener('keydown', (e) => {
    const d = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
    if (!d) return;
    const n = tabs[(i + d + tabs.length) % tabs.length];
    n.focus(); select(n);
  });
});

document.querySelectorAll('.copy').forEach((b) => b.addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = 'Copied'; }
  catch { b.textContent = 'Press ⌘C'; }
  setTimeout(() => { b.textContent = 'Copy'; }, 1600);
}));

// Only one ad plays at a time.
const videos = document.querySelectorAll('.ad video');
videos.forEach((v) => v.addEventListener('play', () => videos.forEach((o) => o !== v && o.pause())));
