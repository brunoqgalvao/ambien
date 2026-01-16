<script>
  let { size = 36, showText = true } = $props();
</script>

<a href="/" class="logo" style="--size: {size}px">
  <div class="logo-mark">
    <svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
      <circle cx="50" cy="50" r="45" fill="url(#gradient)"/>
      <rect x="28" y="38" width="7" height="24" rx="3.5" fill="white" class="bar bar-1"/>
      <rect x="40" y="28" width="7" height="44" rx="3.5" fill="white" class="bar bar-2"/>
      <rect x="52" y="32" width="7" height="36" rx="3.5" fill="white" class="bar bar-3"/>
      <rect x="64" y="42" width="7" height="16" rx="3.5" fill="white" class="bar bar-4"/>
      <defs>
        <linearGradient id="gradient" x1="0" y1="0" x2="100" y2="100" gradientUnits="userSpaceOnUse">
          <stop stop-color="#8B5CF6"/>
          <stop offset="1" stop-color="#6D28D9"/>
        </linearGradient>
      </defs>
    </svg>
  </div>
  {#if showText}
    <span class="logo-text">whisp</span>
  {/if}
</a>

<style>
  .logo {
    display: flex;
    align-items: center;
    gap: calc(var(--size) * 0.3);
    text-decoration: none;
  }

  .logo-mark {
    width: var(--size);
    height: var(--size);
    filter: drop-shadow(0 2px 8px rgba(139, 92, 246, 0.25));
    transition: transform 0.3s ease, filter 0.3s ease;
  }

  .logo:hover .logo-mark {
    transform: scale(1.05);
    filter: drop-shadow(0 4px 12px rgba(139, 92, 246, 0.35));
  }

  .logo-mark svg {
    width: 100%;
    height: 100%;
  }

  .bar {
    transform-origin: center bottom;
  }

  .logo:hover .bar-1 {
    animation: wave 0.6s ease-in-out infinite;
    animation-delay: 0s;
  }
  .logo:hover .bar-2 {
    animation: wave 0.6s ease-in-out infinite;
    animation-delay: 0.1s;
  }
  .logo:hover .bar-3 {
    animation: wave 0.6s ease-in-out infinite;
    animation-delay: 0.2s;
  }
  .logo:hover .bar-4 {
    animation: wave 0.6s ease-in-out infinite;
    animation-delay: 0.3s;
  }

  @keyframes wave {
    0%, 100% { transform: scaleY(1); }
    50% { transform: scaleY(0.6); }
  }

  .logo-text {
    font-size: calc(var(--size) * 0.6);
    font-weight: 700;
    color: var(--brand-ink);
    letter-spacing: -0.02em;
  }
</style>
