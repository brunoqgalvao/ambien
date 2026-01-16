<script>
  import Logo from './Logo.svelte';
</script>

<footer class="footer">
  <div class="container">
    <div class="footer-content">
      <div class="footer-brand">
        <Logo size={32} />
        <p>The invisible meeting recorder for macOS. Record system audio, transcribe with AI, query with Claude Code.</p>
        <div class="social-links">
          <a href="https://twitter.com/whisp_app" target="_blank" rel="noopener" aria-label="Twitter">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
            </svg>
          </a>
          <a href="https://github.com/whisp-app" target="_blank" rel="noopener" aria-label="GitHub">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
            </svg>
          </a>
        </div>
      </div>

      <div class="footer-links">
        <div class="link-group">
          <h4>Product</h4>
          <a href="#features">Features</a>
          <a href="#how-it-works">How it works</a>
          <a href="#pricing">Pricing</a>
          <a href="/changelog">Changelog</a>
        </div>

        <div class="link-group">
          <h4>Resources</h4>
          <a href="/docs">Documentation</a>
          <a href="/docs/agent-api">Agent API</a>
          <a href="/docs/shortcuts">Keyboard Shortcuts</a>
          <a href="/support">Support</a>
        </div>

        <div class="link-group">
          <h4>Legal</h4>
          <a href="/privacy">Privacy Policy</a>
          <a href="/terms">Terms of Service</a>
          <a href="/refund">Refund Policy</a>
        </div>
      </div>
    </div>

    <div class="footer-bottom">
      <p>&copy; {new Date().getFullYear()} Whisp. All rights reserved.</p>
      <p class="made-with">
        Made with
        <svg width="14" height="14" viewBox="0 0 24 24" fill="var(--brand-coral)">
          <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
        </svg>
        in San Francisco
      </p>
    </div>
  </div>
</footer>

<style>
  .footer {
    padding: 80px 0 40px;
    background: var(--brand-ink);
    color: white;
  }

  .footer-content {
    display: grid;
    grid-template-columns: 1.5fr 2fr;
    gap: 80px;
    margin-bottom: 60px;
  }

  .footer-brand p {
    margin: 20px 0;
    font-size: 0.9375rem;
    color: rgba(255, 255, 255, 0.6);
    line-height: 1.7;
    max-width: 320px;
  }

  .footer-brand :global(.logo-text) {
    color: white;
  }

  .social-links {
    display: flex;
    gap: 16px;
  }

  .social-links a {
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(255, 255, 255, 0.1);
    border-radius: var(--radius-sm);
    color: rgba(255, 255, 255, 0.7);
    transition: all 0.2s;
  }

  .social-links a:hover {
    background: var(--brand-violet);
    color: white;
  }

  .footer-links {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 40px;
  }

  .link-group h4 {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: rgba(255, 255, 255, 0.4);
    margin-bottom: 20px;
  }

  .link-group a {
    display: block;
    color: rgba(255, 255, 255, 0.7);
    font-size: 0.9375rem;
    margin-bottom: 12px;
    transition: color 0.2s;
  }

  .link-group a:hover {
    color: white;
  }

  .footer-bottom {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-top: 40px;
    border-top: 1px solid rgba(255, 255, 255, 0.1);
  }

  .footer-bottom p {
    font-size: 0.8125rem;
    color: rgba(255, 255, 255, 0.4);
    margin: 0;
  }

  .made-with {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  @media (max-width: 968px) {
    .footer-content {
      grid-template-columns: 1fr;
      gap: 48px;
    }

    .footer-links {
      grid-template-columns: repeat(3, 1fr);
    }
  }

  @media (max-width: 640px) {
    .footer-links {
      grid-template-columns: 1fr 1fr;
    }

    .footer-bottom {
      flex-direction: column;
      gap: 12px;
      text-align: center;
    }

    .footer {
      padding: 60px 0 32px;
    }
  }
</style>
