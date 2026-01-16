<script>
  const features = [
    'Unlimited recordings',
    'System audio capture (Zoom, Meet, Teams)',
    'AI transcription via OpenAI',
    'Full-text search',
    'Calendar view',
    'Agent API for Claude Code',
    'Dictation anywhere',
    'macOS Sonoma native',
    'Lifetime updates'
  ];
</script>

<section id="pricing" class="pricing">
  <div class="container">
    <div class="section-header">
      <span class="badge badge-mint">Pricing</span>
      <h2>One price.<br/><span class="gradient-text">Forever yours.</span></h2>
      <p>No subscriptions. No per-seat pricing. No cloud fees.<br/>Just a one-time purchase that respects your time and wallet.</p>
    </div>

    <div class="pricing-card">
      <div class="price-header">
        <div class="price-badge">EARLY BIRD</div>
        <div class="price">
          <span class="currency">$</span>
          <span class="amount">49</span>
          <span class="period">one-time</span>
        </div>
        <p class="price-note">
          <s>$79</s> — Launch price. Includes all future updates.
        </p>
      </div>

      <div class="price-features">
        {#each features as feature}
          <div class="feature-item">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
              <polyline points="20 6 9 17 4 12"/>
            </svg>
            <span>{feature}</span>
          </div>
        {/each}
      </div>

      <div class="price-cta">
        <button class="btn btn-primary btn-large" style="width: 100%;">
          Download for Mac
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
            <polyline points="7 10 12 15 17 10"/>
            <line x1="12" y1="15" x2="12" y2="3"/>
          </svg>
        </button>
        <p class="guarantee">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
          </svg>
          30-day money-back guarantee. No questions asked.
        </p>
      </div>

      <div class="price-note-byok">
        <strong>Note:</strong> Transcription uses your OpenAI API key (BYOK).
        You pay OpenAI directly at ~$0.003/minute. A typical 1-hour meeting costs ~$0.18.
      </div>
    </div>

    <div class="comparison">
      <h3>Why not use [Otter/Fireflies/etc]?</h3>
      <div class="comparison-table">
        <div class="compare-row header">
          <span></span>
          <span>Whisp</span>
          <span>Others</span>
        </div>
        <div class="compare-row">
          <span>Bot joins call</span>
          <span class="no">No bot</span>
          <span class="yes">Yes, awkward</span>
        </div>
        <div class="compare-row">
          <span>Data stored</span>
          <span class="good">Your Mac only</span>
          <span class="bad">Their cloud</span>
        </div>
        <div class="compare-row">
          <span>Pricing</span>
          <span class="good">$49 once</span>
          <span class="bad">$20+/month</span>
        </div>
        <div class="compare-row">
          <span>Agent API</span>
          <span class="good">Built-in</span>
          <span class="bad">None</span>
        </div>
      </div>
    </div>
  </div>
</section>

<style>
  .pricing {
    padding: 120px 0;
    background: var(--brand-surface);
  }

  .section-header {
    text-align: center;
    max-width: 600px;
    margin: 0 auto 48px;
  }

  .section-header h2 {
    margin: 20px 0 16px;
  }

  .pricing-card {
    max-width: 480px;
    margin: 0 auto 80px;
    background: var(--brand-cream);
    border-radius: var(--radius-lg);
    padding: 48px;
    border: 2px solid var(--brand-violet);
    position: relative;
    overflow: hidden;
  }

  .pricing-card::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 4px;
    background: linear-gradient(90deg, var(--brand-violet), var(--brand-coral));
  }

  .price-header {
    text-align: center;
    margin-bottom: 32px;
  }

  .price-badge {
    display: inline-block;
    padding: 4px 12px;
    background: var(--brand-coral);
    color: white;
    font-size: 0.6875rem;
    font-weight: 700;
    letter-spacing: 0.05em;
    border-radius: var(--radius-pill);
    margin-bottom: 16px;
  }

  .price {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 4px;
  }

  .currency {
    font-size: 1.5rem;
    font-weight: 600;
    color: var(--brand-text-secondary);
  }

  .amount {
    font-size: 4rem;
    font-weight: 800;
    line-height: 1;
    color: var(--brand-ink);
  }

  .period {
    font-size: 1rem;
    color: var(--brand-text-secondary);
    margin-left: 4px;
  }

  .price-note {
    margin-top: 8px;
    font-size: 0.875rem;
  }

  .price-note s {
    color: var(--brand-text-secondary);
  }

  .price-features {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-bottom: 32px;
  }

  .feature-item {
    display: flex;
    align-items: center;
    gap: 12px;
    font-size: 0.9375rem;
    color: var(--brand-text-primary);
  }

  .feature-item svg {
    color: var(--brand-mint);
    flex-shrink: 0;
  }

  .price-cta {
    display: flex;
    flex-direction: column;
    gap: 16px;
    margin-bottom: 24px;
  }

  .guarantee {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    font-size: 0.8125rem;
    color: var(--brand-text-secondary);
  }

  .guarantee svg {
    color: var(--brand-mint);
  }

  .price-note-byok {
    padding: 16px;
    background: rgba(139, 92, 246, 0.08);
    border-radius: var(--radius-sm);
    font-size: 0.8125rem;
    color: var(--brand-text-secondary);
    line-height: 1.6;
  }

  .price-note-byok strong {
    color: var(--brand-violet);
  }

  /* Comparison */
  .comparison {
    max-width: 600px;
    margin: 0 auto;
  }

  .comparison h3 {
    text-align: center;
    margin-bottom: 24px;
    font-size: 1.25rem;
  }

  .comparison-table {
    background: var(--brand-cream);
    border-radius: var(--radius-md);
    overflow: hidden;
  }

  .compare-row {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 16px;
    padding: 16px 24px;
    border-bottom: 1px solid var(--brand-border);
  }

  .compare-row:last-child {
    border-bottom: none;
  }

  .compare-row.header {
    background: var(--brand-surface);
    font-weight: 600;
    font-size: 0.875rem;
  }

  .compare-row span:first-child {
    color: var(--brand-text-secondary);
    font-size: 0.875rem;
  }

  .compare-row .good,
  .compare-row .no {
    color: var(--brand-mint);
    font-weight: 500;
  }

  .compare-row .bad,
  .compare-row .yes {
    color: var(--brand-coral);
  }

  @media (max-width: 640px) {
    .pricing-card {
      padding: 32px 24px;
    }

    .amount {
      font-size: 3rem;
    }

    .pricing {
      padding: 80px 0;
    }
  }
</style>
