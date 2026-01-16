<script>
  const features = [
    {
      icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
        <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
        <line x1="12" y1="19" x2="12" y2="23"/>
        <line x1="8" y1="23" x2="16" y2="23"/>
      </svg>`,
      title: 'Invisible Recording',
      description: 'Captures system audio directly from your Mac. No bot joins your Zoom, Meet, or Teams call. Nobody knows you\'re recording.',
      badge: 'Privacy First'
    },
    {
      icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
      </svg>`,
      title: 'AI Transcription',
      description: 'Uses OpenAI\'s latest transcription API. Bring your own key — you pay OpenAI directly at $0.003/min. No middleman markup.',
      badge: 'BYOK'
    },
    {
      icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
        <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
      </svg>`,
      title: '100% Local',
      description: 'Your recordings and transcripts never leave your Mac. Stored in ~/Library. Full data sovereignty, zero cloud dependencies.',
      badge: 'Secure'
    },
    {
      icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
        <line x1="16" y1="2" x2="16" y2="6"/>
        <line x1="8" y1="2" x2="8" y2="6"/>
        <line x1="3" y1="10" x2="21" y2="10"/>
      </svg>`,
      title: 'Calendar View',
      description: 'Browse past meetings by date. Beautiful, Amie-inspired UI. Search across all transcripts instantly with full-text search.',
      badge: 'Organized'
    },
    {
      icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="4 17 10 11 4 5"/>
        <line x1="12" y1="19" x2="20" y2="19"/>
      </svg>`,
      title: 'Agent-Native API',
      description: 'Expose your meetings as JSON files. Claude Code and Codex can query your meeting history. The first AI-native meeting tool.',
      badge: 'Developer'
    },
    {
      icon: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/>
      </svg>`,
      title: 'Dictation Anywhere',
      description: 'Press Ctrl+Cmd+D, speak, release. Your words appear at cursor. Works in any app. Faster than typing for quick notes.',
      badge: 'Productivity'
    }
  ];
</script>

<section id="features" class="features">
  <div class="container">
    <div class="section-header">
      <span class="badge badge-violet">Features</span>
      <h2>Everything you need.<br/><span class="gradient-text">Nothing you don't.</span></h2>
      <p>Built for people who actually use meeting recordings, not just collect them.</p>
    </div>

    <div class="features-grid">
      {#each features as feature}
        <div class="card feature-card">
          <div class="feature-icon">
            {@html feature.icon}
          </div>
          <span class="badge badge-violet" style="font-size: 0.625rem;">{feature.badge}</span>
          <h3>{feature.title}</h3>
          <p>{feature.description}</p>
        </div>
      {/each}
    </div>
  </div>
</section>

<style>
  .features {
    padding: 120px 0;
    background: var(--brand-surface);
  }

  .section-header {
    text-align: center;
    max-width: 600px;
    margin: 0 auto 64px;
  }

  .section-header h2 {
    margin: 20px 0 16px;
  }

  .section-header p {
    font-size: 1.125rem;
  }

  .features-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 24px;
  }

  .feature-card {
    display: flex;
    flex-direction: column;
    gap: 12px;
    align-items: flex-start;
  }

  .feature-icon {
    width: 48px;
    height: 48px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(139, 92, 246, 0.1);
    border-radius: var(--radius-sm);
    color: var(--brand-violet);
    margin-bottom: 4px;
  }

  .feature-icon :global(svg) {
    width: 24px;
    height: 24px;
  }

  .feature-card h3 {
    font-size: 1.125rem;
    margin-top: 4px;
  }

  .feature-card p {
    font-size: 0.9375rem;
    line-height: 1.6;
    margin: 0;
  }

  @media (max-width: 968px) {
    .features-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }

  @media (max-width: 640px) {
    .features-grid {
      grid-template-columns: 1fr;
    }

    .features {
      padding: 80px 0;
    }
  }
</style>
