<script>
  import RecordingIndicator from './RecordingIndicator.svelte';

  let isHovered = $state(false);
</script>

<section class="hero">
  <div class="container">
    <div class="hero-content">
      <div class="badge badge-violet">
        <span class="badge-dot"></span>
        macOS Native App
      </div>

      <h1>
        Record meetings<br/>
        <span class="highlight">without the awkward bot</span>
      </h1>

      <p class="hero-subtitle">
        Ambien captures system audio from Zoom, Meet, and Teams directly on your Mac.
        No bot joins your call. No one knows you're recording. Just pure, local-first transcription.
      </p>

      <div class="hero-cta">
        <a href="#pricing" class="btn btn-primary btn-large">
          Download for Mac
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 5v14M5 12l7 7 7-7"/>
          </svg>
        </a>
        <a href="#how-it-works" class="btn btn-secondary btn-large">
          See how it works
        </a>
      </div>

      <div class="hero-meta">
        <span class="meta-item">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
            <polyline points="22 4 12 14.01 9 11.01"/>
          </svg>
          One-time purchase
        </span>
        <span class="meta-item">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
            <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          </svg>
          100% local
        </span>
        <span class="meta-item">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="10"/>
            <polyline points="12 6 12 12 16 14"/>
          </svg>
          macOS 12.3+
        </span>
      </div>
    </div>

    <div class="hero-visual"
         onmouseenter={() => isHovered = true}
         onmouseleave={() => isHovered = false}
         role="img"
         aria-label="App preview">
      <div class="app-window">
        <div class="window-header">
          <div class="window-dots">
            <span class="dot red"></span>
            <span class="dot yellow"></span>
            <span class="dot green"></span>
          </div>
          <span class="window-title">Ambien</span>
        </div>
        <div class="window-content">
          <div class="recording-card" class:active={isHovered}>
            <RecordingIndicator active={isHovered} />
            <div class="recording-info">
              <span class="recording-title">Team Standup</span>
              <span class="recording-time">{isHovered ? 'Recording...' : 'Click to preview'}</span>
            </div>
            <div class="recording-duration">
              {isHovered ? '00:32' : '—'}
            </div>
          </div>

          <div class="meeting-list">
            <div class="meeting-item">
              <div class="meeting-icon">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M3 18v-6a9 9 0 0 1 18 0v6"/>
                  <path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/>
                </svg>
              </div>
              <div class="meeting-details">
                <span class="meeting-title">Product Review</span>
                <span class="meeting-meta">Yesterday • 1h 12m</span>
              </div>
              <span class="badge badge-mint" style="font-size: 0.625rem; padding: 3px 8px;">Transcribed</span>
            </div>

            <div class="meeting-item">
              <div class="meeting-icon">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M3 18v-6a9 9 0 0 1 18 0v6"/>
                  <path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/>
                </svg>
              </div>
              <div class="meeting-details">
                <span class="meeting-title">Client Call - Acme</span>
                <span class="meeting-meta">Jan 14 • 45m</span>
              </div>
              <span class="badge badge-mint" style="font-size: 0.625rem; padding: 3px 8px;">Transcribed</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Floating elements -->
      <div class="float-badge float-1">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
          <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
          <line x1="12" y1="19" x2="12" y2="23"/>
          <line x1="8" y1="23" x2="16" y2="23"/>
        </svg>
        System Audio
      </div>

      <div class="float-badge float-2">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
        </svg>
        AI Transcription
      </div>
    </div>
  </div>
</section>

<style>
  .hero {
    padding: 80px 0 120px;
    overflow: hidden;
  }

  .hero .container {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 80px;
    align-items: center;
  }

  .hero-content {
    animation: fade-in-up 0.8s ease-out;
  }

  .badge-dot {
    width: 6px;
    height: 6px;
    background: var(--brand-violet);
    border-radius: 50%;
    animation: pulse-ring 2s ease-out infinite;
  }

  h1 {
    margin: 24px 0;
  }

  .hero-subtitle {
    font-size: 1.25rem;
    line-height: 1.7;
    margin-bottom: 32px;
    max-width: 520px;
  }

  .hero-cta {
    display: flex;
    gap: 16px;
    margin-bottom: 40px;
  }

  .hero-meta {
    display: flex;
    gap: 24px;
  }

  .meta-item {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.875rem;
    color: var(--brand-text-secondary);
  }

  .meta-item svg {
    color: var(--brand-mint);
  }

  /* App Window Visual */
  .hero-visual {
    position: relative;
    animation: fade-in-up 0.8s ease-out 0.2s backwards;
  }

  .app-window {
    background: var(--brand-surface);
    border-radius: var(--radius-md);
    box-shadow:
      0 4px 6px rgba(0, 0, 0, 0.02),
      0 12px 24px rgba(0, 0, 0, 0.06),
      0 24px 48px rgba(0, 0, 0, 0.04);
    border: 1px solid var(--brand-border);
    overflow: hidden;
  }

  .window-header {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 14px 16px;
    background: var(--brand-cream);
    border-bottom: 1px solid var(--brand-border);
  }

  .window-dots {
    display: flex;
    gap: 8px;
  }

  .dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
  }

  .dot.red { background: #FF6B6B; }
  .dot.yellow { background: #FBBF24; }
  .dot.green { background: #4ADE80; }

  .window-title {
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--brand-text-secondary);
  }

  .window-content {
    padding: 20px;
  }

  .recording-card {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 16px;
    background: var(--brand-cream);
    border-radius: var(--radius-sm);
    margin-bottom: 20px;
    border: 1px solid transparent;
    transition: all 0.3s ease;
    cursor: pointer;
  }

  .recording-card.active {
    border-color: var(--brand-coral);
    background: rgba(255, 107, 107, 0.05);
  }

  .recording-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .recording-title {
    font-weight: 600;
    font-size: 0.9375rem;
    color: var(--brand-ink);
  }

  .recording-time {
    font-size: 0.8125rem;
    color: var(--brand-text-secondary);
  }

  .recording-card.active .recording-time {
    color: var(--brand-coral);
  }

  .recording-duration {
    font-family: var(--font-mono);
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--brand-coral);
  }

  .meeting-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .meeting-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px;
    border-radius: var(--radius-sm);
    transition: background 0.2s;
  }

  .meeting-item:hover {
    background: var(--brand-cream);
  }

  .meeting-icon {
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(139, 92, 246, 0.1);
    border-radius: 50%;
    color: var(--brand-violet);
  }

  .meeting-details {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .meeting-title {
    font-weight: 500;
    font-size: 0.875rem;
    color: var(--brand-ink);
  }

  .meeting-meta {
    font-size: 0.75rem;
    color: var(--brand-text-secondary);
  }

  /* Floating badges */
  .float-badge {
    position: absolute;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 16px;
    background: var(--brand-surface);
    border-radius: var(--radius-sm);
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--brand-ink);
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
    animation: float 4s ease-in-out infinite;
  }

  .float-badge svg {
    color: var(--brand-violet);
  }

  .float-1 {
    top: -20px;
    right: -20px;
    animation-delay: 0s;
  }

  .float-2 {
    bottom: 40px;
    left: -40px;
    animation-delay: 1s;
  }

  @media (max-width: 968px) {
    .hero .container {
      grid-template-columns: 1fr;
      gap: 60px;
    }

    .hero-visual {
      order: -1;
      max-width: 500px;
      margin: 0 auto;
    }

    .float-1 {
      right: 0;
    }

    .float-2 {
      left: 0;
    }
  }

  @media (max-width: 640px) {
    .hero-cta {
      flex-direction: column;
    }

    .hero-meta {
      flex-wrap: wrap;
      gap: 16px;
    }

    .float-badge {
      display: none;
    }
  }
</style>
