# Fuime Brand Tokens

Source of truth for Phase 0 visual identity. Applied on top of the HCB design system
(layouts/components stay; accent + type change).

## Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `fuime.blue` / `$fuime-blue` / `primary` | `#0D6EFD` | Primary electric blue |
| `fuime.blue-hover` | `#0B5ED7` | Primary hover |
| `fuime.navy` | `#0F172A` | Deep slate navy (dark surfaces / copy) |
| `fuime.background` | `#F8FAFC` | Off-white canvas |
| `fuime.card` | `#FFFFFF` | Card / surface |
| `fuime.cyan` | `#06B6D4` | Accent cyan |
| `fuime.mint` | `#10B981` | Success green |

## Typography

| Token | Stack | Usage |
|-------|-------|-------|
| `font-heading` / `$font-heading` | Plus Jakarta Sans | Headings |
| `font-body` / `$font-body` | Inter, system fallbacks | Body copy |

Loaded via Google Fonts in `app/views/layouts/_head.html.erb`.

## Effects

| Token | Value |
|-------|-------|
| `shadow-fuime-glow` / `--fuime-glow` | `0 0 20px rgba(13, 110, 253, 0.25)` |

## Files

- `tailwind.config.js` — Tailwind theme extensions
- `app/assets/stylesheets/_variables.scss` — SCSS + CSS custom properties
- `app/assets/stylesheets/application.scss` — font stacks + heading family
- `app/views/layouts/_head.html.erb` — font link + theme-color
