/*
 * Replays the hero ledger's subtraction the first time it comes into view: the
 * dropped rows strike out in sequence while the output size counts down.
 *
 * Progressive enhancement only. The markup already carries the finished state,
 * so anyone without JavaScript — or who has asked for reduced motion — sees the
 * answer rather than a half-played animation.
 */
(() => {
  const ledger = document.getElementById("ledger");
  const size = ledger?.querySelector("[data-count-from]");
  if (!ledger || !size) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const from = Number(size.dataset.countFrom);
  const to = Number(size.dataset.countTo);
  const settled = size.textContent;

  // Long enough to outlast the last row's staggered strike.
  const DURATION = 950;
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);

  const countDown = (startedAt) => {
    const progress = Math.min((performance.now() - startedAt) / DURATION, 1);
    size.textContent = `${(from + (to - from) * easeOut(progress)).toFixed(2)} GB`;
    if (progress < 1) requestAnimationFrame(() => countDown(startedAt));
    else size.textContent = settled;
  };

  const play = () => {
    ledger.classList.add("is-playing");
    countDown(performance.now());
  };

  // Seed the starting figure before the first paint, so the settled number never
  // flashes ahead of the countdown. Safe to do unconditionally: the output row
  // sits at the foot of a tall panel, so it only scrolls into view well after the
  // observer has fired and the count is already running.
  size.textContent = `${from.toFixed(2)} GB`;

  if (!("IntersectionObserver" in window)) return play();

  const observer = new IntersectionObserver(
    (entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      play();
    },
    { threshold: 0.35 }
  );
  observer.observe(ledger);
})();
