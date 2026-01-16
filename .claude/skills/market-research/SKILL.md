---
name: market-research
description: Deep market and product research for founders. Use when the user wants to research a market, validate a product idea, analyze competitors, understand customer pain points, or prepare for MVP development. Triggers on market research, product research, validate idea, competitive analysis, customer discovery.
---

# Market Research Skill

Comprehensive first-hand market research for consumer/prosumer products. Built for founders researching new ideas or detailing product MVPs.

## Workflow

### Phase 1: Discovery Interview (Required)

Before any research, ask these questions to understand the product/market:

```
1. PRODUCT: What's the product/idea in one sentence? What problem does it solve?

2. TARGET USER: Who's the ideal customer? (demographics, behavior, current solutions)

3. COMPETITORS: Any known competitors or alternatives? (even indirect ones)

4. PRICE POINT: Rough pricing tier? (free, <$20/mo, $20-100/mo, $100+/mo, one-time purchase)

5. UNIQUE ANGLE: What's the differentiation hypothesis? Why would someone switch?
```

Wait for user responses before proceeding.

### Phase 2: Parallel Research Blitz

Spawn 5 parallel subagents, each focused on a specific research domain:

#### Agent 1: Reddit & Community Mining
- Search Reddit for pain points, complaints, "I wish" posts
- Target subreddits related to the problem space
- Look for: frustrations with existing solutions, feature requests, workarounds
- Extract direct quotes with upvote counts

#### Agent 2: Review Scraping
- App Store / Play Store reviews for competitor apps
- Amazon reviews for related products
- G2/Capterra if B2B adjacent
- Focus on 1-3 star reviews (pain points) AND 5 star reviews (what people love)

#### Agent 3: Social Listening
- Twitter/X search for problem-related keywords
- YouTube comments on relevant videos
- Look for organic complaints and praise

#### Agent 4: Competitor Intelligence
- Competitor pricing pages
- Competitor feature matrices
- Their negative reviews (opportunities)
- ProductHunt launches and comments
- Job postings (reveals priorities)

#### Agent 5: Search Intent & Trends
- Google Trends data
- "People also ask" insights
- Related searches
- Keyword volume indicators

### Phase 3: Synthesis & Report

Compile findings into a structured markdown report.

## Report Template

Generate the report in this format:

```markdown
# Market Research Report: [Product Name/Idea]

**Generated:** [Date]
**Research Duration:** [Time spent]

---

## Executive Summary
[3-5 bullet points of the most critical findings]

---

## 1. Problem Validation

### Pain Points Discovered
| Pain Point | Source | Evidence Strength | Quote |
|------------|--------|-------------------|-------|
| [Issue] | [Reddit/Reviews/etc] | [High/Med/Low] | "[Direct quote]" |

### Current Solutions & Their Gaps
[What people use today and why it sucks]

---

## 2. Target User Profile

### Demographics
- Age range:
- Income level:
- Tech savviness:
- Current behavior:

### Psychographics
- Motivations:
- Frustrations:
- Goals:

### Willingness to Pay
[Evidence of price sensitivity or willingness to pay]

---

## 3. Competitive Landscape

### Direct Competitors
| Competitor | Pricing | Strengths | Weaknesses | User Sentiment |
|------------|---------|-----------|------------|----------------|
| [Name] | [Price] | [+] | [-] | [Summary] |

### Indirect Competitors / Substitutes
[What else solves this problem, even if differently]

### Competitive Gaps (Your Opportunity)
[Where competitors fail that you could win]

---

## 4. Market Signals

### Search Trends
[Google Trends insights, search volume indicators]

### Social Buzz
[Volume and sentiment of social discussion]

### Recent Launches
[ProductHunt, HackerNews activity in this space]

---

## 5. Voice of Customer

### Top Quotes to Remember
> "[Most impactful quote #1]" - [Source]

> "[Most impactful quote #2]" - [Source]

> "[Most impactful quote #3]" - [Source]

### Feature Requests (From the Wild)
1. [Feature users are begging for]
2. [Another requested feature]
3. [Third requested feature]

---

## 6. MVP Recommendations

### Must-Have Features (Day 1)
- [ ] [Feature based on research]
- [ ] [Feature based on research]
- [ ] [Feature based on research]

### Nice-to-Have (Post-Launch)
- [ ] [Feature]
- [ ] [Feature]

### Features to SKIP (Overbuilt by Competitors)
- [Feature that's table stakes / commoditized]

---

## 7. Go-to-Market Insights

### Where Your Users Hang Out
- [Subreddits]
- [Communities]
- [Platforms]

### Messaging That Resonates
[Based on language used in reviews/posts]

### Pricing Strategy Recommendation
[Based on competitor pricing and willingness to pay signals]

---

## 8. Risks & Red Flags

- **[Risk 1]:** [Description and mitigation]
- **[Risk 2]:** [Description and mitigation]

---

## 9. Raw Research Links

### Sources Consulted
- [Link 1]
- [Link 2]
- [etc]

---

## Next Steps

1. [Recommended action #1]
2. [Recommended action #2]
3. [Recommended action #3]
```

## Research Agent Instructions

When spawning subagents, provide them with:

1. The product/idea description
2. Target user profile
3. Known competitors
4. Specific sources to search
5. What data to extract

Each agent should return:
- Raw findings with sources
- Direct quotes where possible
- Confidence level (high/medium/low based on evidence volume)

## Tool Usage

This skill primarily uses:
- `WebSearch` - For finding relevant discussions, reviews, trends
- `WebFetch` - For scraping specific pages
- `mcp__multi-session__spawn_agent` - For parallel research
- `Write` - For generating the final report

## Guidelines

1. **First-hand data only** - Prioritize real user quotes over analyst opinions
2. **Cite everything** - Every claim needs a source
3. **Quantity matters** - More data points = higher confidence
4. **Recency matters** - Prefer recent posts/reviews (last 2 years)
5. **Negative reviews are gold** - They reveal opportunities
6. **Don't make up data** - If you can't find something, say so
7. **Be actionable** - Every insight should inform a decision

## Output Location

Save the report to: `./research-reports/[product-name]-[date].md`

Create the directory if it doesn't exist.
