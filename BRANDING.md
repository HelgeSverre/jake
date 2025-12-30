# Jake Branding Guidelines

## Brand Identity

**Name:** Jake
**Tagline:** Modern command running
**Positioning:** The best of Make and Just, combined.

**Brand Personality:**
- Developer-focused, no-nonsense
- Modern but approachable
- Fast, efficient, reliable
- Clean and minimal

---

## Logo

### Primary Mark: `{j}`

The Jake logo is a simple, code-native mark using curly braces around a lowercase j.

```
{j}
```

**Usage:**
- Favicon and small contexts: `{j}`
- With wordmark: `{j} jake`
- CLI output: `{j}` or just `jake`

**Why braces?**
- Instantly recognizable as code/developer-focused
- Works in any monospace font
- Renders perfectly at any size
- Can be typed in plain text
- Evokes configuration files and syntax

### Logo Variations

| Context | Format |
|---------|--------|
| Favicon | `{j}` in primary color on transparent |
| Header | `{j} jake` |
| Badge | `{j}` only |
| CLI | Plain text `jake` or `{j}` |

### Logo Don'ts
- Don't use other bracket types: `[j]` `<j>` `(j)`
- Don't capitalize: `{J}`
- Don't add spacing: `{ j }`
- Don't use different fonts for the braces vs letter

---

## Color Palette

### Primary Colors

| Role | Name | Hex | RGB | Usage |
|------|------|-----|-----|-------|
| **Primary** | Jake Red | `#f43f5e` | 244, 63, 94 | Main brand color, CTAs, links |
| **Primary Dark** | Deep Red | `#e11d48` | 225, 29, 72 | Hover states, emphasis |
| **Primary Light** | Rose | `#fda4af` | 253, 164, 175 | Backgrounds, highlights |

### Neutral Colors

| Role | Name | Hex | Usage |
|------|------|-----|-------|
| **Background Dark** | Charcoal | `#0f0f0f` | Dark mode background |
| **Background Light** | Off-white | `#fafafa` | Light mode background |
| **Surface Dark** | Dark Gray | `#1a1a1a` | Cards, code blocks (dark) |
| **Surface Light** | Light Gray | `#f4f4f5` | Cards, code blocks (light) |
| **Text Primary** | Near Black | `#18181b` | Body text (light mode) |
| **Text Primary** | Near White | `#fafafa` | Body text (dark mode) |
| **Text Muted** | Gray | `#71717a` | Secondary text |

### Semantic Colors

| Role | Hex | Usage |
|------|-----|-------|
| Success | `#22c55e` | Task complete, passed |
| Error | `#ef4444` | Failed, errors |
| Warning | `#f59e0b` | Warnings, caution |
| Info | `#3b82f6` | Information, tips |

### Color in Context

```
Dark mode:   #0f0f0f background, #f43f5e accents, #fafafa text
Light mode:  #fafafa background, #f43f5e accents, #18181b text
```

---

## Typography

### Font Stack

**Headings & UI:**
```css
font-family: Inter, system-ui, -apple-system, sans-serif;
```

**Code & Monospace:**
```css
font-family: 'JetBrains Mono', 'Fira Code', 'SF Mono', Consolas, monospace;
```

### Font Weights
- Regular (400): Body text
- Medium (500): UI elements, subheadings
- Semibold (600): Headings
- Bold (700): Emphasis, hero text

---

## CLI Output Styling

### Task Status Indicators

```
{j} jake v1.0.0

Running task: build
  ✓ compile        (completed - green)
  → bundle         (running - primary/cyan)
  ○ test           (pending - gray)
  ✗ deploy         (failed - red)
```

### ANSI Color Codes

| Element | Color | ANSI Code |
|---------|-------|-----------|
| Success/Done | Green | `\x1b[32m` |
| Error/Failed | Red | `\x1b[31m` |
| Warning | Yellow | `\x1b[33m` |
| Running/Info | Cyan | `\x1b[36m` |
| Muted/Dim | Gray | `\x1b[90m` |
| Task Name | Bold | `\x1b[1m` |
| Reset | - | `\x1b[0m` |

### Output Examples

**Minimal (default):**
```
✓ build
✓ test
✓ deploy
```

**Verbose:**
```
{j} jake v1.0.0
Running: deploy

→ build
  echo "Building..."
  Building...
✓ build (0.12s)

→ test
  npm test
  All tests passed
✓ test (1.34s)

→ deploy
  rsync dist/ server:/var/www/
✓ deploy (0.89s)

Done in 2.35s
```

---

## README Badges

### Primary Badge
```markdown
[![Jake](https://img.shields.io/badge/{j}-jake-f43f5e?style=flat-square)](https://jakefile.dev)
```

### Full Badge Set
```markdown
[![CI](https://github.com/HelgeSverre/jake/actions/workflows/ci.yml/badge.svg)](https://github.com/HelgeSverre/jake/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/HelgeSverre/jake?style=flat-square)](https://github.com/HelgeSverre/jake/releases)
[![Zig](https://img.shields.io/badge/lang-Zig-F7A41D?style=flat-square&logo=zig)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE.md)
```

---

## Website Design

### Hero Section
- Large `{j} jake` logo
- Tagline: "Modern command running"
- Install command with copy button
- Primary CTA: "Get Started" (primary color)
- Secondary CTA: "View on GitHub" (outline)

### Code Examples
- Dark background (`#1a1a1a`)
- Syntax highlighting with primary color for keywords
- Copy button on hover

### Feature Cards
- Icon + title + description
- Subtle border or shadow
- Hover state with slight lift

---

## Favicon

### SVG Source
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <text x="50%" y="50%"
        dominant-baseline="central"
        text-anchor="middle"
        font-family="monospace"
        font-size="20"
        font-weight="600"
        fill="#f43f5e">{j}</text>
</svg>
```

### Sizes to Generate
- 16x16 (favicon.ico)
- 32x32 (favicon-32x32.png)
- 180x180 (apple-touch-icon.png)
- 192x192 (android-chrome-192x192.png)
- 512x512 (android-chrome-512x512.png)

---

## Social Media

### Open Graph Image (1200x630)
- Dark background (`#0f0f0f`)
- Large `{j}` mark in primary color
- "jake" wordmark below
- Tagline: "Modern command running"

### Twitter Card
- Same as OG image
- Ensure text is readable at thumbnail size

---

## File Naming

| Asset | Filename |
|-------|----------|
| Primary logo SVG | `jake-logo.svg` |
| Favicon | `favicon.svg` / `favicon.ico` |
| OG Image | `og-image.png` |
| Twitter Card | `twitter-card.png` |

---

## Quick Reference

```
Logo:       {j}
Color:      #f43f5e
Tagline:    Modern command running
Font:       Inter + JetBrains Mono
CLI icon:   {j} or ✓/✗/→/○
```
