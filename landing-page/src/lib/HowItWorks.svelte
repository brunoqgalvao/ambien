<script>
  const steps = [
    {
      number: '01',
      title: 'Start Recording',
      description: 'Click the menu bar icon or use the keyboard shortcut. Ambien automatically detects if Zoom, Meet, or Teams is running.',
      visual: 'menubar'
    },
    {
      number: '02',
      title: 'Have Your Meeting',
      description: 'Ambien captures system audio silently in the background. No one in your call knows you\'re recording. No awkward "Recorder Bot joined."',
      visual: 'recording'
    },
    {
      number: '03',
      title: 'Auto-Transcribe',
      description: 'When you stop recording, Ambien sends audio to OpenAI for transcription. Get a searchable transcript in minutes.',
      visual: 'transcribe'
    },
    {
      number: '04',
      title: 'Search & Share',
      description: 'Browse by date, search across all meetings, or let Claude Code query your meeting history via the agent API.',
      visual: 'search'
    }
  ];
</script>

<section id="how-it-works" class="how-it-works">
  <div class="container">
    <div class="section-header">
      <span class="badge badge-coral">How it works</span>
      <h2>From meeting to transcript<br/><span class="gradient-text">in 4 simple steps</span></h2>
    </div>

    <div class="steps">
      {#each steps as step, i}
        <div class="step" style="--delay: {i * 0.1}s">
          <div class="step-number">{step.number}</div>
          <div class="step-content">
            <h3>{step.title}</h3>
            <p>{step.description}</p>
          </div>
          <div class="step-visual {step.visual}">
            {#if step.visual === 'menubar'}
              <div class="visual-menubar">
                <div class="menubar-icon">
                  <div class="icon-bars">
                    <span></span><span></span><span></span>
                  </div>
                </div>
                <div class="dropdown">
                  <div class="dropdown-item active">
                    <span class="rec-dot"></span>
                    Start Recording
                  </div>
                  <div class="dropdown-item">Recent Meetings</div>
                  <div class="dropdown-item">Settings</div>
                </div>
              </div>
            {:else if step.visual === 'recording'}
              <div class="visual-recording">
                <div class="waveform">
                  {#each Array(12) as _, i}
                    <div class="wave-bar" style="--i: {i}"></div>
                  {/each}
                </div>
                <div class="time-display">00:45:32</div>
              </div>
            {:else if step.visual === 'transcribe'}
              <div class="visual-transcribe">
                <div class="spinner"></div>
                <div class="progress">
                  <div class="progress-bar"></div>
                </div>
                <span class="progress-text">Transcribing...</span>
              </div>
            {:else if step.visual === 'search'}
              <div class="visual-search">
                <div class="search-box">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <circle cx="11" cy="11" r="8"/>
                    <line x1="21" y1="21" x2="16.65" y2="16.65"/>
                  </svg>
                  <span>action items from Q4</span>
                </div>
                <div class="search-results">
                  <div class="result">Product Review — 3 matches</div>
                  <div class="result">Strategy Call — 2 matches</div>
                </div>
              </div>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  </div>
</section>

<style>
  .how-it-works {
    padding: 120px 0;
    background: var(--brand-cream);
  }

  .section-header {
    text-align: center;
    max-width: 600px;
    margin: 0 auto 80px;
  }

  .section-header h2 {
    margin-top: 20px;
  }

  .steps {
    display: flex;
    flex-direction: column;
    gap: 32px;
    max-width: 900px;
    margin: 0 auto;
  }

  .step {
    display: grid;
    grid-template-columns: 60px 1fr 280px;
    gap: 32px;
    align-items: center;
    padding: 32px;
    background: var(--brand-surface);
    border-radius: var(--radius-md);
    border: 1px solid var(--brand-border);
    animation: fade-in-up 0.6s ease-out backwards;
    animation-delay: var(--delay);
  }

  .step-number {
    font-size: 2rem;
    font-weight: 800;
    color: var(--brand-violet);
    opacity: 0.3;
  }

  .step-content h3 {
    font-size: 1.25rem;
    margin-bottom: 8px;
  }

  .step-content p {
    font-size: 0.9375rem;
    margin: 0;
    line-height: 1.6;
  }

  .step-visual {
    height: 140px;
    background: var(--brand-cream);
    border-radius: var(--radius-sm);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
  }

  /* Visual: Menubar */
  .visual-menubar {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }

  .menubar-icon {
    width: 24px;
    height: 24px;
    background: var(--brand-violet);
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .icon-bars {
    display: flex;
    gap: 2px;
    align-items: center;
    height: 12px;
  }

  .icon-bars span {
    width: 2px;
    background: white;
    border-radius: 1px;
  }

  .icon-bars span:nth-child(1) { height: 4px; }
  .icon-bars span:nth-child(2) { height: 8px; }
  .icon-bars span:nth-child(3) { height: 6px; }

  .dropdown {
    background: white;
    border-radius: 6px;
    padding: 4px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    font-size: 0.75rem;
  }

  .dropdown-item {
    padding: 6px 12px;
    border-radius: 4px;
    display: flex;
    align-items: center;
    gap: 6px;
    color: var(--brand-text-secondary);
  }

  .dropdown-item.active {
    background: rgba(139, 92, 246, 0.1);
    color: var(--brand-violet);
    font-weight: 500;
  }

  .rec-dot {
    width: 6px;
    height: 6px;
    background: var(--brand-coral);
    border-radius: 50%;
    animation: pulse-ring 1s infinite;
  }

  /* Visual: Recording */
  .visual-recording {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
  }

  .waveform {
    display: flex;
    align-items: center;
    gap: 4px;
    height: 48px;
  }

  .wave-bar {
    width: 4px;
    background: linear-gradient(to top, var(--brand-coral), var(--brand-coral-pop));
    border-radius: 2px;
    animation: wave 0.8s ease-in-out infinite;
    animation-delay: calc(var(--i) * 0.08s);
  }

  @keyframes wave {
    0%, 100% { height: 16px; }
    50% { height: 40px; }
  }

  .time-display {
    font-family: var(--font-mono);
    font-size: 1.25rem;
    font-weight: 600;
    color: var(--brand-coral);
  }

  /* Visual: Transcribe */
  .visual-transcribe {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
  }

  .spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--brand-border);
    border-top-color: var(--brand-violet);
    border-radius: 50%;
    animation: spin 1s linear infinite;
  }

  .progress {
    width: 160px;
    height: 4px;
    background: var(--brand-border);
    border-radius: 2px;
    overflow: hidden;
  }

  .progress-bar {
    height: 100%;
    width: 65%;
    background: linear-gradient(90deg, var(--brand-violet), var(--brand-violet-bright));
    border-radius: 2px;
    animation: progress 2s ease-in-out infinite;
  }

  @keyframes progress {
    0% { width: 20%; }
    50% { width: 80%; }
    100% { width: 20%; }
  }

  .progress-text {
    font-size: 0.75rem;
    color: var(--brand-text-secondary);
  }

  /* Visual: Search */
  .visual-search {
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 200px;
  }

  .search-box {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: white;
    border-radius: 6px;
    border: 1px solid var(--brand-border);
    font-size: 0.75rem;
    color: var(--brand-text-primary);
  }

  .search-box svg {
    color: var(--brand-text-secondary);
    flex-shrink: 0;
  }

  .search-results {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .result {
    padding: 8px 12px;
    background: white;
    border-radius: 6px;
    font-size: 0.6875rem;
    color: var(--brand-text-secondary);
    border-left: 2px solid var(--brand-violet);
  }

  @media (max-width: 768px) {
    .step {
      grid-template-columns: 1fr;
      gap: 24px;
    }

    .step-number {
      font-size: 1.5rem;
    }

    .step-visual {
      height: 120px;
    }

    .how-it-works {
      padding: 80px 0;
    }
  }
</style>
