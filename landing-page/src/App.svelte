<script>
  import Logo from './lib/Logo.svelte';
  import Hero from './lib/Hero.svelte';
  import Features from './lib/Features.svelte';
  import HowItWorks from './lib/HowItWorks.svelte';
  import Pricing from './lib/Pricing.svelte';
  import Footer from './lib/Footer.svelte';
</script>

<div class="app">
  <!-- Navigation -->
  <nav class="nav">
    <div class="container nav-content">
      <Logo />
      <div class="nav-links">
        <a href="#features" class="nav-link">Features</a>
        <a href="#how-it-works" class="nav-link">How it works</a>
        <a href="#pricing" class="nav-link">Pricing</a>
      </div>
      <a href="#pricing" class="btn btn-primary btn-nav">Download</a>
    </div>
  </nav>

  <main>
    <Hero />
    <Features />
    <HowItWorks />
    <Pricing />
  </main>

  <Footer />
</div>

<style>
  .app {
    min-height: 100vh;
  }

  .nav {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 100;
    background: rgba(250, 247, 242, 0.8);
    backdrop-filter: blur(12px);
    border-bottom: 1px solid var(--brand-border);
  }

  .nav-content {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 72px;
  }

  .nav-links {
    display: flex;
    gap: 8px;
  }

  .nav-link {
    padding: 10px 16px;
    color: var(--brand-text-secondary);
    font-size: 0.9375rem;
    font-weight: 500;
    border-radius: var(--radius-sm);
    transition: all 0.2s;
  }

  .nav-link:hover {
    color: var(--brand-violet);
    background: rgba(139, 92, 246, 0.05);
  }

  .btn-nav {
    padding: 10px 20px;
    font-size: 0.875rem;
  }

  main {
    padding-top: 72px;
  }

  @media (max-width: 768px) {
    .nav-links {
      display: none;
    }
  }
</style>
