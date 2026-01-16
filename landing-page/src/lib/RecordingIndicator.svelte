<script>
  let { active = false, size = 40 } = $props();

  let bars = $state([0.3, 0.5, 0.8, 0.6, 0.4]);

  $effect(() => {
    if (active) {
      const interval = setInterval(() => {
        bars = bars.map(() => 0.2 + Math.random() * 0.8);
      }, 100);
      return () => clearInterval(interval);
    } else {
      bars = [0.3, 0.5, 0.8, 0.6, 0.4];
    }
  });
</script>

<div class="recording-indicator" class:active style="--size: {size}px">
  {#if active}
    <div class="pulse-ring"></div>
    <div class="pulse-ring delay"></div>
  {/if}
  <div class="bars">
    {#each bars as height, i}
      <div
        class="bar"
        style="height: {active ? height * 100 : [30, 50, 80, 60, 40][i]}%; transition-delay: {i * 30}ms"
      ></div>
    {/each}
  </div>
</div>

<style>
  .recording-indicator {
    position: relative;
    width: var(--size);
    height: var(--size);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .pulse-ring {
    position: absolute;
    width: 100%;
    height: 100%;
    border-radius: 50%;
    border: 2px solid var(--brand-coral);
    opacity: 0.4;
    animation: pulse 1.5s ease-out infinite;
  }

  .pulse-ring.delay {
    animation-delay: 0.5s;
  }

  @keyframes pulse {
    0% {
      transform: scale(1);
      opacity: 0.4;
    }
    100% {
      transform: scale(1.6);
      opacity: 0;
    }
  }

  .bars {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: calc(var(--size) * 0.06);
    height: calc(var(--size) * 0.6);
    z-index: 1;
  }

  .bar {
    width: calc(var(--size) * 0.1);
    background: linear-gradient(to top, var(--brand-coral), var(--brand-coral-pop));
    border-radius: calc(var(--size) * 0.05);
    transition: height 0.1s ease;
  }

  .recording-indicator:not(.active) .bar {
    background: var(--brand-text-secondary);
    opacity: 0.3;
  }
</style>
