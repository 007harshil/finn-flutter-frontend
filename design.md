# FiNN — Design Specification (for Flutter recreation)

FiNN is a mobile-first, portrait-only personal finance app ("Personal Finance Command Center"). Currency is INR (₹). This document describes **only visual and UX design**: screens, layout, spacing, colors, typography, icons, motion, interactions, copy and visual states. It does not cover data access, APIs or code architecture.

Conventions:
- Sizes come from Tailwind classes converted to logical pixels (1 Tailwind unit = 4px; `p-4` = 16px). Use them as Flutter logical pixels.
- Named colors (`emerald-500`, `rose-500`, …) are Tailwind v3 default palette values. Hex is given where known.
- Icons are Lucide icon names. In Flutter, use the `lucide_icons` / `lucide_icons_flutter` package for a 1:1 match.
- Font: no custom font. The app uses the platform system sans-serif stack, so Flutter defaults (Roboto / SF Pro) match.
- Theme: shadcn "slate" theme with light and dark variants. Dark mode is class-based. No theme toggle is rendered in the current Settings UI.

## Theme Tokens (resolved hex)

| Token | Light | Dark |
|---|---|---|
| background | #FFFFFF | #020817 |
| foreground | #020817 | #F8FAFC |
| card / popover | #FFFFFF | #020817 |
| primary | #0F172A | #F8FAFC |
| primary-foreground | #F8FAFC | #0F172A |
| secondary / muted / accent | #F1F5F9 | #1E293B |
| muted-foreground | #64748B | #94A3B8 |
| destructive | #EF4444 | #7F1D1D |
| destructive-foreground | #F8FAFC | #F8FAFC |
| border / input | #E2E8F0 | #1E293B |
| ring | #020817 | #CBD5E1 |

Radius: `--radius` = 8px. `rounded-lg` = 8px, `rounded-md` = 6px, `rounded-sm` = 4px. Explicit classes like `rounded-2xl` (16px), `rounded-3xl` (24px) and `rounded-full` appear per screen below.

Browser/OS theme color: `#4f46e5` (indigo-600). App short name: "FiNN". Brand image: `finn.jpeg`.

## Important rendering note: progress bars

Callers pass an `indicatorClassName` to set bar colors (for example rose/amber for budgets, white for goals, yellow for the emergency fund). The base progress widget ignores this prop. **On screen, every progress indicator renders in `primary` color** on a `secondary` track (default height 16px, fully rounded, overridden per use, usually 8px). The intended colors are documented per screen below. Choose deliberately in Flutter: match current visuals (primary only) or the intended colors.

---


Scope: visual/UX only. Tailwind classes converted to px (base 1rem = 16px, 1 Tailwind spacing unit = 4px). Colors are shadcn HSL tokens converted to hex, plus Tailwind default palette hex.

## 0. Global Tokens

### Color tokens (shadcn, from src/globals.css)

| Token | Light | Dark |
|---|---|---|
| background | #FFFFFF | #020817 |
| foreground | #020817 | #F8FAFC |
| card / card-foreground | #FFFFFF / #020817 | #020817 / #F8FAFC |
| primary | #0F172A | #F8FAFC |
| primary-foreground | #F8FAFC | #0F172A |
| secondary, muted, accent | #F1F5F9 | #1E293B |
| muted-foreground | #64748B | #94A3B8 |
| border, input | #E2E8F0 | #1E293B |
| destructive | #EF4444 | #7F1D1D |
| destructive-foreground | #F8FAFC | #F8FAFC |
| ring | #020817 | #CBD5E1 |

- Radius base `--radius` = 8px. `rounded-lg` = 8px, `rounded-md` = 6px, `rounded-sm` = 4px.
- Global: `* { border-color: border }`. `body` = background + foreground.
- Utility `.no-scrollbar` hides scrollbars (WebKit and Firefox).
- `.safe-area-pt` = padding-top `env(safe-area-inset-top)`. `.safe-area-pb` = padding-bottom `env(safe-area-inset-bottom)`.
- `text-white` used directly everywhere on gradient cards.
- Tailwind opacity modifiers are alpha over the given hex (e.g. `bg-white/10` = #FFFFFF at 10%, `bg-black/80` = #000000 at 80%).

### Font
- No custom font loaded in index.html. Tailwind config has no `fontFamily`. Assume default Tailwind sans stack (not verified in globals.css).
- Weights: `font-medium` 500, `font-semibold` 600, `font-bold` 700, `font-extrabold` 800, `font-black` 900.
- Tracking: `tracking-tighter` -0.05em, `tracking-tight` -0.025em, `tracking-wide` 0.025em, `tracking-widest` 0.1em, `tracking-[0.2em]` 0.2em, `tracking-wider` 0.05em.
- Line height: `leading-none` 1, `leading-tight` 1.25, `leading-snug` 1.375, `leading-relaxed` 1.625.
- Numerals: AnimatedCounter uses `tabular-lining` (tabular, lining figures).

### Tailwind palette hex used (default Tailwind v3 palette)
- emerald: 50 #ECFDF5, 200 #A7F3D0, 300 #6EE7B7, 400 #34D399, 500 #10B981, 600 #059669, 800 #065F46, 900 #064E3B, 950 #022C22, 100 #D1FAE5
- teal-800 #115E59
- rose: 50 #FFF1F2, 300 #FDA4AF, 500 #F43F5E, 600 #E11D48, 950 n/a; red-800 #991B1B
- amber: 50 #FFFBEB, 100 #FEF3C7, 200 #FDE68A, 400 #FBBF24, 500 #F59E0B, 600 #D97706; orange-600 #EA580C
- blue: 50 #EFF6FF, 500 #3B82F6, 600 #2563EB, 700 #1D4ED8, 800 #1E40AF
- indigo: 50 #EEF2FF, 100 #E0E7FF, 500 #6366F1, 600 #4F46E5, 900 #312E81, 950 #1E1B4B
- violet: 100 #EDE9FE, 200 #DDD6FE, 400 #A78BFA, 500 #8B5CF6, 600 #7C3AED, 700 #6D28D9
- pink-600 #DB2777
- green: 50 #F0FDF4, 500 #22C55E, 600 #16A34A
- slate: 100 #F1F5F9, 300 #CBD5E1, 500 #64748B, 800 #1E293B, 950 #020617
- zinc: 50 #FAFAFA, 800 #27272A, 950 #09090B
- gray: 50 #F9FAFB, 800 #1F2937, 950 #030712
- yellow-300 #FDE047

### Icons
- Library: lucide-react. Default size 24px. Sizes below are explicit.
- Stroke: default 2 unless noted (`strokeWidth={2.5}` in toasts).

### Haptics (navigator.vibrate, Android only, silently ignored elsewhere)
| Type | Pattern (ms) |
|---|---|
| success | [10, 30, 10] |
| warning | [30, 50, 10] |
| error | [50, 50, 50] |
| light | 5 |
| medium | 10 |
| heavy | 20 |
| selection | 2 |

---

## App Shell & Navigation

### Root layout
- Root div: `min-h-screen bg-background text-foreground`.
- Router: react-router `BrowserRouter`.
- Routes and screen names (page title in parentheses is the screen name shown in the app):

| Path | Screen | Shell |
|---|---|---|
| `/` | Dashboard (Home) | MobileShell + AuthGuard |
| `/history` | History | MobileShell + AuthGuard |
| `/insights` | Insights | MobileShell + AuthGuard |
| `/goals` | Goals | MobileShell + AuthGuard |
| `/subscriptions` | Subscriptions (Recurring Costs) | MobileShell + AuthGuard |
| `/pending-transactions` | Pending Transactions (Pending Ledger) | MobileShell + AuthGuard |
| `/settings` | Settings | MobileShell + AuthGuard |
| `/categories` | Categories | MobileShell + AuthGuard |
| `/timeline` | Timeline (Monthly Story) | MobileShell + AuthGuard |
| `/login` | Login | none (public) |
| `/verify-otp` | Verify OTP | none (public) |
| `/auth/callback` | Auth callback | none (public) |
| `*` | Not Found | MobileShell (no AuthGuard) |

- Tour overlay (TourGuide) mounted globally, public guard wrapper.
- Toaster mounted globally (see Shared UI).

### MobileShell (phone frame)
- Outer: `flex justify-center min-h-screen bg-gray-50 dark:bg-gray-950` → light #F9FAFB, dark #030712.
- Inner column: `w-full max-w-md` = max width 448px, `bg-background`, `shadow-2xl`, `flex flex-col`. On desktop it is a centered 448px column on a gray backdrop. On phone it is full width.
- Main: `flex-grow overflow-y-auto pb-24 safe-area-pt no-scrollbar`. Bottom padding 96px. Top padding = safe-area top inset. Scrollbar hidden.
- Global overlays inside shell: ScrollToTop, NetworkStatus (offline banner).

### Bottom navigation bar
- Element: `nav` `fixed bottom-0 left-1/2 -translate-x-1/2 w-full max-w-md bg-card border-t dark:border-gray-800 z-50 safe-area-pb`.
  - Position: fixed bottom, centered, 448px max width.
  - Background: `bg-card` (light #FFFFFF, dark #020817).
  - Top border 1px, color `border` (light #E2E8F0), dark gray-800 #1F2937.
  - Padding bottom: safe-area inset.
  - z-index 50.
- Inner row: `flex justify-around h-16 items-center` → 64px tall row, items evenly spaced.
- Items (in order, left to right, each `flex-1 h-full`):

| # | Label | Icon (lucide) | Route |
|---|---|---|---|
| 1 | Home | LayoutDashboard | `/` |
| 2 | Goals | Target | `/goals` |
| 3 | History | History | `/history` |
| 4 | Settings | Settings | `/settings` |

- Each item: `flex flex-col items-center justify-center p-1 flex-1 h-full transition-colors duration-200 active:scale-95`.
- Icon: size 20px (icon-only, 20x20).
- Label: `text-[10px] mt-0.5 truncate font-medium` → 10px font, weight 500, 2px top margin, single line with ellipsis. No uppercase.
- Colors:
  - Active (`location.pathname === item.path`): `text-primary` → #0F172A light; dark `text-primary-foreground` → #0F172A (note: on dark this resolves to #0F172A, which is dark on the dark bg; likely a bug. Dark active label is nearly invisible. Verify).
  - Inactive: `text-muted-foreground` → #64748B light, #94A3B8 dark. Hover: `text-foreground`.
- No active indicator pill, underline, or badge. Active state = color only.
- Links use `replace={true}` (no history entries).
- Tap: `triggerHaptic('selection')` → vibrate 2ms.
- Press feedback: scale to 95% while pressed (`active:scale-95`).

### Floating Action Button (FAB) — Home only
- Rendered inside the Dashboard page (not the shell). Element: shadcn Button with `size="icon"`, `id="tour-add-fab"`.
- Position: `fixed bottom-24 right-5` → bottom 96px, right 20px (viewport-fixed, not container-fixed; on desktop it sits at the viewport's right edge, not at the 448px column edge).
- Size: `w-14 h-14` = 56 x 56px, `rounded-full` (circle).
- Background: `bg-primary` → #0F172A light, #F8FAFC dark. Hover from base button: `hover:bg-primary/90` (overridden to the same bg; scale is what changes).
- Shadow: `shadow-2xl` (Tailwind: 0 25px 50px -12px rgba(0,0,0,0.25)).
- z-index: `z-40` (below nav z-50).
- Icon: `Plus`, `w-6 h-6` = 24px, color `text-primary-foreground` (#F8FAFC light, #0F172A dark).
- Transition: `transition-all duration-300`.
- Scroll behavior (conditional visual state):
  - Scroll direction down (more than 10px delta): `translate-y-32 opacity-0` → slides 128px down and fades out (hidden).
  - Scroll up (or at rest): `translate-y-0 opacity-100 hover:scale-105`.
- Tap: `triggerHaptic('medium')` → 10ms, then opens AddTransactionSheet (bottom sheet).

### Page header
- Header is NOT part of the shell. Each page renders its own header. Dashboard header:
  - Container: `flex items-center justify-between pt-2 px-1` → top padding 8px, horizontal 4px.
  - Left block:
    - Line 1: "Dashboard" — `text-xl font-black text-primary` → 20px, weight 900, color #0F172A light / #F8FAFC dark.
    - Line 2: "Welcome, {displayName}" — `text-lg font-black text-foreground tracking-tight` → 18px, weight 900, tracking -0.025em.
    - displayName = profile display name, else email prefix before "@", else "User".
  - Right: help button (see Dashboard).
- Page body wrapper on Dashboard: `p-3 space-y-8 pb-32` → 12px padding all sides, 32px vertical gap between sections, 128px bottom padding (clears FAB and nav).

### Offline banner (NetworkStatus)
- Shown only when `navigator.onLine` is false, listens to online/offline events.
- Element: `fixed top-0 left-0 right-0 z-[100] bg-destructive text-destructive-foreground px-4 py-2 text-center shadow-md`.
  - Full width, top of viewport, z-index 100.
  - Background #EF4444 (destructive light), text #F8FAFC.
  - Padding: 16px horizontal, 8px vertical.
  - Shadow: `shadow-md`.
  - Enter animation: `animate-in slide-in-from-top-full duration-300` (slides down from top, 300ms).
- Inner row: `flex items-center justify-center gap-2 text-xs font-bold uppercase tracking-widest` → 12px, weight 700, uppercase, tracking 0.1em, gap 8px.
- Icon: `WifiOff` `h-4 w-4` = 16px.
- Copy: **"You are offline. Changes may not save."**
- Disappears instantly when back online (no exit animation).

### Scroll to top
- ScrollToTop component resets scroll on route change (no visual).

### Global back handling (GlobalBackHandler)
- Hardware/browser back (popstate):
  1. If an input, textarea, or contentEditable is focused: blur it (closes keyboard), re-push history state, do not navigate. No visual besides keyboard closing.
  2. Else: closes the top-most open sheet/drawer.
- Implication: on mobile, back gesture closes open bottom sheets before navigating.

### Page title
- Dynamic document title via PageTitleUpdater (not read; not visual on screen).

### index.html / PWA metadata (visible only in OS share/home screen)
- `<title>`: "FiNN - Personal Finance Command Center".
- theme-color: #4F46E5 (indigo-600) (address bar tint on Android).
- Viewport: `width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover` → no pinch zoom, draws under notch.
- Apple: `apple-mobile-web-app-capable` yes, status bar style default, title "FiNN".
- OG and Twitter image: `/finn.jpeg`.
- Apple touch icon: `/placeholder.svg` (placeholder asset).
- Manifest: `/manifest.json`.
- Currency in SEO: INR.

---

## Shared UI Primitives

### Button (shadcn, src/components/ui/button.tsx)
- Base: `inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium` → 14px, weight 500, 8px icon gap, radius 6px, single line.
- Icon children: `[&_svg]` size 16px (`size-4`), flex-shrink 0, pointer-events none.
- Focus ring: 2px ring `#020817`, offset 2px (keyboard focus only).
- Disabled: opacity 50%, no pointer events.
- Transition: `transition-colors` (150ms default).

Variants (default size h-10 px-4 py-2 unless overridden):

| Variant | Classes | Light colors |
|---|---|---|
| default | bg-primary text-primary-foreground hover:bg-primary/90 | bg #0F172A, text #F8FAFC, hover 90% |
| destructive | bg-destructive text-destructive-foreground hover:bg-destructive/90 | bg #EF4444 |
| outline | border border-input bg-background hover:bg-accent hover:text-accent-foreground | 1px #E2E8F0 border, white bg, hover #F1F5F9 |
| secondary | bg-secondary text-secondary-foreground hover:bg-secondary/80 | bg #F1F5F9 |
| ghost | hover:bg-accent hover:text-accent-foreground | transparent, hover #F1F5F9 |
| link | text-primary underline-offset-4 hover:underline | text #0F172A, underline on hover |

Sizes:

| Size | Classes | Height | Padding | Radius |
|---|---|---|---|---|
| default | h-10 px-4 py-2 | 40px | 16px x 8px | 6px |
| sm | h-9 rounded-md px-3 | 36px | 12px | 6px |
| lg | h-11 rounded-md px-8 | 44px | 32px | 6px |
| icon | h-10 w-10 | 40 x 40 | 0 | 6px |

Common overrides used in the app (instance-level):
- Full-width primary CTA: `h-12 rounded-xl font-bold` → 48px tall, 12px radius, bold.
- Small pill button in cards: `h-8 px-3 rounded-lg text-[10px] uppercase` → 32px, 8px radius, 10px uppercase.
- Tiny text buttons: `text-[10px] font-black uppercase tracking-widest h-11 rounded-2xl` → 44px tall, 16px radius.
- Icon ghost in headers: `h-10 w-10 rounded-full` or `h-7 w-7 rounded-full hover:bg-white/10`.

### Card
- Base: `rounded-lg border bg-card text-card-foreground shadow-sm` → 8px radius, 1px border (#E2E8F0 light, #1E293B dark), bg card, shadow-sm (0 1px 2px rgba(0,0,0,0.05)).
- Most instances override: `border-none shadow-lg`, `overflow-hidden`, `relative`, plus gradient backgrounds.
- CardHeader default `flex flex-col space-y-1.5 p-6` (24px). Overridden often to `p-3.5 sm:p-4 pb-2` (14px, 16px at sm+).
- CardContent default `p-6 pt-0`. Overridden to `p-3`, `p-3.5`, `p-4`, `p-5`, `p-0`.
- CardTitle default `text-2xl font-semibold leading-none tracking-tight`. Overridden in app.
- CardFooter `flex items-center p-6 pt-0` (unused in listed files).

### Bottom sheet
- Overlay: `fixed inset-0 z-50 bg-black/80` → #000 at 80% (rgba(0,0,0,0.8)). Fades in/out with `fade-in-0` / `fade-out-0` (tailwindcss-animate defaults).
- Content variants:
  - `side=bottom`: `inset-x-0 bottom-0 border-t`, full width, slides up from bottom. Used for AddTransactionSheet-style sheets.
  - `side=right/left`: `h-full w-3/4 sm:max-w-sm` → 75% width, max 384px on sm+.
  - `side=top`: full width, top.
- Panel: `fixed z-50 gap-4 bg-background p-6 shadow-lg` → 24px padding, 16px child gap, background #FFFFFF / #020817, shadow-lg.
- Animation: `transition ease-in-out`:
  - open: `slide-in-from-bottom` duration 500ms.
  - close: `slide-out-to-bottom` duration 300ms.
- Close X button: `absolute right-4 top-4` → 16px from top-right, icon `X` 16px (h-4 w-4), opacity 70%, hover 100%. Focus ring 2px.
- Title: `text-lg font-semibold text-foreground` → 18px, weight 600.
- Description: `text-sm text-muted-foreground` → 14px, #64748B.
- Header: `flex flex-col space-y-2 text-center sm:text-left` → centered on mobile, 8px gap.
- Footer: `flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2` → stacked buttons, reversed column on mobile.

### Drawer
- Overlay: `fixed inset-0 z-50 bg-black/80`.
- Content: `fixed inset-x-0 bottom-0 z-50 mt-24 flex h-auto flex-col rounded-t-[10px] border bg-background`.
  - Top corners radius 10px.
  - Top margin 96px (max-height cap from top).
  - 1px border (#E2E8F0 / #1E293B).
  - Background white / #020817.
- Drag handle (always shown at top): `mx-auto mt-4 h-2 w-[100px] rounded-full bg-muted` → centered, 16px top margin, 8px tall, 100px wide, pill, color #F1F5F9 light / #1E293B dark.
- Header: `grid gap-1.5 p-4 text-center sm:text-left` → 16px padding, 6px gap, centered on mobile.
- Footer: `mt-auto flex flex-col gap-2 p-4` → 16px padding, 8px gap, pinned to bottom.
- Title: `text-lg font-semibold leading-none tracking-tight` → 18px, 600, -0.025em.
- Description: `text-sm text-muted-foreground`.
- Scale background: vaul `shouldScaleBackground` true (page behind scales down as drawer opens).
- Dismiss: drag down (vaul gesture). Back button closes it (GlobalBackHandler).

### Toast system (Sonner + custom ToastBody)

#### Toaster
- Position: `top-center` (appears at top, centered).
- Default duration: 3000ms.
- Wrapper class: `toast w-full p-0 bg-transparent border-none shadow-none font-sans` → full width, no chrome; ToastBody provides the look.
- Theme follows system/next-themes.

#### ToastBody
- Container: `w-full flex items-center gap-4 p-4 rounded-3xl shadow-xl border-2 transition-all duration-300`.
  - Radius 24px, padding 16px, gap 16px, border 2px, shadow-xl, 300ms transition.
- Icon tile: `w-12 h-12 rounded-2xl flex items-center justify-center shrink-0 shadow-sm` → 48 x 48px, radius 16px, centered, shadow-sm.
- Icon: `w-7 h-7` = 28px, `strokeWidth={2.5}`.
- Text column: `flex-1 min-w-0`.
  - Title: `text-base font-black leading-tight tracking-tight` → 16px, weight 900, line-height 1.25, tracking -0.025em.
  - Subtitle: `text-xs font-bold text-muted-foreground mt-0.5 truncate opacity-80` → 12px, weight 700, 2px top margin, single line ellipsis, 80% opacity.
- Action slot: `shrink-0` (right side, used by PWA update button).

Per-type styles:

| Type | Panel bg (light / dark) | Border (light / dark) | Icon tile bg | Icon color | Title color (light / dark) | Icon |
|---|---|---|---|---|---|---|
| success | emerald-50 #ECFDF5 / emerald-950 at 30% | emerald-200 #A7F3D0 / emerald-800 #065F46 | emerald-500 #10B981 | white | emerald-900 #064E3B / emerald-100 #D1FAE5 | CheckCircle2 |
| error | rose-50 #FFF1F2 / rose-950 at 30% | rose-200 #FECDD3 / rose-800 #9F1239 | rose-500 #F43F5E | white | rose-900 #881337 / rose-100 #FFE4E6 | XCircle |
| warning | amber-50 #FFFBEB / amber-950 at 30% | amber-200 #FDE68A / amber-800 #92400E | amber-500 #F59E0B | white | amber-900 #78350F / amber-100 #FEF3C7 | AlertTriangle |
| info | blue-50 #EFF6FF / blue-950 at 30% | blue-200 #BFDBFE / blue-800 #1E40AF | blue-500 #3B82F6 | white | blue-900 #1E3A8A / blue-100 #DBEAFE | Info |
| loading | zinc-50 #FAFAFA / zinc-900 #18181B | zinc-200 #E4E4E7 / zinc-800 #27272A | zinc-200 / zinc-800 | zinc-600 #52525B / zinc-400 #A1A1AA | zinc-900 / zinc-100 | Loader2 (spinning) |

Note: dark mode hex for rose/amber/blue borders and panels are Tailwind defaults (derived from palette; verify if pixel-exact needed).

Toast helpers and copy:

| Helper | Haptic | Duration | Title (arg) | Subtitle default |
|---|---|---|---|---|
| showSuccess | success | 3000ms | message | (none) |
| showError | error | 4000ms | message | "Something went wrong." |
| showWarning | warning | 4000ms | message | (none) |
| showInfo | light | 3000ms | message | (none) |
| showLoading | light | Infinity (manual dismiss) | message | "Please wait..." (spinner icon) |

#### PWA update toast
- Appears when a new service worker is ready. Duration Infinity (stays until acted on).
- Type: info (blue).
- Title: **"New Update Available"**
- Subtitle: **"A better version of FiNN is ready."**
- Action button: `size="sm"`, classes `bg-blue-600 hover:bg-blue-700 text-white h-9 px-4 rounded-xl text-xs font-bold shadow-lg shadow-blue-500/20`.
  - Height 36px, padding 16px, radius 12px, 12px bold.
  - Shadow: blue-500 at 20%.
  - Icon `Download` `h-3.5 w-3.5` (14px), `mr-2` (8px right margin).
  - Label: **"Update Now"**.
- Tap: activates new service worker and reloads.
- Service worker update check runs hourly (no visual).

### Skeleton loaders

#### ListSkeleton
- Container: `space-y-3` → 12px between rows.
- Count: default 4 rows.
- Row: Card `p-0 border-none shadow-sm bg-muted/20` → 8px radius, no border, shadow-sm, background #F1F5F9 at 20% (light) / #1E293B at 20% (dark).
- Row content: `CardContent p-3 flex items-center justify-between` → 12px padding.
  - Left group: `flex items-center space-x-3 w-full` (12px gap).
    - Avatar: `h-10 w-10 rounded-full flex-shrink-0` → 40px circle.
    - Text stack: `space-y-2 flex-1` (8px gap).
      - Title bar: `h-4 w-3/4 max-w-[150px]` → 16px tall, 75% width, max 150px.
      - Subtitle bar: `h-3 w-1/2 max-w-[100px]` → 12px tall, 50%, max 100px.
  - Right stack: `flex flex-col items-end space-y-2` (8px gap, right aligned).
    - Amount bar: `h-4 w-16` → 16 x 64px.
    - Date bar: `h-3 w-10` → 12 x 40px.
- Skeleton primitive (components/ui/skeleton, not read): assume shadcn default `animate-pulse rounded-md bg-muted` (#F1F5F9 light / #1E293B dark). Unverified.

#### DashboardCardSkeleton
- Card: `p-4 shadow-lg` (white card, 1px border, 16px padding, shadow-lg).
- Note: `height` prop is accepted but NOT applied; all instances render the same height.
- CardContent: `p-0 pt-4 space-y-4` (top 16px, 16px gaps).
- Row 1: `flex items-center justify-between` — title bar `h-4 w-1/3` (16px tall, 33% wide); right circle `h-6 w-6 rounded-full` (24px).
- Block A (`space-y-3 pt-2`, 12px gaps, 8px top):
  - Row: circle `h-5 w-5 rounded-full` (20px), then bar `h-4 w-2/3` (16px, 67%), gap 8px.
  - Full bar `h-3 w-full` (12px).
- Block B: identical to Block A.
- Used for: Liquidity balance (passed height h-32, ignored), Unsettled Ledger, Behavior Analysis while loading.

#### Balance and other skeleton variants
- RecurringCostCard loading: `Skeleton h-40 w-full rounded-3xl` (160px tall, 24px radius).
- AttentionSummaryCard loading: `Skeleton h-48 w-full rounded-xl` (192px, 12px radius).
- PendingSummaryCard loading: `Card h-48 w-full rounded-3xl animate-pulse bg-muted` (192px, 24px radius, pulsing solid #F1F5F9 / #1E293B).
- InsightsSummaryCard loading: `Card h-40 w-full rounded-3xl animate-pulse bg-muted` (160px).
- BalanceCard loading: gradient card with label and "Loading..." (see Dashboard) with spinner, not a skeleton.

### Empty state
- Props: icon, title, description, optional action label + handler.
- Container: `flex flex-col items-center justify-center py-12 text-center p-4 border-2 border-dashed rounded-[1.5rem] bg-muted/10 animate-in fade-in zoom-in-95 duration-300`.
  - Vertical padding 48px, horizontal 16px.
  - Dashed 2px border (color border token).
  - Radius 24px.
  - Background #F1F5F9 at 10%.
  - Enters: fade in + zoom from 95% to 100%, 300ms.
- Icon tile: `bg-muted p-4 rounded-full mb-3 shadow-sm` → circle, 16px padding, 12px bottom margin, shadow-sm, #F1F5F9 / #1E293B.
- Icon: `h-8 w-8` = 32px, color `text-muted-foreground/70` (#64748B at 70%).
- Title: `text-base font-black uppercase tracking-tight text-foreground/80 mb-1` → 16px, weight 900, uppercase, -0.025em, foreground 80%, 4px bottom margin.
- Description: `text-xs font-medium text-muted-foreground max-w-[240px] mb-5 leading-relaxed` → 12px, weight 500, max width 240px, 20px bottom margin, line-height 1.625.
- Action (optional): outline button `h-9 rounded-xl font-bold text-xs uppercase tracking-wider shadow-sm bg-background` → 36px tall, 12px radius, bold 12px uppercase, tracking 0.05em, white bg, shadow-sm.
- Note: EmptyState is not rendered by any of the listed dashboard files. Its use on other screens is unknown from this scope.

### Loading screen
- Full screen: `flex flex-col items-center justify-center h-screen w-full bg-background text-foreground animate-in fade-in duration-300` → centered, background white / #020817, fades in over 300ms.
- Spinner: `Loader2` `h-10 w-10` = 40px, `animate-spin` (1s linear infinite), color `text-primary` (#0F172A light / #F8FAFC dark), `mb-4` = 16px below.
- Copy: **"Loading FiNN..."** — `text-sm font-bold uppercase tracking-widest text-muted-foreground animate-pulse` → 14px, weight 700, uppercase, tracking 0.1em, #64748B, pulsing opacity (2s ease-in-out infinite).
- No logo/splash image or video is rendered by this component.
- finn.jpeg and finn.mp4:
  - `/finn.jpeg` is referenced ONLY in index.html as og:image and twitter:image (social share preview).
  - `/finn.mp4` is NOT referenced in any of the listed files (src/, index.html). It exists in `public/` only. Not used in the loading/splash flow in this scope. If a splash video exists, it is elsewhere (AuthGuard or main.tsx were not part of this read; main.tsx does not reference it).

### Animated counter
- Counts from its current value to the new `value` over `duration` (default 500ms), using requestAnimationFrame.
- Easing: cubic ease-out, `1 - (1 - t)^3`.
- Starts at 0 on first mount, so numbers count up from 0 on load.
- Display: integer rounded up (`Math.ceil`) by default; `decimals` sets fixed decimals (default 0).
- Formatting: `toLocaleString(undefined, {min/max fraction digits})`. Grouping follows device locale (en-US: 123,456; en-IN: 1,23,456).
- Sign: "-" when negative. "+" only when `showSign` is set (not used in listed screens).
- Prefix: "₹" in all listed uses (INR).
- Class: `tabular-lining tracking-tighter` (tabular figures, letter-spacing -0.05em). Caller sets size/weight.

---

## Dashboard Screen (Home, `/`)

Top to bottom. Root: `p-3 space-y-8 pb-32` (12px padding, 32px between sections, 128px bottom).

### 1. Header row
- Layout: `flex items-center justify-between pt-2 px-1`.
- Left: "Dashboard" (20px, 900, #0F172A light / #F8FAFC dark) above "Welcome, {displayName}" (18px, 900, tracking -0.025em, foreground).
- Right: help button. Ghost icon button `h-10 w-10 rounded-full text-muted-foreground`, icon `HelpCircle` 24px. Tap: dispatches "start-tour" event → opens guided tour on this page.

### 2. Fresh-user state (zero transactions AND zero pending items, not loading)
Replaces sections 3 to 9. Header stays.
- Card: `border-none shadow-xl bg-gradient-to-br from-primary to-primary/80 text-primary-foreground overflow-hidden` → gradient from #0F172A to #0F172A at 80% (dark mode: #F8FAFC to 80%), text #F8FAFC, shadow-xl, 24px spacing? (no, card radius is 8px: rounded-lg default; no override).
- CardContent: `p-6 text-center space-y-4` → 24px padding, centered, 16px gaps.
- Icon tile: `bg-white/20 w-16 h-16 rounded-full flex items-center justify-center mx-auto backdrop-blur-sm` → 64px circle, white 20%, blur 4px.
  - Icon: `Wallet` 32px, white.
- Title: "Welcome to FiNN" — `text-2xl font-black mb-1` → 24px, 900, 4px bottom margin.
- Subtitle: "Your personal finance command center." — `text-sm opacity-90 leading-relaxed font-medium` → 14px, 90% opacity, 500 weight, lh 1.625.
- CTA: full-width button `w-full bg-white text-primary hover:bg-white/90 font-bold h-12 rounded-xl`:
  - 48px tall, 12px radius, bold, white bg, #0F172A text.
  - Label: **"Record First Transaction"**.
  - Tap: haptic medium (10ms), opens AddTransactionSheet.

### 3. Section: Liquidity Status
- Section header (SectionHeader component, see below): icon `Wallet`, title **"LIQUIDITY STATUS"** (text is "Liquidity Status" rendered uppercase), tile color bg-blue-600 (#2563EB).
- Body:
  - Loading: `DashboardCardSkeleton`.
  - Loaded: `space-y-3` (12px gap):
    - a) BalanceCard (see 3a).
    - b) Two-column grid `grid grid-cols-2 gap-3` (12px gap), each equal width:
      - Income SummaryCard (see 3b).
      - Expense SummaryCard (see 3b).

#### SectionHeader (used by all sections)
- Wrapper: `space-y-0.5 mb-3 px-1` → 2px gap, 12px bottom margin, 4px horizontal padding.
- Row: `flex items-center gap-2.5` → 10px gap.
- Icon tile: `p-2 rounded-xl shadow-sm` + color class → 8px padding, 12px radius, shadow-sm. Tile = 32px square (16px icon + 16px padding).
  - Icon: `h-4 w-4` = 16px, white.
- Title: `text-base font-black tracking-tight text-foreground uppercase` → 16px, 900, -0.025em, uppercase. Renders as e.g. "LIQUIDITY STATUS".
- Section tile colors:

| Section | Icon | Tile color |
|---|---|---|
| Liquidity Status | Wallet | blue-600 #2563EB |
| Monthly Story | BookOpen | amber-600 #D97706 |
| Monitoring Alerts | ShieldAlert | destructive #EF4444 |
| Unsettled Ledger | Clock | violet-600 #7C3AED |
| Behavior Analysis | Sparkles | emerald-600 #059669 |
| Recurring Costs | Zap | pink-600 #DB2777 |

Each section body: `space-y-4` (16px between header and content).

### 3a. Balance card ("Liquid Cash")
- Card: `p-4 shadow-lg border-none bg-gradient-to-br from-blue-700 to-indigo-900 text-white transition-all duration-300 hover:shadow-xl relative overflow-hidden`.
  - Gradient 135°-ish (to bottom-right): #1D4ED8 → #312E81.
  - Padding 16px, radius 8px (default card, no override), shadow-lg → hover shadow-xl.
- Watermark: absolute top-0 right-0, `p-3 opacity-10` (10%), `Wallet` size 100px, white.
- Content: `relative z-10 flex flex-col space-y-3` (12px gap), row `flex justify-between items-center`:
  - Label: "Liquid Cash" — `text-[10px] font-black uppercase tracking-widest opacity-80` → 10px, 900, uppercase, 0.1em tracking, 80% opacity.
  - Value: `text-3xl font-black tracking-tighter` → 30px (line 36px), 900, -0.05em tracking. Shows "₹" + AnimatedCounter (whole rupees, count-up 500ms).
  - Icon tile right: `bg-white/10 p-2.5 rounded-xl backdrop-blur-md` → 10px padding, 12px radius, white 10%, blur 12px. Icon `Wallet` 20px white.
- Value = available_balance (0 if missing).
- Loading variant:
  - Gradient `from-blue-800 to-indigo-950` (#1E40AF → #1E1B4B), `p-4`.
  - Label "Available Balance" `text-xs opacity-80 font-medium` → 12px, 500, 80%.
  - Right: `Loader2` `w-5 h-5 opacity-80 animate-spin`.
  - Value text: "Loading..." `text-2xl font-extrabold tracking-tight` → 24px, 800.
- Tour target id: `tour-balance-card`.

### 3b. Income / Expense summary cards (side by side)
Each is a link (block, full height) to `/history?month=YYYY-MM&type=income|expense`. Tap: `active:scale-95` (press shrinks to 95%).

- Card: `relative overflow-hidden border-none shadow-md text-white transition-all duration-300 hover:shadow-lg active:scale-95 bg-gradient-to-br h-full` + color class.
  - Income gradient: `from-emerald-600 to-teal-800` → #059669 → #115E59.
  - Expense gradient: `from-rose-600 to-red-800` → #E11D48 → #991B1B.
  - Radius 8px (default card). Shadow md → lg on hover.
- Watermark: absolute top-0 right-0, `p-1.5 opacity-10 pointer-events-none translate-x-1/4 -translate-y-1/4`, icon size 80px, white. Icon: TrendingUp (income) or TrendingDown (expense).
- CardContent: `p-3.5 flex flex-col space-y-2 relative z-10 h-full justify-between` → 14px padding, 8px gaps, content pushed top and bottom.
  - Top row `flex items-center justify-between gap-1` (4px gap):
    - Icon chip: `p-1 rounded-md backdrop-blur-md shrink-0` → 4px padding, 6px radius; bg emerald-500 at 20% (#10B981 / 20%) income, rose-500 at 20% (#F43F5E / 20%) expense. Icon `w-3 h-3` = 12px, white. Icon = TrendingUp (income) or TrendingDown (expense).
    - Month switcher pill: `flex items-center bg-black/10 rounded-full p-0.5 border border-white/10 shrink-0` → black 10%, full pill, 2px padding, 1px white 10% border.
      - Prev button: `p-0.5 hover:bg-white/10 rounded-full` with `ChevronLeft` size 10px.
      - Label: `text-[10px] font-black uppercase px-0.5 min-w-[36px] text-center` → 10px, 900, uppercase, min-width 36px. Text format `MMM yy` (e.g. "OCT 26").
      - Next button: same, `ChevronRight` size 10px.
      - Tap chevrons: changes month, does NOT navigate (preventDefault).
  - Bottom stack `space-y-0.5` (2px):
    - Label: `text-[11px] font-black uppercase tracking-widest opacity-80 leading-none mb-0.5` → 11px, 900, uppercase, 0.1em, 80%. Text: **"Income"** or **"Expense"**.
    - Amount: `text-lg font-black tracking-tighter truncate leading-none` → 18px, 900, -0.05em, single line ellipsis. "₹" + AnimatedCounter (whole rupees).
    - Sub-label: `text-[10px] font-bold uppercase tracking-wider opacity-60 leading-none mt-0.5` → 10px, 700, uppercase, 0.05em, 60%. Text: **"Current Month"** if the selected month is this month, else the full month name in caps (e.g. "OCTOBER" when uppercased by CSS? Source is `MMMM` with no uppercase transform beyond the class; class uppercases it).
- Month change: when the stored last-viewed month differs, card pulses (`animate-pulse`) for 800ms.
- Amount logic: sum of transactions of that type in the selected month, excluding loan-linked income.
- Tour target ids: `tour-summary-cards` on the grid wrapper.

Visual states: none for color on value (always white on gradient).

### 4. Section: Monthly Story (conditional: day of month >= 25 only)
- Wrapper: `space-y-4 animate-in fade-in slide-in-from-bottom-4 duration-700` → fades in and slides up 16px over 700ms.
- Header: BookOpen, title "Monthly Story", tile amber-600 #D97706.
- Link `block` → Card:
  - Card: `border-none shadow-lg bg-gradient-to-r from-amber-500 to-orange-600 text-white overflow-hidden relative group active:scale-[0.98] transition-all`.
    - Gradient horizontal: #F59E0B → #EA580C.
    - Press: scale 98%.
    - Hover (group): chip shifts right 4px.
  - Watermark: `absolute top-0 right-0 p-4 opacity-10 pointer-events-none translate-x-1/4 -translate-y-1/4`, `Sparkles` size 120px, white.
  - CardContent `p-5 flex items-center justify-between relative z-10` → 20px padding.
    - Left stack `space-y-1` (4px):
      - Title: "Read this month's chapter" — `text-lg font-black tracking-tight` → 18px, 900.
      - Sub: "Your financial highlights are ready." — `text-xs font-bold opacity-90 uppercase tracking-widest` → 12px, 700, uppercase, 0.1em.
    - Right chip: `bg-white/20 p-2 rounded-full backdrop-blur-md group-hover:translate-x-1 transition-transform` → 8px padding, circle, white 20%, blur 12px. Icon `ArrowRight` size 20px.

### 5. Section: Monitoring Alerts
- Header: ShieldAlert, title "Monitoring Alerts", tile destructive #EF4444.
- Body: AttentionSummaryCard (see 5a). Loading: `Skeleton h-48 w-full rounded-xl`.
- Tour target id: `tour-alerts`.

#### 5a. Attention card (states)
State priority: onboarding → healthy → alerts. Loading → skeleton.

**State A: Onboarding** (no emergency fund set or target 0)
- Card: `p-0 shadow-lg border-l-4 border-indigo-500 overflow-hidden bg-indigo-50/30` → 4px left border #6366F1, background #EEF2FF at 30%, no padding (inner handles it).
- Inner row: `p-4 flex items-start gap-3` → 16px padding, 12px gap, top aligned.
  - Icon tile: `text-white bg-indigo-500 p-2 rounded-xl` → 8px padding, 12px radius; `ShieldAlert` 20px white.
  - Text column (flex-1):
    - Title: **"Priority #1: Set Emergency Fund"** — `text-sm font-black text-indigo-900 leading-tight` → 14px, 900, #312E81, lh 1.25.
    - Body: **"Define your safety net to protect against shocks."** — `text-xs text-muted-foreground mt-1` → 12px, #64748B, 4px top.
    - CTA: link `inline-block mt-3` (12px top) to `/goals`, containing `Button size="sm"` overridden to `bg-indigo-600 h-8 px-3 rounded-lg text-[10px] uppercase`:
      - Label **"Setup Now"** + `ArrowRight` h-3 w-3 (12px), `ml-1.5` (6px).
      - Button: 32px tall, 12px horizontal, 8px radius, 10px uppercase, bg #4F46E5, white text.

**State B: Healthy** (no critical, no warnings)
- Card: `p-4 shadow-lg border-l-4 border-green-500 bg-green-50/50` → 16px padding, 4px left border #22C55E, bg #F0FDF4 at 50%.
- Header (`p-0 pb-1` → 4px bottom):
  - Title: **"Health: Optimized"** — `text-lg font-bold flex items-center gap-2 text-green-600` → 18px, 700, #16A34A, gap 8px.
  - Icon: `CheckCircle` `h-5 w-5` = 20px, same green.
- Body (`p-0`): **"No urgent alerts found."** — `text-sm text-muted-foreground` → 14px, #64748B.

**State C: Alerts** (critical and/or warnings)
- Card: `p-0 shadow-lg border-l-4 overflow-hidden`:
  - Left border 4px: `border-destructive` (#EF4444) if any critical; else `border-amber-500` (#F59E0B).
- Top bar: `p-4 pb-3 flex justify-between items-center` → 16px sides/top, 12px bottom; bg `bg-destructive/5` (#EF4444 at 5%) if critical, else `bg-amber-500/5`.
  - Left: `flex items-center gap-2` (8px):
    - `Bell` `h-5 w-5` = 20px, color destructive (#EF4444) if critical else amber-500 (#F59E0B).
    - Title: **"Attention Needed"** — `text-lg font-bold` → 18px, 700.
  - Right: `Badge` — variant `destructive` if critical else `secondary`. Text: "{N} Alerts" where N = total count (critical + warnings). Badge styling not read (components/ui/badge not in scope; assume shadcn default: rounded-full, 12px semibold, 2px x 10px padding).
- Items list (each is a Link to its target route; full-width rows; `flex flex-col`; each row has `border-b last:border-b-0`, 1px `border` color separator):
  - Row shell: `px-4 py-3` → 16px sides, 12px vertical. Hover: `transition-colors`.
  - Row layout: `flex items-start gap-3` (12px). Top aligned.
    - Icon chip: `mt-0.5 shrink-0 p-1.5 rounded-full` → 2px top offset, 6px padding, circle; icon 16px (h-4 w-4).
    - Text column `flex-1 min-w-0`:
      - Title row `flex justify-between items-start`: title (`text-sm font-bold leading-tight`, 14px, 700) + `ArrowRight` h-3 w-3 (12px) in muted color on the right.
      - Description: `text-xs text-muted-foreground mt-0.5` → 12px, #64748B, 2px top.
      - Suggestion line: `text-xs font-medium text-indigo-600 mt-1.5 pt-1 border-t border-indigo-100`, prefixed by "💡 " (emoji is part of copy). 12px, 500, #4F46E5, 6px top margin, 4px top padding, 1px top border #E0E7FF. Dark: indigo-400 #818CF8 text, border indigo-900 at 30%.
  - Critical row:
    - Row bg `bg-destructive/5` (#EF4444 at 5%), hover `bg-destructive/10` (10%).
    - Icon chip: `text-white bg-destructive` (white icon on #EF4444 circle).
    - Title color: `text-destructive` (#EF4444).
  - Warning row:
    - Row bg `bg-amber-50/20` (#FFFBEB at 20%), hover `bg-amber-100/30`.
    - Icon chip: `text-amber-600 bg-amber-100` (#D97706 icon on #FEF3C7 circle).
    - Title color: `text-foreground`.

- Alert items (all copy as shown; `{x}` = dynamic value). Only those whose condition is met appear.

| Level | Title | Description | Suggestion | Link | Icon | Condition |
|---|---|---|---|---|---|---|
| Critical | Monthly Deficit | "You've spent ₹{x} more than you earned this month." | "Immediately cut discretionary spending to stop the drain." | /history | TrendingDown | expenses > income and income > 0 |
| Critical | Budget Breached | "{category} limit exceeded by ₹{x}." | "Stop all further spending in this category immediately." | /goals | PieChart | category spend > budget limit |
| Warning | Budget Near Limit | "{category} is at {x}% capacity." | "Slow down spending in this category to avoid a breach." | /goals | PieChart | spend > 80% of limit |
| Warning | Low Savings Rate | "Current rate is {x}%, below your 20% target." | "Reduce non-essential spending for the rest of the month." | /insights | PiggyBank | day >= 15 and income > 0 and savings rate < 20% |
| Warning | Aged Pending Item | "A ledger entry has been open for {n} days." | "Follow up to settle this long-standing transaction." | /pending-transactions | Clock | oldest pending > 25 days |
| Warning | Payment Method Bias | "{mode} used for {x}% of spend." | "Avoid over-reliance on one payment mode for better tracking." | /history | CreditCard | day >= 20 and one mode > 75% of expense |
| Warning | Concentrated Spending | "{category} is 50%+ of your total monthly expense." | "Ensure this single category aligns with your priorities." | /insights | PieChart | day >= 20 and top category > 50% of expense |
| Warning | Large Income Drain | "{category} has consumed 30%+ of your total income." | "This category is a major drain on your earnings. Optimize it." | /insights | TrendingDown | day >= 20 and top category > 30% of income |
| Warning | Subscription Renewal | "{name} (₹{amount}) renews in today" or "...renews in {n} days." | "Check if you still need this service before it charges." | /subscriptions | Repeat | subscription due in 0 to 3 days |

- Not shown: loan/debt alerts (commented out in source).

#### AI recommendation footer (inside Monitoring card, both alert states)
- Container: `bg-gradient-to-r from-blue-600 to-indigo-600 p-4 text-white` → 16px padding, #2563EB → #4F46E5 horizontal gradient.
- Row: `flex items-start gap-3` (12px).
  - Icon: `Lightbulb` `h-5 w-5 shrink-0 mt-0.5 text-yellow-300 fill-yellow-300` → 20px, yellow #FDE047 stroke and fill, 2px top.
  - Label: **"AI Recommendation"** — `text-xs font-bold uppercase opacity-80 tracking-wider mb-1` → 12px, 700, uppercase, 0.05em, 80%, 4px bottom.
  - Body: `text-sm font-medium leading-snug` → 14px, 500, lh 1.375.
    - If alerts exist: "Action Required: Focus on resolving '{top alert title}' first. To clear this alert: {top alert suggestion}" (top alert = first critical, else first warning).
    - If none: "Your financial health is currently optimized with no urgent issues detected. Maintain your current discipline."

- Note: the Attention card has no empty/loading dedicated illustration; loading is a 192px skeleton.

### 6. Section: Unsettled Ledger
- Header: Clock, title "Unsettled Ledger", tile violet-600 #7C3AED.
- Body: loading → DashboardCardSkeleton; loaded → PendingSummaryCard.
- Tour target id: `tour-pending-card`.

#### PendingSummaryCard
- Card: `p-3 shadow-lg transition-all duration-300 hover:shadow-xl relative overflow-hidden border-none text-white bg-gradient-to-br from-violet-700 to-indigo-950`.
  - Gradient #6D28D9 → #1E1B4B (top-left to bottom-right).
  - Padding 12px, shadow-lg → xl on hover.
- Watermark: `absolute bottom-0 right-0 opacity-[0.08] pointer-events-none translate-x-1/4 translate-y-1/4`, `Clock` size 180px, white at 8%.
- Header: `flex flex-row items-center justify-between space-y-0 pb-1.5 px-1 relative z-10` → 6px bottom, 4px sides.
  - Title: `text-xl md:text-2xl font-black flex items-center space-x-2 tracking-tight` → 20px (24px at md+), 900, gap 8px, -0.025em.
    - Icon: `Clock` `h-5 w-5 text-violet-200` (20px, #DDD6FE).
    - Text: **"Pending Items"** rendered `uppercase italic`.
  - Badge: `text-[10px] font-black uppercase px-2 py-0.5 bg-white/20 text-white border-none` → 10px, 900, uppercase, 8px sides, 2px vertical, white 20% pill.
    - Text: `{activeCount}Active` (no space between number and "Active" in source, so renders e.g. "3Active"; uppercase).
- Content: `p-1 pt-3 space-y-4 relative z-10` → 4px padding, 12px top, 16px gaps.
  - Totals grid: `grid grid-cols-2 gap-2 text-center border-b border-white/10 pb-4` → 2 equal columns, 8px gap, centered text, bottom divider 1px white 10%, 16px bottom padding.
    - Col 1 label: **"To Pay"** — `text-[10px] font-black uppercase tracking-widest opacity-60` → 10px, 900, uppercase, 0.1em, 60%.
      - Value: `text-2xl font-black text-rose-300` → 24px, 900, #FDA4AF; "₹" + count-up integer.
    - Col 2 label: **"To Receive"** (same style).
      - Value: `text-2xl font-black text-emerald-300` → 24px, 900, #6EE7B7.
  - Alert pill: `p-3 rounded-2xl text-xs flex items-center space-x-3 border backdrop-blur-sm` → 12px padding, 16px radius, 12px text, 12px icon gap, 1px border, blur 4px.
    - Default variant: `bg-white/10 border-white/5 text-violet-100` (white 10%, border white 5%, #EDE9FE text).
    - Warning variant: `bg-amber-500/20 border-amber-500/30 text-amber-200` (#F59E0B at 20%, border at 30%, #FDE68A text).
    - Icon: 16px (`h-4 w-4`), `flex-shrink-0`.
    - Text: `font-bold tracking-tight` → 12px, 700, -0.025em.
    - Messages and icons:

| Variant | Condition | Copy | Icon |
|---|---|---|---|
| success (default style) | no active pending, or none beyond 14 days and nothing owed | **"All Settled Up!"** | TrendingUp |
| warning | oldest active item older than 14 days | "Oldest: {name} ({N} Days)." (name truncated to 15 chars + "..."; name = person name, else notes, else "Unknown Item") | AlertTriangle |
| info (default style) | a balance to pay exists | "₹{x} Pending To Pay." (x rounded to whole) | TrendingDown |
| info (default style) | balance to receive exists | "Owed ₹{x} From Others." | TrendingUp |

    - Note: the "success" case uses the default (non-warning) pill style.
  - Button row: `flex flex-row gap-3 pt-1` → 12px gap, 4px top.
    - Left: Link `flex-1` to `/pending-transactions` wrapping outline button `size="sm" w-full text-[10px] font-black uppercase tracking-widest h-11 rounded-2xl border-white/20 bg-white/5 hover:bg-white/10 text-white`.
      - Height 44px, 16px radius, 10px uppercase black, border white 20%, bg white 5%, hover white 10%.
      - Icon `ArrowRight` h-3 w-3 (12px), mr-1.5 (6px). Label **"View All"**.
    - Right: `flex-1 bg-violet-500 hover:bg-violet-400 text-white text-[10px] font-black uppercase tracking-widest h-11 rounded-2xl shadow-lg shadow-violet-500/20`.
      - Bg #8B5CF6 (hover #A78BFA), 44px tall, 16px radius, shadow violet-500 at 20%.
      - Icon `Plus` h-3 w-3 (12px), mr-1.5. Label **"Add Item"**. Tap opens AddPendingSheet.
- Loading variant: `Card h-48 w-full rounded-3xl animate-pulse bg-muted` (192px tall, 24px radius, pulsing).
- Tour target id: `tour-pending-card`.

### 7. Section: Behavior Analysis (InsightsSummaryCard)
- Header: Sparkles, title "Behavior Analysis", tile emerald-600 #059669.
- Body: loading → DashboardCardSkeleton; loaded → InsightsSummaryCard.
- Loading standalone variant: `h-40 w-full rounded-3xl animate-pulse bg-muted`.
- Tour target id: `tour-insights-card`.

#### InsightsSummaryCard
- Card: `overflow-hidden border-none shadow-lg bg-emerald-50/30 dark:bg-emerald-950/5 relative`.
  - Bg #ECFDF5 at 30% (light). Dark: emerald-950 at 5%.
- Watermark: absolute bottom-0 right-0, `opacity-[0.03]` (dark 5%), translate 25%/25%, `BarChart3` size 200px, color `text-emerald-900` (#064E3B) light / `text-emerald-100` (#D1FAE5) dark.
- Header: `p-3.5 sm:p-4 pb-2 border-b dark:border-white/5 relative z-10` → 14px padding (16px at sm+), 8px bottom, 1px bottom border.
  - Row: chip `p-2 bg-emerald-500/10 rounded-lg text-emerald-600 dark:text-emerald-400` → 8px padding, 8px radius, emerald-500 at 10%, icon `BarChart3` 16px, #059669 (dark #34D399).
  - Title: **"Insights"** — `text-base font-black uppercase tracking-tight` → 16px, 900, uppercase, -0.025em. Gap between chip and title 10px.
  - No right-side action in header.
- Content: `p-3.5 sm:p-4 space-y-3 relative z-10` → 14px (16px at sm+), 12px between tiles.
  - Grid: `grid grid-cols-1 gap-2.5` → single column, 10px gap.

**Tile 1: Saving Power** (always shown)
- Shell: `p-3 rounded-[1.5rem] border transition-all relative overflow-hidden group` → 12px padding, 24px radius, 1px border, all transitions.
  - Below 20%: `bg-rose-500/5 border-rose-500/10` (#F43F5E at 5%, border 10%).
  - At/above 20%: `bg-emerald-500/5 border-emerald-500/10`.
- Row: `flex items-start justify-between relative z-10`.
  - Left stack `space-y-0.5` (2px):
    - Label: **"Saving Power"** — `text-[9px] font-black uppercase tracking-widest text-muted-foreground` → 9px, 900, uppercase, 0.1em, #64748B.
    - Value line `flex items-baseline gap-2` (8px gap):
      - Value: `text-2xl font-black italic tracking-tighter` → 24px, 900, italic, -0.05em. Text "{rate, 1 decimal}%" (e.g. "18.5%").
        - Below 20%: `text-rose-600` (#E11D48). At/above 20%: `text-emerald-600` (#059669).
      - Sub-label: **"of income"** — `text-[9px] font-bold text-muted-foreground opacity-50` → 9px, 700, 50% opacity.
  - Icon chip: `p-2 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform` → 8px padding, 12px radius, shadow-lg, scales 110% on hover.
    - Below 20%: `bg-rose-500 text-white shadow-rose-500/20`.
    - At/above 20%: `bg-emerald-500 text-white shadow-emerald-500/20`.
    - Icon: `PiggyBank` size 18px.
- Math: (net savings this month: contributions minus withdrawals, from savings ledger) / (income this month) × 100. 0 if no income.
- Conditional: below 20% → rose (warning). This is the only "saving rate" visual state.

**Tile 2: Top Spending** (shown only when there is at least one expense category this month)
- Shell: `p-3 rounded-[1.5rem] border transition-all relative overflow-hidden group` → same as Tile 1.
  - If danger level is High: `bg-rose-500/5 border-rose-500/10`.
  - Otherwise: `bg-blue-500/5 border-blue-500/10` (even for Healthy and Moderate).
- Row: `flex items-start justify-between relative z-10`.
  - Left (`space-y-1 flex-1`):
    - Label row `flex items-center gap-1.5` (6px):
      - Label: **"Top Spending"** — `text-[9px] font-black uppercase tracking-widest text-muted-foreground`.
      - Risk badge: `text-[7px] font-black uppercase px-1.5 py-0 h-3.5 rounded-md border-none text-white` → 7px text (very small), 900, uppercase, 6px sides, 0 vertical, height 14px, 6px radius, no border, white text, background per level.
        - High Risk: category share of INCOME ≥ 30% → bg `bg-rose-500` (#F43F5E).
        - Moderate: ≥ 15% → bg `bg-amber-500` (#F59E0B).
        - Healthy: < 15% → bg `bg-emerald-500` (#10B981).
        - Labels: **"High Risk"**, **"Moderate"**, **"Healthy"**.
    - Name block `space-y-0.5`:
      - Category name: `text-lg font-black tracking-tighter leading-tight` → 18px, 900, -0.05em, lh 1.25. Color per level:
        - High Risk: `text-rose-600` (#E11D48).
        - Moderate: `text-amber-600` (#D97706).
        - Healthy: `text-emerald-600` (#059669).
        - Fallback text if no name: "Unknown".
      - Stats row `flex items-center gap-2.5` (10px):
        - Column 1: label **"of expense"** `text-[9px] font-black uppercase tracking-tighter text-muted-foreground opacity-70` (9px, 900, -0.05em, 70%), value `text-xs font-black italic` (12px, 900, italic) = share of total expense, 0 decimals + "%".
        - Divider: `w-[1px] h-5 bg-muted-foreground/20` → 1px x 20px, #64748B at 20%.
        - Column 2: label **"of income"** same style, value = share of income, 0 decimals + "%".
- Icon chip: `p-2 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform shrink-0 text-white shadow-black/5` → 8px padding, 12px radius, bg per level (rose-500 / amber-500 / emerald-500), `ShoppingCart` size 18px white.

Summary of level colors:

| Level | Tile bg | Tile border | Badge bg | Name color | Chip bg |
|---|---|---|---|---|---|
| High Risk | rose-500 @5% | rose-500 @10% | rose-500 | rose-600 #E11D48 | rose-500 #F43F5E |
| Moderate | blue-500 @5% | blue-500 @10% | amber-500 #F59E0B | amber-600 #D97706 | amber-500 #F59E0B |
| Healthy | blue-500 @5% | blue-500 @10% | emerald-500 #10B981 | emerald-600 #059669 | emerald-500 #10B981 |

Note: Tile 2 background is blue for Moderate/Healthy, even though the badge is amber/emerald. Possible mismatch by design; keep as-is.

**Footer CTA**
- Link: `block pt-0.5` (2px top) to `/insights`.
- Button: `variant="outline" w-full rounded-xl border-emerald-200 dark:border-emerald-800 font-black text-[10px] uppercase tracking-widest h-10 hover:bg-emerald-100 transition-colors`.
  - 40px tall, 12px radius, full width, border #A7F3D0 (dark #065F46), 10px black uppercase, tracking 0.1em, hover bg #D1FAE5.
  - Label: **"Deep Dive Analysis"** + `ArrowRight` h-3 w-3 (12px), `ml-1.5` (6px).

### 8. Section: Recurring Costs (RecurringCostCard)
- Header: Zap, title "Recurring Costs", tile pink-600 #DB2777.
- Body: `Skeleton h-40 w-full rounded-3xl` while loading (160px, 24px radius). Loaded card below.
- Tour target id: `tour-subscriptions-card` (on section wrapper).

#### RecurringCostCard
- Card: `overflow-hidden border-none shadow-lg bg-gradient-to-br from-slate-800 to-zinc-950 text-white relative`.
  - Gradient #1E293B → #09090B (top-left to bottom-right).
- Watermark: absolute bottom-0 right-0, `opacity-[0.03]` (3%), translate 25%/25%, `Repeat` size 180px, white.
- Header: `p-3.5 sm:p-4 pb-2 border-b border-white/5 relative z-10` → 14px (16px at sm+), 8px bottom, 1px divider white 5%.
  - Row `flex items-center justify-between`:
    - Left group `flex items-center gap-2.5` (10px):
      - Chip: `p-2 bg-rose-500/20 rounded-lg` → 8px padding, 8px radius, #F43F5E at 20%. Icon `Repeat` size 16px, `text-rose-300` (#FDA4AF).
      - Title: **"Recurring Costs"** — `text-base font-black uppercase tracking-tight` → 16px, 900, uppercase, -0.025em, white.
    - Right: `Link` to `/subscriptions` wrapping `Button variant="ghost" size="icon"` overridden `h-7 w-7 rounded-full hover:bg-white/10` → 28px circle, hover white 10%. Icon `ArrowRight` size 16px.
- Content: `p-3.5 sm:p-4 space-y-4 relative z-10` → 14px (16px sm+), 16px gaps.
  - Hero block `text-center py-1 space-y-0.5` → centered, 4px vertical padding, 2px gap.
    - Label: **"Monthly Commitment"** — `text-[9px] font-black uppercase tracking-[0.2em] text-white/60` → 9px, 900, uppercase, 0.2em tracking, white 60%.
    - Value: `text-3xl font-black tracking-tighter text-white` → 30px, 900, -0.05em, white. "₹" + count-up integer (sum of active subscription amounts).
  - Two tiles `grid grid-cols-2 gap-3` (12px gap):
    - Each tile: `p-3 rounded-2xl bg-white/5 border border-white/10 flex flex-col items-center space-y-0.5` → 12px padding, 16px radius, white 5% fill, 1px white 10% border, centered column, 2px gap.
    - Tile 1 label: **"Annual Impact"** — `text-[9px] font-black text-white/50 uppercase tracking-wider` → 9px, 900, 50% white, uppercase, 0.05em.
      - Value: `text-base font-black text-white` → 16px, 900. "₹" + count-up (monthly total × 12), integer.
    - Tile 2 label: **"Income Load"** (same label style).
      - Value: `text-base font-black` → 16px, 900. Shows percentage with 1 decimal ("12.3%").
        - Normal: `text-emerald-400` (#34D399).
        - High (> 10%): `text-amber-400` (#FBBF24).
      - Percent = monthly subscription total / this month's income × 100. 0 if no income.
  - Alert strip: `p-3 rounded-xl text-xs font-medium flex items-start gap-2.5 border backdrop-blur-sm` → 12px padding, 12px radius, 12px text, 500 weight, 10px gap, 1px border, blur 4px, top-aligned.
    - Normal (≤ 10%): `bg-slate-500/20 text-slate-100 border-white/10`.
      - Icon: `Info` 16px (`h-4 w-4 shrink-0 text-slate-300`).
      - Copy: **"Your subscription load is within a healthy range. These are automated charges that occur regardless of your daily habits."**
    - High (> 10%): `bg-amber-500/10 text-amber-100 border-amber-500/20`.
      - Icon: `AlertTriangle` 16px, `text-amber-400`.
      - Copy: **"Warning: Recurring bills consume a heavy portion of your income. Evaluate your active subscriptions to free up cash."**
    - Text paragraph: `leading-relaxed` (1.625).

Visual states summary (this card):
- Income Load value: emerald-400 (≤10%) vs amber-400 (>10%).
- Alert strip: slate neutral vs amber warning.

---

## Motion & Haptics

### Framer-motion
- Not used in any of the listed files. All motion is CSS (Tailwind + tailwindcss-animate) or rAF. Do not spec framer-motion variants from this scope.

### Tailwind / tailwindcss-animate motion inventory

| Where | Class | Duration | Easing | Effect |
|---|---|---|---|---|
| Sheet panel open | slide-in-from-bottom (or left/right/top) + animate-in | 500ms | ease-in-out | slide in |
| Sheet panel close | slide-out-to-bottom + animate-out | 300ms | ease-in-out | slide out |
| Sheet / drawer overlay | fade-in-0 / fade-out-0 | tailwindcss-animate default (~150ms, not verified) | default | fade |
| Drawer | vaul default | vaul default | vaul spring | drag, scale background |
| Offline banner | animate-in slide-in-from-top-full duration-300 | 300ms | default ease | slides from top |
| Loading screen | animate-in fade-in duration-300 | 300ms | default | fade in |
| EmptyState | animate-in fade-in zoom-in-95 duration-300 | 300ms | default | fade + scale 95% → 100% |
| Monthly Story section | animate-in fade-in slide-in-from-bottom-4 duration-700 | 700ms | default | fade + 16px rise |
| Summary card month change | animate-pulse (on isMonthChanged) | 800ms total | default | pulse opacity |
| Pulsing placeholders | animate-pulse | 2s | cubic-bezier(0.4,0,0.6,1) infinite | opacity 1 → 0.5 |
| Spinners | animate-spin | 1s | linear infinite | 360° rotate |
| Pulse text ("Loading FiNN...") | animate-pulse | 2s | cubic-bezier(0.4,0,0.6,1) infinite | opacity pulse |
| Toast body | transition-all duration-300 | 300ms | default | (on mount: Sonner default slide) |
| Card hover shadow | transition-all duration-300 hover:shadow-xl | 300ms | default | shadow grows |
| Button colors | transition-colors | Tailwind default 150ms | cubic-bezier(0.4,0,0.2,1) | color change |
| Nav link color | transition-colors duration-200 | 200ms | default | color |
| Nav and summary press | active:scale-95 | Tailwind default transform 150ms | default | 95% while pressed |
| Timeline press | active:scale-[0.98] transition-all | 150ms default | default | 98% while pressed |
| Icon chips on hover | group-hover:scale-110 transition-transform | 150ms default | default | scale 110% |
| Timeline arrow | group-hover:translate-x-1 transition-transform | 150ms default | default | 4px right shift |
| Balance card hover | hover:shadow-xl transition-all duration-300 | 300ms | default | shadow |
| FAB show/hide | transition-all duration-300 translate-y-32 opacity-0 ↔ translate-y-0 opacity-100 | 300ms | default | slide 128px down + fade |
| FAB hover (visible) | hover:scale-105 | 150ms default | default | 105% |
| AnimatedCounter | requestAnimationFrame | 500ms default | cubic ease-out (1 - (1-t)^3) | count-up |
| Dashboard Monthly Story | section fade | 700ms | default | fade and rise |
| Scrollbar | none | - | - | hidden (.no-scrollbar) |
| Tour | react-joyride defaults | Joyride default | Joyride default | spotlight tooltip |

Note: "default" Tailwind transition = 150ms, cubic-bezier(0.4, 0, 0.2, 1) for `transition-*` utilities without a duration class.

### Interactions

| Element | Gesture | Feedback |
|---|---|---|
| Bottom nav item | tap | navigates (replace), haptic selection (2ms), press scale 95%, color change 200ms |
| FAB | tap | haptic medium (10ms), opens Add Transaction bottom sheet |
| FAB | scroll down / up | hides (slides down 128px, fades) on scroll down; reappears on scroll up |
| Help button (top right) | tap | dispatches start-tour, opens react-joyride guided tour for current route |
| Balance card | none (no link) | hover shadow only |
| Income / Expense cards | tap | navigates to /history with month and type query; press scale 95% |
| Income / Expense month chevrons | tap | changes month, no navigation (preventDefault) |
| Monthly Story card | tap | navigates /timeline; press scale 98%; arrow chip shifts right on hover |
| Attention alert rows | tap | navigates to item link; hover background tint |
| Attention onboarding "Setup Now" | tap | navigates /goals |
| Pending "View All" | tap | navigates /pending-transactions |
| Pending "Add Item" | tap | opens AddPendingSheet |
| Insights "Deep Dive Analysis" | tap | navigates /insights |
| Recurring Costs arrow | tap | navigates /subscriptions |
| Fresh user "Record First Transaction" | tap | haptic medium, opens AddTransactionSheet |
| PWA "Update Now" | tap | activates new service worker |
| Offline banner | none (display only) | appears on offline, instant removal online |
| Toasts | auto-dismiss (3000 to 4000ms) or manual (loading and PWA: Infinity) | haptic per type |
| Bottom sheet | drag/tap outside/close X/back button | closes; close X at top right |
| Drawer (vaul) | swipe down | dismiss, background scales |
| Back button (device) | press | blur focused input first; otherwise close top sheet |
| Long press | none in listed files | - |
| Swipe (horizontal) | none in listed files | - |
| Pull to refresh | none in listed files | - |

### Haptic events (triggerHaptic) in listed scope

| Event | Haptic | Pattern |
|---|---|---|
| Nav tab tap | selection | 2ms |
| FAB tap | medium | 10ms |
| Fresh-user CTA | medium | 10ms |
| showSuccess | success | [10, 30, 10] |
| showError | error | [50, 50, 50] |
| showWarning | warning | [30, 50, 10] |
| showInfo | light | 5ms |
| showLoading | light | 5ms |

Haptics are Android-only in practice. iOS Safari does not implement navigator.vibrate.

### Visual state summary (conditional colors)

| Element | Condition | Visual |
|---|---|---|
| Nav item | active route | text #0F172A (light) |
| Nav item | inactive | text #64748B |
| Offline banner | navigator offline | red #EF4444 bar, white text |
| Balance loading | isLoading | blue-800 → indigo-950 gradient, spinner |
| Income/Expense cards | month changed | pulse 800ms |
| Monthly Story section | day >= 25 | visible, else hidden |
| Attention card | onboarding (no emergency fund target) | indigo left border, "Priority #1" |
| Attention card | no alerts | green left border, "Health: Optimized" |
| Attention card | any critical | red left border and bar, red badge |
| Attention card | only warnings | amber left border and bar, secondary badge |
| Pending card "Oldest" pill | oldest > 14 days | amber pill, warning icon |
| Pending "To Pay" value | always | rose-300 |
| Pending "To Receive" value | always | emerald-300 |
| Saving Power | < 20% | rose tile, rose value, rose chip |
| Saving Power | >= 20% | emerald tile, emerald value, emerald chip |
| Top Spending | High Risk (>= 30% of income) | rose tile, rose badge, rose name, rose chip |
| Top Spending | Moderate (>= 15%) | blue tile, amber badge, amber name, amber chip |
| Top Spending | Healthy | blue tile, emerald badge, emerald name, emerald chip |
| Top Spending | no expense this month | tile hidden |
| Income Load | > 10% | amber-400 value, amber alert strip |
| Income Load | <= 10% | emerald-400 value, neutral slate alert strip |
| Toast | success / error / warning / info / loading | emerald / rose / amber / blue / zinc palettes |
| Dashboard | fresh user (no transactions or pending) | single welcome card, sections hidden |
| Dashboard | loading | section skeletons |

### Notes and gotchas for the Flutter port
1. Dashboard FAB `fixed` is viewport-anchored. Put it at right 20px and bottom 96px from the screen edge, not the 448px column.
2. Nav active dark mode color resolves to #0F172A (same as dark background). Likely a bug. Verify in the app before copying.
3. Pending card count text has no space: "3Active".
4. Badge in Top Spending uses 7px text. Tiny. Keep if pixel-close.
5. The `tour-insights-card` id is duplicated on the Insights card and its wrapper. Not visual.
6. DashboardCardSkeleton ignores the `height` prop.
7. Blur effects (`backdrop-blur-*`) are on small chips and pills: 4px (sm), 12px (md), backdrop-blur-md on Income/Expense chips and Monthly Story chip. Flutter: use BackdropFilter with ImageFilter.blur(sigmaX: 12, sigmaY: 12) for md; sm 4px.
8. Shadows (Tailwind): shadow-sm = 0 1px 2px rgba(0,0,0,0.05); shadow-md = 0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -2px rgba(0,0,0,0.1); shadow-lg = 0 10px 15px -3px rgba(0,0,0,0.1), 0 4px 6px -4px rgba(0,0,0,0.1); shadow-xl = 0 20px 25px -5px rgba(0,0,0,0.1), 0 8px 10px -6px rgba(0,0,0,0.1); shadow-2xl = 0 25px 50px -12px rgba(0,0,0,0.25). Colored shadows (shadow-blue-500/20 etc.) are same offsets with that color at the stated alpha.
9. Icons are lucide-react. Names listed above. Stroke width default 2 (lucide default), except toast icons 2.5.
10. Copy with emoji: suggestion line prefix "💡".
11. Currency: ₹ prefix, whole rupees on the dashboard; percentages with 0 or 1 decimal as listed.
12. Dates: month labels "MMM yy" (e.g., "OCT 26"), full month names via date-fns format.
13. No empty-state illustrations for dashboard cards; empty state is Health card or fresh-user card.

---


Not verified (assumed): Skeleton primitive styling, Badge styling, Sonner default slide animation, font family, tailwindcss-animate default durations, dark-mode hex for Tailwind palette derived colors.

---


Scope: visual/UX only. Tailwind classes converted to px (Tailwind default scale: 1 unit = 4px, text sizes as listed). Where a shadcn/ui primitive (Drawer, Tabs, Select, Popover, Calendar, AlertDialog, Badge, Card, ScrollArea, Button variants) sets styling not overridden in the call site, that default is NOT in this doc. Those primitives live in `src/components/ui/*` and were not read; treat their defaults as a gap to fill separately.

## Global conventions used below

- Type scale: `text-[8px]`=8px, `text-[9px]`=9px, `text-[10px]`=10px, `text-[11px]`=11px, `text-xs`=12px/16 lh, `text-sm`=14px/20, `text-base`=16px/24, `text-lg`=18px/28, `text-xl`=20px/28, `text-2xl`=24px/32, `text-3xl`=30px/36.
- Weights: `font-medium`=500, `font-bold`=700, `font-black`=900.
- Tracking: `tracking-tighter`=-0.05em, `tracking-tight`=-0.025em, `tracking-wider`=0.05em, `tracking-widest`=0.1em, `tracking-[0.2em]`=0.2em.
- Uppercase is applied to many labels via `uppercase`.
- Spacing: `p-1`=4, `p-1.5`=6, `p-2`=8, `p-2.5`=10, `p-3`=12, `p-4`=16, `pt-6`=24, `pb-20`=80, `pb-24`=96. `space-y-N` / `gap-N` = N*4px (`space-y-1.5`=6, `space-y-2`=8, `space-y-3`=12, `space-y-5`=20, `space-y-6`=24, `gap-2`=8, `gap-3`=12, `gap-4`=16).
- Heights: `h-14`=56, `h-12`=48, `h-11`=44, `h-10`=40, `h-8`=32, `h-7`=28, `h-6`=24, `h-3.5`=14, `h-3`=12, `h-2`=8, `h-[250px]`=250, `h-60`=240, `h-64`=256, `sm:h-80`=320, `min-h-[80px]`.
- Radius: `rounded-lg`=8, `rounded-xl`=12, `rounded-2xl`=16, `rounded-3xl`=24, `rounded-full`=9999.
- Shadows: `shadow-sm` = `0 1px 2px rgba(0,0,0,0.05)`; `shadow-md` = `0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -2px rgba(0,0,0,0.1)`; `shadow-lg` = `0 10px 15px -3px rgba(0,0,0,0.1), 0 4px 6px -4px rgba(0,0,0,0.1)`.
- Blur: `backdrop-blur-sm`=4px, `backdrop-blur-md`=12px.
- Max sheet width: `max-w-md` = 448px, content centered.
- Durations: `duration-150`=150ms, `duration-200`=200ms, `duration-300`=300ms, `duration-500`=500ms. `transition-all` with no duration = 150ms default, Tailwind ease `cubic-bezier(0.4,0,0.2,1)`.
- Animations: `animate-spin` = 1s linear infinite rotate. `animate-pulse` = 2s `cubic-bezier(0.4,0,0.6,1)` infinite, opacity 1 to 0.5 to 1. `animate-in fade-in slide-in-from-top-2` (tailwindcss-animate, default ~150ms) fade from 0 with 8px slide-down. Approximate.
- Framer-motion: NOT used in any file in this part. No framer-motion durations or easings here.
- Haptics called (types only, see `triggerHaptic`): `'selection'`, `'light'`, `'medium'`. Mapping of which interaction fires which is listed per screen below. Intensity of each type is defined in `src/lib/haptics` (not read).
- Icons: lucide-react. Names are given per use.
- Drawer sheets: bottom sheet presented by vaul-style `Drawer`. Back-button closes the sheet (hook `useSheetBackHandler`, behavior only).

---

## Add Transaction Sheet

Component: `AddTransactionSheet`. Bottom drawer. Also reachable from a global add button (not in these files).

### Container
- `DrawerContent`: height `h-[90vh]` on mobile (<768px), `md:h-[80vh]` on tablet+ (768px+). Max width 448px, centered, flex column.
- Inner wrapper: `mx-auto w-full max-w-md flex flex-col h-full overflow-hidden`.
- Body content only mounts after `open` is true; unmounts 300ms after close.

### Header (`DrawerHeader`, `text-left`, `flex-shrink-0`, relative)
- Title: **"Record Transaction"**, `text-2xl` (24px / 32 lh). Weight: primitive default (not overridden).
- Description: **"Add a new expense or income."** Default size from primitive.
- Close button: absolute, `right-4` (16px), `top-4` (16px), 32x32, variant `ghost`, size `icon`. Icon `X` lucide, `h-4 w-4` (16px). Tap closes sheet.

### Scroll area
- `ScrollArea` `flex-1 px-4` (16px side padding).
- Inner: `space-y-6` (24px between sections), `pb-6` (24px bottom).

### Section 1: Type tabs
- `Tabs` full width, `TabsList` `grid w-full grid-cols-2 h-11` (44px), `p-1` (4px padding), `rounded-xl` (12px), background `bg-muted/50` (muted color at 50% alpha).
- Triggers: **"Expense"** and **"Income"**, `rounded-lg` (8px), `font-bold` (700), `uppercase`, `tracking-widest` (0.1em), `text-[10px]`.
- Default selected: Expense. Switching sets type, which filters category list.
- Haptic: none in this sheet on tab change (Tabs onValueChange has no haptic call).

### Section 2: Category
- `space-y-2` (8px) group.
- Label: **"Category"**. Classes: `text-xs` (12px), `font-black` (900), `uppercase`, `tracking-widest` (0.1em), color `text-muted-foreground`.
- Loading state while categories load: box `h-40` (160px), flex centered, background `bg-muted/20` (muted at 20%), `rounded-xl` (12px), **dashed** border 1px (`border border-dashed`). Inside: `Loader2` icon, 20x20 (`h-5 w-5`), `animate-spin`, color `text-muted-foreground`.
- Then renders `CategorySelector` (see Category Selector section) with categories filtered to current type.
- Link below selector: text **"can't find category? don't worry you can create your own custom category click here"**. Lowercase as written. `text-[10px]` (10px), color `text-muted-foreground`, hover `text-primary`, `transition-colors`, `text-center`, `block`, `font-bold` (700), `px-4` (16px), `leading-tight`. Tap navigates to `/categories` and closes the sheet.

### Section 3: Amount (₹)
- Label: **"Amount (₹)"** (same label style as Category).
- Wrapper `relative`. Left icon: `IndianRupee` lucide, 20x20 (`h-5 w-5`), absolute `left-3` (12px), vertically centered, color `text-muted-foreground`.
- Input: `type="number"`, `step="1"`, `min="0"`, `inputMode="decimal"`, placeholder **"0"**. Classes: `pl-10` (40px left padding, clears icon), `text-xl` (20px), `h-14` (56px), `font-black` (900), `rounded-2xl` (16px). Default input border/background from primitive.
- Keyboard: `-` and `e` keys blocked (`preventDefault`).
- Value parsed as number (`valueAsNumber`).
- Validation message (under field, shown when error): **"Amount must be greater than zero."** Classes: `text-sm` (14px), `text-destructive`, `mt-1` (4px top margin).

### Section 4: Date + Mode (2-column grid)
- Grid `grid grid-cols-2 gap-4` (16px gap). Each column `space-y-2`.
- **Date** label (same label style). Trigger button: variant `outline`, `w-full`, `justify-start`, `text-left`, `font-normal`, `h-11` (44px), `rounded-xl` (12px).
  - Leading icon `CalendarIcon` 16x16 (`h-4 w-4`), `mr-2` (8px).
  - Text `text-xs` (12px), `truncate`. Format `MMM dd, yyyy` (e.g. "Oct 10, 2026"). Empty fallback **"Pick a date"**.
  - Popover content `w-auto p-0`, contains shadcn `Calendar` single-select, `initialFocus`. Tapping a day sets date and (no explicit close).
- **Mode** label. Select trigger `w-full h-11 rounded-xl`. Default value **Card**.
  - Options in order: **Cash**, **Card**, **UPI**, **Bank Transfer**.

### Section 5: Notes
- Label **"Notes"**.
- Textarea: placeholder **"Optional description..."**, `rounded-xl` (12px). Height/padding from primitive (not overridden).

### Footer (CTA)
- Wrapper: `p-4` (16px), `border-t` (1px top border), background `bg-background`, `flex-shrink-0`. Shows only when `open`-rendered.
- Button: `type="submit"`, `w-full`, `h-14` (56px), `text-lg` (18px), `font-black`, `uppercase`, `tracking-widest` (0.1em), `rounded-2xl` (16px). Default variant (primary fill).
  - Label: **"Record Expense"** when type = expense, **"Record Income"** when type = income.
  - Loading: `Loader2` 20x20, `animate-spin`, `mr-2` (8px) replaces label while saving.
  - Disabled when saving OR no category selected (`selectedCategory` null). Disabled look from primitive (opacity).

### Save feedback and validation messages (toast)
- Success toast: `Expense recorded of ₹{amount} recorded!` or `Income received of ₹{amount} recorded!` (copy as in code, including the duplicated word "recorded").
- Error toasts: **"Amount must be greater than zero."**, **"You must be logged in to record a transaction."**, **"Failed to save transaction."**
- Toast styling: `src/utils/toast` (not read).
- After success: sheet closes, form resets, selected category clears.

### Conditional states
- Category not selected: button disabled.
- Type switch changes the Category list and the CTA label.

---

## Category Selector

Component: `CategorySelector`. Used inside Add Transaction sheet.

### Layout
- Outer `space-y-3` (12px).
- Search row (if `showSearch`, default true): relative wrapper.
  - Icon `Search` 16x16 (`h-4 w-4`), absolute `left-3` (12px), vertically centered, `text-muted-foreground`.
  - `Input` placeholder **"Search categories..."**, `pl-10` (40px), `h-11` (44px), `rounded-xl` (12px), `border-2` (2px border), focus ring `focus-visible:ring-primary`.
- List container: `ScrollArea` `h-64` (256px) on mobile, `sm:h-80` (320px) at 640px+. `border` (1px), `rounded-xl` (12px), background `bg-muted/20`.
  - Inner padding `p-2` (8px), `space-y-2` (8px) between items.

### Loading / delayed render
- On mount, list shows centered block `py-12` (48px vertical) with text **"Synchronizing..."**: `text-[10px]`, `font-black`, `uppercase`, `tracking-[0.2em]`, `animate-pulse`, color `text-muted-foreground`. Renders after 50ms timeout.

### Empty state
- Block `text-center py-12` (48px), text **"No matching categories"**: `text-xs` (12px), `font-bold`, `uppercase`, `tracking-widest`, `text-muted-foreground`.

### Category item (button, full width)
- Base classes: `w-full flex items-start p-3` (12px padding), `rounded-xl` (12px), `transition-all duration-200` (200ms), `border-2` (2px), `text-left`.
- Unselected: `border-transparent`, background `bg-background/50` (50%), hover `bg-background` and `shadow-sm`.
- Selected: border `border-primary`, `ring-1` (1px) `ring-primary/20` (20% alpha), background `bg-background`, `shadow-md`.
- Tap: fires haptic `selection`, then `onSelect`.
- Icon tile: `w-10 h-10` (40x40), `rounded-xl` (12px), `mr-3` (12px), `flex-shrink-0`, `mt-0.5` (2px), `shadow-sm`, background = category color (gradient class from palette below).
  - Icon: `Icon` component, size 20, color white.
- Text column `flex-1 min-w-0`:
  - Row: name + check. Name: `font-black` (900), `text-sm` (14px), `tracking-tight` (-0.025em), `uppercase`, `truncate`.
  - Selected check: `CheckCircle` lucide, 16x16, color `text-primary`, `ml-2` (8px), `flex-shrink-0`.
  - Sub-description: `text-[10px]` (10px), `text-muted-foreground`, `leading-snug`, `font-medium` (500), `italic`, `line-clamp-1` (one line, ellipsis), `mt-0.5` (2px). Shows `subCategories` text.

### Filtering rules (behavior affects visible list)
- Only categories with non-empty `subCategories` appear.
- Search matches name or sub-categories, case-insensitive substring.
- Duplicates by name+type dropped.

### Placeholder
- `placeholder` prop default "Select a category" (not visibly rendered in this component).

---

## History Screen

Page: `History`. Bottom tab destination. Shows transaction feed plus a Transaction Details sheet.

### Page loading state
- Padding `p-4` (16px) with `pt-6` (24px top), `space-y-6` (24px).
- Title **"Transaction History"**: `text-3xl` (30px), `font-bold` (700).
- Then 8 skeleton rows (`ListSkeleton count=8`, shapes from its own file, not read).

### Page header
- Wrapper `p-4 space-y-6 pt-6 pb-20` (16px sides, 24px top, 80px bottom).
- Row `flex items-center justify-between`:
  - Title **"History"**: `text-3xl` (30px), `font-black` (900), `tracking-tighter` (-0.05em).
  - Help button: `ghost`, `icon`, `rounded-full`, 40x40 (`h-10 w-10`), color `text-muted-foreground`. Icon `HelpCircle` lucide, 24x24 (`h-6 w-6`). Tap dispatches `start-tour` window event (app walkthrough).

### Sticky filter bar (inside `TransactionList`)
- Wrapper: `sticky top-0 z-20`, background `bg-background/95` (95% alpha), `backdrop-blur-md` (12px blur), `space-y-3` (12px), `pb-2` (8px) `pt-2` (8px), bottom border `border-b` (1px).
- Month switcher row: `flex items-center justify-between bg-muted/30 p-1.5 rounded-xl border`.
  - Background `bg-muted/30` (30% alpha), padding 6px, radius 12px, border 1px.
  - Prev button: `ghost`, `sm`, `h-8 w-8` (32x32), `p-0`, `rounded-lg` (8px). Glyph **"←"** (literal character).
  - Month label: `text-[10px]`, `font-black`, `uppercase`, `tracking-[0.2em]`, color `text-primary`. Format `MMMM yyyy` (e.g. "OCTOBER 2026" via uppercase).
  - Next button: `ghost`, `icon`, `h-8 w-8` (32x32), `p-0`, `rounded-lg`. Glyph **"→"**.
  - Each tap fires haptic `selection`. Month change flashes list for 800ms (see List below).
- Filter row: `flex gap-2` (8px).
  - Search: relative `flex-1`. Icon `Search` 14x14 (`h-3.5 w-3.5`), absolute `left-3` (12px), centered vertically, `text-muted-foreground`.
    - `Input` placeholder **"Filter notes..."**, `pl-9` (36px), `h-10` (40px), `rounded-xl` (12px), `border-2` (2px), focus ring primary, `text-xs` (12px), `font-medium` (500).
  - Type select: trigger `w-[110px]` (110px), `h-10` (40px), `rounded-xl` (12px), `text-[10px]`, `font-black`, `uppercase`, `tracking-widest` (0.1em). Placeholder "All".
    - Options: **Total** (value all), **Income**, **Expense**.
    - Change fires haptic `selection`.

### List area
- Wrapper `space-y-4` (16px), `pb-20` (80px). When month changed: `animate-pulse opacity-50` (50% opacity, pulsing) for 800ms.
- Date group: `space-y-1` (4px).
  - Date header: `h3`, `text-[10px]`, `font-black`, `text-muted-foreground`, `uppercase`, `tracking-[0.2em]`, `mb-2` (8px), `px-1` (4px), `flex items-center gap-2` (8px).
    - Icon `Calendar` 12x12 (`h-3 w-3`), before text.
    - Text format `EEEE, MMM dd` e.g. "FRIDAY, OCT 10".
  - Rows: `space-y-1` (4px).
- Load more: wrapper `pt-4` (16px), centered. Button `outline`, `w-full`, `h-12` (48px), `rounded-xl` (12px), `text-[10px]`, `font-black`, `uppercase`, `tracking-[0.2em]`. Label **"Load More Entries"** + `ChevronDown` 12x12 (`h-3 w-3`), `ml-1` (4px). Page size 20. Haptic `selection`.
- Empty state: `EmptyState` with icon `ListX`, title **"Clean Slate"**, description **"No matching records found for this period."**

### Transaction row
- Container: `flex items-center justify-between py-3` (12px vertical), `px-3` (12px), `-mx-2` (-8px, bleeds to edges), `rounded-xl` (12px).
- Hover: `hover:bg-accent/30` (accent at 30%). Press: `active:scale-[0.99]` (scale to 99%). Transition `transition-all duration-200` (200ms).
- Tap: haptic `light`, opens details sheet.
- Left group: `flex items-center space-x-3` (12px gap), `min-w-0 flex-1`.
  - Icon tile: `w-9 h-9` (36x36), `rounded-xl` (12px), `shadow-sm`, centered, flex-shrink-0. Icon 16x16 (`h-4 w-4`) white.
  - Title: `font-bold` (700), `text-sm` (14px), `tracking-tight`, `leading-tight`, `truncate`, `uppercase`.
  - Subtitle (description): `text-[10px]` (10px), `text-muted-foreground`, `truncate`, `font-medium` (500), `uppercase`, `tracking-tight`, `mt-0.5` (2px).
- Right group: `text-right flex-shrink-0 ml-3` (12px left margin).
  - Amount: `font-black` (900), `text-base` (16px), `tracking-tighter` (-0.05em), `leading-none`. Prefix `+` or `-`, then `₹` and amount rounded to 0 decimals.
    - Income / inflow: `text-emerald-600` (#059669).
    - Outflow: `text-rose-600` (#e11d48).
  - Status badge: `Badge variant="outline"`, `text-[8px]` (8px), `h-3.5` (14px), `mt-1` (4px), `px-1` (4px), `py-0`, `uppercase`, `font-black`, `tracking-tighter`, `opacity-80`. Text = status or **"Done"**.

#### Icon tile per source type (icon 16px white, tile color)
| Source type | Icon (lucide) | Tile color |
|---|---|---|
| TRANSACTION | `DollarSign` | emerald-500 (#10b981) if inflow, rose-500 (#f43f5e) if outflow |
| LOAN_PAYMENT | `Scale` | orange-500 (#f97316) |
| ASSET_BUY | `Banknote` | indigo-500 (#6366f1) |
| ASSET_SELL | `Banknote` | teal-500 (#14b8a6) |
| SUBSCRIPTION | `Repeat` | purple-500 (#a855f7) |
| fallback | `DollarSign` | gray-500 (#6b7280) |

Sign rule: inflow if type income (except ASSET_SELL and some loan logic forced inflow/outflow per code); amount green/rose by inflow.

### Transaction details sheet
- `DrawerContent`: height `h-[85vh]` mobile, `md:h-[80vh]` tablet+. `w-full max-w-md mx-auto`, `outline-none`, `rounded-t-xl` (12px top corners).
- Header block `px-4 pt-4 pb-2` (16 / 16 / 8 / 16 px as listed: top 16, bottom 8).
  - Title **"Transaction Details"**: `text-lg` (18px) on mobile, `md:text-xl` (20px) tablet+, `font-black`, `uppercase`, `tracking-tight`.
  - Description **"Financial Audit Trail"**: `text-xs` (12px), `font-bold`, `text-muted-foreground`, `uppercase`, `tracking-wider` (0.05em).
  - Close: absolute `right-3` (12px), `top-3` (12px), 32x32, `ghost`, `rounded-full`, `X` 16x16.
- Body `ScrollArea` `flex-1 px-4 pb-4` (16px sides, 16 bottom). Inner `space-y-5` (20px), `pb-8` (32px).
- Summary card: `Card` `p-4` (16px), `mt-2` (8px), `border-none`, `shadow-sm`, `relative overflow-hidden`.
  - Background: inflow `bg-emerald-500/10` (10% alpha), outflow `bg-rose-500/10`.
  - Row `flex justify-between items-start gap-2`:
    - Title: `text-base` (16px) on mobile, `md:text-lg` (18px) tablet+, `font-black`, `leading-tight`, `uppercase`, `tracking-tight`, `truncate`.
    - Amount: `text-2xl` (24px), `font-black`, `tracking-tighter`. Color `text-emerald-600` inflow / `text-rose-600` outflow. Prefix `+` or `-`, then `₹` and amount rounded to 0 decimals.
  - Description under: `text-xs` (12px), `font-medium`, `text-muted-foreground`, `mt-2` (8px), `leading-snug`, `italic`. Fallback text **"No notes provided."**
- Details list: `space-y-3` (12px), `text-[11px]` (11px) mobile, `md:text-xs` (12px) tablet+, `border-t` (1px), `pt-4` (16px), `px-1` (4px). Dark mode border `dark:border-gray-800`.
  - Each row `flex justify-between`. Label: `text-muted-foreground`, `font-bold`, `uppercase`, `tracking-widest` (0.1em). Value: `font-black`.
  - Rows, in order:
    1. **"Reference Date"** value format `MMMM dd, yyyy` (e.g. "October 10, 2026").
    2. **"Audit Status"** value: `Badge` `text-[9px]`, `h-5` (20px), `font-black`, `uppercase`, `tracking-tighter`. Background `bg-emerald-500` (hover `bg-emerald-600`) when status = paid, else `bg-amber-500` (hover `bg-amber-600`). Text = status or **"Verified"**.
    3. **"Category Classification"** (only if category exists). Value `font-black`, `text-primary`. Shows category name.
    4. **"Transaction Source"**. Value `font-black`, `uppercase`. Shows source type with underscore replaced by space (e.g. "ASSET BUY", "LOAN PAYMENT"; note: `.replace('_',' ')` replaces first underscore only).

---

## Categories Screen

Page: `Categories`. Reached from Settings (back arrow goes to `/settings`).

### Loading
- Centered block `p-8` (32px), `pt-20` (80px top). Spinner `Loader2` 40x40 (`h-10 w-10`), `animate-spin`, `text-primary`. No text.

### Header
- Wrapper `p-4 space-y-6 pt-6 pb-20` (16 sides, 24 top, 80 bottom; `space-y-6` = 24px).
- Row `flex items-center space-x-4` (16px gap):
  - Back: wraps `Button variant="outline" size="icon" rounded-full` (default 40x40 icon size from primitive). Icon `ArrowLeft` 16x16 (`h-4 w-4`).
  - Title **"Categories"**: `text-3xl` (30px), `font-black`, `tracking-tighter`.

### Create button
- Full width, `h-14` (56px), `rounded-2xl` (16px), `shadow-lg`, `font-black`, `uppercase`, `tracking-widest` (0.1em), `text-xs` (12px).
- Icon `Plus` 16x16 (`h-4 w-4`), `mr-2` (8px). Label **"Create New Category"**.
- Tap: haptic `medium`, opens form sheet in create mode.

### Tabs
- `TabsList` `grid w-full grid-cols-2 h-12` (48px), `p-1.5` (6px), `rounded-2xl` (16px), `bg-muted/50`, `mb-6` (24px).
- Triggers: `rounded-xl` (12px), `font-bold`, `uppercase`, `tracking-widest`, `text-[10px]`.
  - Labels include live count: **"Expense (N)"** and **"Income (N)"**.
- Tab change haptic `selection`. Default tab: Expense.
- Tab content `mt-0 space-y-4` (16px between rows).

### Category row (card-like button)
- Container: `flex items-start justify-between p-4` (16px), `bg-muted/30` (30%), `rounded-xl` (12px), `border` (1px), hover `bg-muted/50` (50%), `transition-all` (150ms default), `cursor-pointer`, `group`.
- Tap: haptic `light`, opens edit sheet.
- Left group `flex items-start space-x-4` (16px gap), `min-w-0`:
  - Icon tile: `w-12 h-12` (48x48), `rounded-2xl` (16px), `shadow-sm`, centered, flex-shrink-0, background = category color gradient. Icon 24x24 (`size={24}`) white.
  - Text column `min-w-0`:
    - Name: `font-black` (900), `text-lg` (18px), `tracking-tight` (-0.025em), `leading-none`, `mb-1.5` (6px).
    - Row `flex items-start gap-1.5` (6px): `Info` icon 12x12 (`h-3 w-3`), `text-muted-foreground`, `mt-0.5` (2px), `shrink-0`. Text: `text-xs` (12px), `text-muted-foreground`, `leading-snug`, `italic`, `line-clamp-2` (2 lines max, ellipsis). Shows sub-categories.
- Right: `Button variant="ghost" size="icon" h-8 w-8 (32x32) rounded-full`, `group-hover:bg-background` on hover. Icon `Pencil` 16x16 (`h-4 w-4`), `text-muted-foreground`.

### Filtering (behavior)
- Only categories with non-empty `subCategories` show. Split by type into Expense and Income.

### Empty tab
- No empty-state copy in this screen. Tab content is simply blank when count is 0.

---

### Category Form Sheet (Create / Edit)
Component: `CategoryFormSheet`. Bottom drawer.

#### Container
- `DrawerContent` `h-[90vh]` mobile, `md:h-[80vh]` tablet+. `max-w-md mx-auto flex flex-col`. Inner `mx-auto w-full max-w-md flex flex-col h-full overflow-hidden`.

#### Header
- Title: **"Edit Category"** (edit mode) or **"New Category"** (create). `text-2xl` (24px), `font-black`.
- Description: **"All fields are required to maintain your financial clarity."** `text-xs` (12px), `font-medium`.
- Close: absolute `right-4` `top-4` (16px), 32x32, `ghost`, `X` 16x16.

#### Body
- `ScrollArea flex-1 px-4`. Form `space-y-6 pb-6` (24px between fields).
- Each field group `space-y-2` (8px). Label style: `text-xs` (12px), `font-black`, `uppercase`, `tracking-widest` (0.1em), `text-muted-foreground`.

1. **Type** label. `Tabs` with `TabsList` `grid w-full grid-cols-2 h-11 bg-muted/50 p-1 rounded-xl`. Triggers **"Expense"** / **"Income"**, `rounded-lg`, `text-[10px]`, `font-bold`, `uppercase`, `tracking-widest`. Default Expense.
2. **Category Name** label. `Input` placeholder **"e.g. Health, Dining, Side Hustle"**, `h-12` (48px), `rounded-xl` (12px). Error state: `border-destructive ring-destructive`.
   - Error text: **"Please enter a category name."** Classes: `text-[10px]`, `text-destructive`, `font-bold`, `uppercase`, `tracking-tight`, `flex items-center gap-1` (4px). Leading icon `AlertCircle` 12x12 (`h-3 w-3`).
3. **Sub-Categories / Items** label, with `Info` icon 12x12 after text, `gap-1.5` (6px), flex. `Textarea` placeholder **"Describe what belongs here (e.g. medicines, doctor fees, insurance)"**, `rounded-xl`, `min-h-[80px]` (80px). Error state same as above.
   - Error text: **"Please describe the sub-categories or items for this category."** Same error style.
4. **Choose Icon** label. `IconSelector` (see below). Error text: **"Please select an icon for your category."**
5. **Choose Color** label. `ColorSelector` (see below). Error text: **"Please select a color for your category."**

#### Footer
- `p-4` (16px), `border-t` (1px), `bg-background`, `flex-shrink-0`.
- Row `flex gap-4` (16px gap).
  - Primary button: `flex-1`, `h-14` (56px), `text-sm` (14px), `font-black`, `uppercase`, `tracking-widest`, `rounded-2xl` (16px). Icon `Save` 20x20 (`h-5 w-5`), `mr-2`. Label **"Save Category"** (create) or **"Update Category"** (edit). Loading: `Loader2` 20x20 spinning replaces label. Disabled while submitting.
  - Delete (edit mode only): `variant="destructive"`, `size="icon"`, 56x56 (`h-14 w-14`), `rounded-2xl`. Icon `Trash2` 20x20.
    - Confirm dialog: `rounded-3xl` (24px), no border. Title **"Delete Category?"**. Cancel: **"Cancel"** (`rounded-xl`, `bg-muted`, `font-bold`, no border). Confirm: **"Delete"** (`bg-destructive`, hover `bg-destructive/90`, `rounded-xl`, `font-bold`).

#### Toasts
- Create success: **"Category created!"**. Update: **"Category updated!"**. Delete: **"Category deleted."**.
- Errors: server message or **"Failed to save category."**; delete failure **"Failed to delete."**

### Icon Selector (in form)
- Trigger: `Button variant="outline"` `w-full justify-start`. Shows currently selected icon `Icon` 16x16 (`h-4 w-4`) `mr-2` (8px), then the icon name as text (e.g. "Utensils"). Empty when none selected.
- Popover `w-[250px]` (250px) `p-2` (8px).
  - Search: `Input` placeholder **"Search icons..."**, `mb-2` (8px).
  - Grid: `ScrollArea h-60` (240px). Inner `grid grid-cols-4 gap-1 p-1` (4 columns, 4px gap, 4px pad).
  - Each cell: `Button variant="ghost" size="icon"` (primitive size, ~40x40), icon size 20. Selected: `bg-accent`.
  - Tap: selects icon, closes popover, clears search.
- Icon names shown in picker (18, in this order):
  `Utensils`, `ShoppingBag`, `Home`, `Car`, `Heart`, `PiggyBank`, `DollarSign`, `Briefcase`, `Scale`, `Zap`, `Target`, `Users`, `CreditCard`, `Receipt`, `Wallet`, `Calendar`, `Tag`, `Lightbulb`.
  - NOTE: `CreditCard` and `Receipt` are NOT in `icon-map`, so they render the fallback `Wallet` icon. Icon name stored still "CreditCard"/"Receipt".
- Search filters names by substring, case-insensitive. Filter is on name strings (no human labels).

### Color Selector (in form)
- `flex flex-wrap gap-2` (8px).
- Swatch: `w-8 h-8` (32x32), `rounded-full`, `border-2` (2px). Fill is gradient `bg-gradient-to-r` (left-to-right). Unselected border `border-transparent`, hover `ring-1` (1px) `ring-muted-foreground`. Selected: `border-primary`, `ring-2` (2px) `ring-offset-2` (2px offset) `ring-primary/50` (50% alpha).
- Transition `transition-all duration-150` (150ms).
- No label text inside; swatches only, no names shown.

#### Color palette (14 options, in order)
Gradient = `from` to `to`, Tailwind v3 default hex values.

| # | Class | From (hex) | To (hex) |
|---|---|---|---|
| 1 | `from-blue-500 to-cyan-500` | blue-500 #3b82f6 | cyan-500 #06b6d4 |
| 2 | `from-purple-500 to-pink-500` | purple-500 #a855f7 | pink-500 #ec4899 |
| 3 | `from-green-500 to-teal-500` | green-500 #22c55e | teal-500 #14b8a6 |
| 4 | `from-yellow-500 to-orange-500` | yellow-500 #eab308 | orange-500 #f97316 |
| 5 | `from-red-500 to-pink-500` | red-500 #ef4444 | pink-500 #ec4899 |
| 6 | `from-indigo-500 to-purple-500` | indigo-500 #6366f1 | purple-500 #a855f7 |
| 7 | `from-gray-500 to-gray-700` | gray-500 #6b7280 | gray-700 #374151 |
| 8 | `from-lime-500 to-green-500` | lime-500 #84cc16 | green-500 #22c55e |
| 9 | `from-fuchsia-500 to-pink-500` | fuchsia-500 #d946ef | pink-500 #ec4899 |
| 10 | `from-sky-500 to-indigo-500` | sky-500 #0ea5e9 | indigo-500 #6366f1 |
| 11 | `from-amber-500 to-red-500` | amber-500 #f59e0b | red-500 #ef4444 |
| 12 | `from-emerald-500 to-blue-500` | emerald-500 #10b981 | blue-500 #3b82f6 |
| 13 | `from-rose-500 to-orange-500` | rose-500 #f43f5e | orange-500 #f97316 |
| 14 | `from-violet-500 to-fuchsia-500` | violet-500 #8b5cf6 | fuchsia-500 #d946ef |

Note: Category color value is the full class string; the same gradient classes render the category tile in every list (Add Transaction, Categories, Subscriptions).

---

## Subscriptions Screen

Page: `Subscriptions` (route title "Recurring Costs"). Accent color is **pink**.

### Loading
- Block `p-8` (32px), `pt-20` (80px top), centered. Spinner `Loader2` 40x40, `animate-spin`, `text-primary`. Below: **"LOADING..."** `mt-4` (16px), `text-muted-foreground`, `font-bold`.

### Error state
- `p-4 space-y-4 pt-6 text-center`. Title **"Recurring Costs"** `text-xl` (20px), `font-black`.
- Error box: `text-destructive py-6` (24px vertical), `bg-destructive/5` (5% alpha), `rounded-xl` (12px), `border border-destructive/20` (20% alpha). Text **"Failed to load."** `font-bold`.

### Page wrapper
- `p-2` (8px), `space-y-4` (16px), `pt-3` (12px), `pb-24` (96px bottom).

### Header
- Row `flex items-center justify-between pt-1 px-1` (4px top, 4px sides).
- Title **"Recurring Costs"**: `text-xl` (20px), `font-black`, `tracking-tighter` (-0.05em).
- Help button: `ghost`, `icon`, `rounded-full`, 40x40, `text-muted-foreground`, `HelpCircle` 24x24. Dispatches `start-tour`.

### Monthly Load hero card
- `Card` `overflow-hidden border-none shadow-lg` (shadow-lg), background gradient `bg-gradient-to-br` (top-left to bottom-right) from **pink-700 #be185d** to **rose-950 #4c0519**. Text `text-white`. `relative`.
- Decorative watermark: absolute `bottom-0 right-0`, `opacity-[0.05]` (5%), `pointer-events-none`, `translate-x-1/4 translate-y-1/4` (25% of element size offset). Icon `Zap` size 120 (120x120 px), white.
- Header `CardHeader` `p-3` (12px), `pb-1.5` (6px), `relative z-10`, bottom border `border-b border-white/5` (5% white).
  - Row `flex justify-between items-center`.
  - Left: label **"Monthly Load"**, `text-[8px]` (8px), `font-black`, `uppercase`, `tracking-[0.2em]`, `opacity-80`. Under it value: `h2` `text-2xl` (24px), `font-black`, `tracking-tighter`. Value = total of ACTIVE subscriptions (monthly cost, animated counter), prefix **₹**, 0 decimals.
  - Right: icon tile `p-1.5` (6px), `bg-white/10` (10%), `rounded-lg` (8px), `backdrop-blur-sm` (4px blur). Icon `Zap` 16x16 (`h-4 w-4`), color `text-pink-200` (#fbcfe8).
- Content `CardContent` `p-3` (12px), `relative z-10`, `space-y-3` (12px).
  - Row `flex justify-between items-center text-[9px] font-bold uppercase tracking-wider` (0.05em), `opacity-70`. Left **"Annual Projection"**; right `₹{annual}/yr`, annual = monthly x 12, formatted with thousands separator, 0 decimals.
  - Income Impact meter (shown only when monthly income > 0):
    - Wrapper `space-y-1.5` (6px), `pt-1` (4px).
    - Top row `flex justify-between items-end`:
      - Left `flex items-center gap-1.5` (6px): icon `PieChart` 12x12 (`h-3 w-3`), colored by level. Label **"Income Impact"**, `text-[9px]`, `font-black`, `uppercase`, `tracking-tight`, `opacity-90`.
      - Right: level badge `text-[9px]`, `font-black`, `uppercase`, `px-1.5` (6px), `py-0.5` (2px), `rounded-full`, `bg-white/10`. Text = level label. Colored by level.
    - Bar: `h-2` (8px), `bg-black/20` (20% black), `rounded-full`, `overflow-hidden`, `backdrop-blur-sm`, `ring-1` (1px) `ring-white/5`.
      - Fill: `h-full rounded-full`, `transition-all duration-500` (500ms), width = min(percentage, 100)%. Fill color by level.
    - Bottom row `flex justify-between text-[8px] font-medium opacity-70 leading-tight`:
      - Left: **"Consumes {x.x}% of income"** (1 decimal).
      - Right `opacity-60`: level description.

#### Income Impact levels (percentage = monthly cost / monthly income x 100)
| Range | Label | Fill | Text color | Description |
|---|---|---|---|---|
| > 40% | Critical | red-500 #ef4444 | red-300 #fca5a5 | "Costs are consuming too much income." |
| > 25% to 40% | High | orange-400 #fb923c | orange-300 #fdba74 | "Consider reducing fixed costs." |
| > 15% to 25% | Moderate | yellow-400 #facc15 | yellow-300 #fde047 | "Balanced, but keep an eye on it." |
| 0% to 15% (and up to ... ) | Healthy | emerald-400 #34d399 | emerald-300 #6ee7b7 | "Well within safe limits." |

- Meter hidden entirely when monthly income is 0.

### Add Recurring Cost button
- Full width, `h-10` (40px), `rounded-lg` (8px), `shadow-md`, background `bg-pink-600` (#db2777), hover `bg-pink-700` (#be185d). `font-black`, `uppercase`, `tracking-widest`, `text-[9px]`.
- Icon `Plus` 14x14 (`w-3.5 h-3.5`), `mr-1.5` (6px). Label **"Add Recurring Cost"**.

### Section header (Active Services)
- Wrapper `space-y-0.5` (2px), `mb-2` (8px), `px-1` (4px).
- Row `flex items-center gap-2` (8px):
  - Icon tile: `p-1` (4px), `rounded-lg` (8px), `shadow-sm`, background `bg-pink-500` (#ec4899). Icon `Repeat` 12x12 (`h-3 w-3`), white.
  - Title **"Active Services"**: `text-[11px]` (11px), `font-black`, `tracking-tight`, `uppercase`, `text-foreground`.
- Description (below, indented `pl-6` 24px): `text-[10px]` (10px), `font-bold`, `text-muted-foreground/70` (70% alpha), `leading-tight`. Text: **"{n} Recurring Payments."** (n = count of active subs; note the trailing period in copy).

### Subscription list
- Wrapper `space-y-1.5` (6px), `px-0.5` (2px).
- Empty state: `EmptyState` icon `ListX`, title **"No Recurring Costs"**, description **"You don't have any active subscriptions."**, className `opacity-70 bg-muted/20`.

### Subscription row (SubscriptionItem)
- `Card` `p-2.5` (10px), `transition-all duration-300` (300ms), `cursor-pointer`. Hover: `shadow-md`, `hover:border-primary/20` (20% primary border).
- Tap row: haptic `light`, opens details sheet.
- Content `CardContent p-0 flex justify-between items-center gap-2` (8px).
- Left group `flex items-center space-x-2.5` (10px), `min-w-0 flex-1`:
  - Icon tile: `w-8 h-8` (32x32), `rounded-full`, `flex-shrink-0`, background = category color (or gray-500 #6b7280 fallback). Icon `Icon` size 16, white. Icon name = category icon, fallback `Zap`.
  - Name: `font-bold` (700), `text-sm` (14px), `tracking-tight`, `leading-tight`, `truncate`.
  - Frequency row: `text-[10px]` (10px), `text-muted-foreground`, `mt-0.5` (2px). Icon `Repeat` 10x10 (`h-2.5 w-2.5`), `mr-0.5` (2px). Text = **"Monthly"** or **"Yearly"**.
- Right group `text-right flex-shrink-0 space-y-0.5` (2px):
  - Amount: `text-base` (16px), `font-black`, `text-destructive` (red), `tracking-tighter`, `leading-none`, `flex items-center justify-end`. Icon `IndianRupee` 12x12 (`h-3 w-3`), `mr-0.5` (2px) before amount. Amount formatted with thousands separators (no ₹ glyph; rupee is the icon).
  - Reminder row: `flex items-center justify-end space-x-1.5` (6px):
    - Text `text-[10px]`, `font-bold`, `flex items-center`. Color `text-destructive` when urgent or overdue, else `text-muted-foreground`.
      - Bell: `Bell` 10x10 (`h-2.5 w-2.5`), `mr-0.5`, `animate-pulse`. Shown only when urgent (<=7 days, >=0) or overdue.
    - Text rules:
      - Overdue (<0 days): **"Overdue"**
      - Due today: **"Today"**
      - 1 to 7 days: **"{n}d left"**
      - More than 7 days: date `MMM dd` (e.g. "OCT 17" style via format "MMM dd")
  - Edit button: `ghost`, `icon`, `h-6 w-6` (24x24), `rounded-full`, hover `bg-muted`. Icon `Pencil` 12x12 (`h-3 w-3`), `text-muted-foreground`. Tap: stops propagation, haptic `light`, opens management sheet.
  - Pay row `flex justify-end mt-0.5` (2px):
    - Button `size="sm"`, `h-7` (28px), `text-[10px]`, `font-bold`, `px-2` (8px), `py-0`.
    - Variant `default` (pink primary fill) when payment due (overdue or due today) = label **"Pay"**. Variant `outline` otherwise = label **"Pending"**, disabled.
    - Disabled also while any payment processing.
    - Tap: stops propagation, haptic `medium` only when due.

### Subscription details sheet (opened from row tap)
- `Sheet` right-side/side panel. `SheetContent` `sm:max-w-md` (448px at 640px+), `p-4` (16px), `pt-10` (40px top).
- Header `text-left`:
  - Row `flex items-center gap-2` (8px), `mb-1` (4px):
    - Icon circle: `w-8 h-8` (32x32) `rounded-full`, background category color (or gray-500). Icon `CreditCard` 16x16 white (fixed icon, not category icon).
    - Title: subscription name, `text-lg` (18px), `font-bold`, `leading-tight`.
    - Description row `flex items-center gap-1`: Badge `outline`, `text-[9px]`, `h-4` (16px), `px-1` (4px), `leading-none`, `uppercase`, `tracking-wider`. Text = category name or **"Other"**.
- Body `mt-4` (16px), `space-y-4` (16px).
  - Stats grid `grid grid-cols-2 gap-2` (8px):
    - Card `bg-muted/40` (40%), `p-2` (8px), `rounded-lg` (8px), `border` (1px).
      - Label row: `text-[9px]`, `text-muted-foreground`, `uppercase`, `font-bold`, `tracking-tight`, `mb-0.5` (2px), `flex items-center gap-1` (4px). Icon `IndianRupee` 10x10 (`h-2.5 w-2.5`). Text **"Amount"**.
      - Value: `text-base` (16px), `font-black`, `tracking-tight`. Format `₹{amount with thousands separator}`.
    - Card: label with icon `Repeat` 10x10, text **"Frequency"**. Value = "Monthly" or "Yearly", same style.
  - Next due box: `bg-blue-50/50` (light) / `dark:bg-blue-900/10`, `p-3` (12px), `rounded-lg` (8px), `border` (1px), border `border-blue-100` / `dark:border-blue-900/30`.
    - Row `flex items-center justify-between mb-1` (4px):
      - Left: `text-[10px]`, `font-bold`, `text-blue-700` (dark `text-blue-400`), `flex items-center gap-1` (4px). Icon `Calendar` 12x12 (`h-3 w-3`). Text **"Next Due"**.
      - Right: `text-xs` (12px), `font-black`, `text-blue-900` (dark `text-blue-200`). Format `MMM dd, yyyy`.
  - `Separator` (1px line).
  - History section `space-y-3` (12px):
    - Header row `flex items-center justify-between`: title `h3` `text-xs` (12px), `font-bold`, `flex items-center gap-1.5` (6px). Icon `History` 14x14 (`h-3.5 w-3.5`) color `text-indigo-500` (#6366f1). Text **"History"**. Count badge `secondary`, `text-[9px]`, `h-4` (16px), `px-1.5` (6px). Shows number of payments.
    - Scroll area `h-[250px]` (250px), `pr-2` (8px).
      - Loading: 3 skeleton bars `h-10` (40px) `w-full` `rounded-lg` (8px), stacked `space-y-2` (8px).
      - Rows `space-y-2` (8px). Each row `flex items-center justify-between p-2` (8px), `rounded-lg` (8px), `border` (1px), `bg-card/50` (50%).
        - Left `flex items-center gap-2` (8px):
          - Icon circle: `bg-green-100` (dark `bg-green-900/20`), `p-1.5` (6px), `rounded-full`. Icon `Clock` 12x12 (`h-3 w-3`), `text-green-600` (#16a34a).
          - Date: `text-[10px]`, `font-bold`, format `MMM dd, yyyy`. Below: **"Successful"** `text-[8px]`, `text-muted-foreground`.
        - Amount: `text-xs` (12px), `font-black`, `tracking-tight`. `₹{amount with thousands separator}`.
      - Empty: block `text-center py-6` (24px). Icon `Clock` 24x24 (`h-6 w-6`), `text-muted-foreground/20` (20%), `mb-1` (4px), centered. Text **"Empty"**: `text-[10px]`, `text-muted-foreground`, `uppercase`, `font-bold`, `tracking-widest`.

### Add Subscription sheet
Component: `AddSubscriptionSheet`. Bottom drawer.

#### Container
- `DrawerContent` `h-[85vh]` mobile, `md:h-[75vh]` tablet+, `max-w-md mx-auto flex flex-col`.

#### Header (`p-4`)
- Title **"Add Subscription"**: `text-xl` (20px), `font-black`.
- Description **"Record new or existing recurring costs."**: `text-xs` (12px).
- Close: absolute `right-4` `top-4` (16px), 32x32, `ghost`, `X` 16x16.

#### Body
- `ScrollArea flex-1 px-4`. Form `space-y-5` (20px), `pb-6`.
- Field label style: `text-[10px]`, `font-black`, `uppercase`, `tracking-widest` (0.1em), `text-muted-foreground`, `ml-1` (4px). Field group `space-y-1.5` (6px).

1. **Service Name** label. `Input` placeholder **"e.g., Netflix, Spotify"**, `h-10` (40px), `rounded-xl` (12px). Validation error: **"Name is required."** (defined in schema; rendered text not shown in this form).
2. **Amount (₹)** label. Wrapper relative. Icon `IndianRupee` 14x14 (`h-3.5 w-3.5`), absolute `left-3` (12px). Input `type=number`, `step=0.01`, `min=0`, `inputMode=decimal`, `pl-9` (36px), `h-10` (40px), `rounded-xl`, `font-bold` (700). `-` and `e` keys blocked. Validation copy: **"Amount must be positive."** (schema, and submit-time toast).
3. Two columns `grid grid-cols-2 gap-3` (12px):
   - **Frequency** label. Select trigger `h-10` (40px), `rounded-xl`. Options: **Monthly**, **Yearly**. Default Monthly.
   - **Original Start Date** label. Button `variant="outline"`, `w-full h-10` (40px), `justify-start`, `text-left`, `font-normal`, `rounded-xl`. Icon `CalendarIcon` 14x14 (`h-3.5 w-3.5`), `mr-2` (8px). Text `text-xs` (12px) `truncate`, format `MMM dd, yyyy`, fallback **"Pick date"**. Popover `w-auto p-0`, `align="start"`, shadcn `Calendar` single, `initialFocus`.

#### Historical auto-import notice (conditional: start date in past, count > 0)
- Box `bg-amber-50/50` (light) / `dark:bg-amber-900/10`, `p-3` (12px), `rounded-xl` (12px), border `border-amber-100` / `dark:border-amber-900/30`. Animation `animate-in fade-in slide-in-from-top-2` (fade + 8px slide-down).
- Header row `flex items-center gap-2` (8px), `mb-2` (8px):
  - Icon tile: `p-1.5` (6px), `bg-amber-500` (#f59e0b), `rounded-lg` (8px). Icon `History` 12x12 (`h-3 w-3`), white.
  - Title **"Historical Auto-Import"**: `text-[10px]`, `font-black`, `uppercase`, `tracking-widest`, `text-amber-700` (dark `text-amber-400`).
- Body paragraph: `text-xs` (12px), `text-amber-800` (dark `text-amber-200`), `leading-snug`. Text: **"Since the start date is in the past, FiNN will automatically record past payments for accurate history."**
- List `mt-2` (8px), `space-y-1` (4px):
  - Item: `text-[10px]`, `text-amber-700/80`, `flex items-center gap-1.5` (6px). Icon `CheckCircle` 12x12 (`h-3 w-3`). Text: **"Add {n} past payment records"**.
  - Item: same style. Text: **"Your balance will "** + bold **"NOT"** + **" be deducted for past history"**.

#### Same-day notice (conditional: next due date is today)
- Box `bg-blue-50/50` / `dark:bg-blue-900/10`, `p-3` (12px), `rounded-xl` (12px), border `border-blue-100` / `dark:border-blue-900/30`. Same animation.
- Text `text-xs` (12px), `text-blue-800` (dark `text-blue-200`), `leading-snug`, `font-medium` (500). Copy:
  - If start date is today: **"This starts today. Use the 'Pay' button on the dashboard to record today's cost."**
  - Else: **"A payment is due today. It will not be auto-added; please use the 'Pay' button to settle it."**

#### Footer
- `p-4` (16px), `border-t`, `bg-background`, `flex-shrink-0`.
- Button `w-full`, `h-12` (48px), `text-sm` (14px), `font-black`, `uppercase`, `tracking-widest`, `rounded-xl` (12px), `bg-pink-600` (#db2777), hover `bg-pink-700` (#be185d), `shadow-lg` + `shadow-pink-500/20` (pink-500 at 20%). Disabled while submitting.
  - Idle: `Plus` icon 16x16 (`w-4 h-4`), `mr-2` (8px), label **"Add Subscription"**.
  - Submitting: `Loader2` 20x20 spin, `mr-2`, label **"Processing..."**.

#### Toasts
- Success variants:
  - With past payments: **"Subscription added! Imported {n} past payments."**
  - Due today: **"Subscription added! Payment due today."**
  - Otherwise: **"Subscription added successfully!"**
- Error: **"Failed to add subscription."**
- Amount guard: **"Amount must be positive."**

### Edit Subscription sheet
Component: `SubscriptionManagementSheet`. Bottom drawer. Opened from pencil button.

#### Container
- `DrawerContent` `h-[85vh]` mobile, `md:h-[75vh]` tablet+, `max-w-md mx-auto flex flex-col`.

#### Header
- Title **"Edit Subscription"**: `text-2xl` (24px), primitive weight.
- Description **"Update details for your recurring expense."**
- Close: absolute `right-4` `top-4`, 32x32, ghost, `X` 16x16.

#### Body
- `ScrollArea flex-1 px-4`. Form `space-y-6` (24px), `pb-6`. Fields `space-y-2` (8px). Labels use the default Label style (not overridden): **"Name"**, **"Amount (₹)"**, **"Frequency"**.
- Name: `Input` (default height from primitive). Error text: `text-sm` (14px), `text-destructive`, copy **"Name is required."**
- Amount: icon `IndianRupee` 16x16 (`h-4 w-4`), absolute `left-3`. Input `step=0.01`, `min=0`, `pl-10` (40px), `text-lg` (18px), `h-12` (48px). `-` and `e` blocked. No inline error text rendered (error only via toast "Amount must be positive.").
- Frequency: Select, default trigger height. Options **Monthly**, **Yearly**. No start-date picker on this sheet.

#### Footer
- `p-4` (16px), `border-t`, `bg-background`, `flex-shrink-0`. Row `flex gap-4` (16px).
  - Save: `flex-1`, `h-12` (48px), `text-lg` (18px). Icon `Save` 20x20 `mr-2`, label **"Save"**. Loading: `Loader2` 20x20 spin.
  - Delete: `variant="destructive"`, `size="icon"`, `h-12 w-12` (48x48), icon `Trash2` 20x20. Disabled while submitting.
    - Confirm dialog (default AlertDialog size, not rounded override): title **"Delete Subscription?"**. Cancel **"Cancel"** (disabled while submitting). Confirm **"Delete"**, `bg-destructive`, disabled while submitting; shows `Loader2` 16x16 spinning while deleting.

#### Toasts
- Success: **"Subscription updated!"**, delete **"Subscription deleted."**
- Errors: **"Failed to update subscription."**, **"Failed to delete."**, **"Amount must be positive."**

### Behavior notes (visual-relevant)
- Subscriptions with status not ACTIVE are excluded from the list and the Monthly Load total.
- Next due date on edit is recalculated to the first future occurrence from the start date (monthly / yearly steps).
- Pay action is blocked with toast **"Insufficient balance. You have ₹{balance with 2 decimals} available."** when amount exceeds available balance; success toast **"Payment recorded!"**; failure toast **"Failed to process payment."**
- Loading overlay on Pay: all pay buttons disabled while `isProcessing`.

---


---


Visual/UX only. Tailwind classes converted to px (base 1rem = 16px). Hex values are Tailwind v3 default palette unless noted. Lucide icon names are exact.

## Global conventions (apply to all sections)

**Spacing scale (Tailwind):** 0.5=2px, 1=4px, 1.5=6px, 2=8px, 2.5=10px, 3=12px, 4=16px, 5=20px, 6=24px, 8=32px, 9=36px, 10=40px, 11=44px, 12=48px, 14=56px, 16=64px, 20=80px, 24=96px.

**Radius:** base `--radius` = 0.5rem = 8px. `rounded-md` 6px, `rounded-lg` 8px, `rounded-xl` 12px, `rounded-2xl` 16px, `rounded-[1.5rem]` 24px, `rounded-full` 9999px.

**Type scale:** text-[9px] = 9px, text-[10px] = 10px, text-xs 12px/16px lh, text-sm 14px/20px, text-base 16px/24px, text-lg 18px/28px, text-xl 20px/28px, text-2xl 24px/32px, text-3xl 30px/36px.
Weights: font-medium 500, font-semibold 600, font-bold 700, font-black 900.
Tracking: tracking-tighter -0.05em, tracking-tight -0.025em, tracking-widest 0.1em, tracking-[0.2em] 0.2em.
Uppercase is used heavily on labels, badges, buttons (`uppercase`).

**Theme tokens (shadcn, `src/globals.css`, HSL converted to hex):**

| Token | Light | Dark |
|---|---|---|
| background | #FFFFFF | #020817 |
| card | #FFFFFF | #020817 |
| primary | #0F172A (slate-900) | #F8FAFC |
| primary-foreground | #F8FAFC | #0F172A |
| secondary / muted | #F1F5F9 (slate-100) | #1E293B (slate-800) |
| muted-foreground | #64748B (slate-500) | #94A3B8 (slate-400) |
| destructive | #EF4444 (red-500) | #7F1D1D (red-900) |
| border | #E2E8F0 (slate-200) | #1E293B |

Note: `primary` is near-black in light mode. Screens that say `text-primary` or `bg-primary` render slate-900 (light) or slate-50 (dark). Screens that use explicit violet/indigo/green override it.

**Shared component defaults (shadcn):**
- Button default: h-40px (h-10), px-16px, py-8px, rounded-md 6px, text-sm 500. Sizes: sm h-36px (h-9) px-12px; icon h-40px w-40px. Variant `secondary` bg #F1F5F9. `ghost` transparent. `outline` 1px border #E2E8F0 bg white. `destructive` bg #EF4444 text white.
- Input default: h-40px, px-12px, rounded-md 6px, 1px border #E2E8F0, text-sm. Focus ring: 2px ring, offset 2px. `focus-visible:ring-violet-500` on pending search.
- Label: text-sm 500, mb 8px.
- Card: rounded-lg 8px, 1px border, bg white, shadow-sm. Most cards here override to `border-none rounded-2xl` or `rounded-[1.5rem]`.
- Badge: rounded-full, px-10px, py-2px, text-xs 600. Overrides here use `h-4 px-1` (16px high) or `h-6` (24px).
- Tabs list default: h-40px, p-4px, rounded-md, bg #F1F5F9. Trigger active: white bg, shadow-sm.
- Drawer (vaul): bottom sheet. Top corners rounded (about 10px), drag handle bar at top. Content `max-w-md` = 448px, centered (`mx-auto`). Overlay black at 80%.
- AlertDialog: centered, max-w-lg 512px, p-24px, rounded-lg 8px, overlay black 80%.
- Popover: w-auto, p-0 for calendar, shadow-md, rounded-md, 1px border.
- Calendar: 36px day cells (h-9 w-9), selected day bg primary.
- ScrollArea: vertical scroll, thin scrollbar.

**Haptics:** `triggerHaptic('light' | 'medium' | 'selection')` fires on card taps, settle, month change, tab change, add button. Map to `HapticFeedback.lightImpact()` / `mediumImpact()` / `selectionClick()` in Flutter.

**Sheet back-button:** all drawers close on Android back. Flutter: `PopScope` / `showModalBottomSheet` default.

**Currency:** INR symbol `₹`. Whole-number display for card values (`toFixed(0)`), `toLocaleString()` (Indian grouping not forced, so "1,00,000" depends on locale; the code uses default en-US grouping: "100,000"). Form inputs use 2 decimals in some places.

**Animated counter (AnimatedCounter):** count from 0 to target on mount/value change, 500ms default, ease-out-ish (rAF). Used for hero numbers. Flutter: `TweenAnimationBuilder<double>` 500ms.

**Skeleton on load:** all three screens show a header line "Goals & Budgets" (text-xl 900), a `DashboardCardSkeleton` (h-40 = 160px), and `ListSkeleton count=4`. Pending has no loading skeleton on this page.

**Empty state component (`EmptyState`, used by Goals):**
- Container: flex column, centered, py-48px (py-12), p-16px, **2px dashed** border, rounded-[1.5rem] 24px, bg `muted/10` (#F1F5F9 at 10%), entrance animation: fade in + zoom from 95% over 300ms.
- Icon circle: bg `muted` (#F1F5F9), p-16px, rounded-full, shadow-sm. Icon 32px (h-8 w-8), color muted-foreground at 70%.
- Title: text-base (16px), font-black, uppercase, tracking-tight, color foreground at 80%, mb-4px.
- Description: text-xs (12px), font-medium, muted-foreground, max-w 240px, mb-20px, line-height relaxed (1.625).
- Action button (optional): h-36px, rounded-xl 12px, font-bold, text-xs, uppercase, tracking-wider, shadow-sm, bg white, outline style.

**Section header (`SectionHeader`, used on Goals and Pending):**
- Row: flex, items-center, gap-8px. mb-16px. px-4px.
- Icon chip: p-6px (p-1.5), rounded-lg 8px, shadow-sm, colored bg, icon 14px (h-3.5 w-3.5), white.
- Title: text-sm (14px), font-black, tracking-tight, uppercase, foreground.

---

## Goals Screen

Route: Goals page. Header title "Goals & Budgets" only in skeleton state; the loaded header reads "Your **Vision**".

### Layout
- Root: `p-3` = 12px horizontal and top padding is `pt-4` (16px). `pb-20` = 80px bottom. Vertical gap between sections `space-y-6` = 24px.
- Page header row: flex, space-between, `pt-1` (4px).
  - Left: `<h1>` text-xl (20px), font-black, tracking-tighter. Text "Your " in foreground, "Vision" in `text-primary`.
  - Right: ghost icon button, 40x40px, rounded-full, icon `HelpCircle` 24px (h-6 w-6), color muted-foreground. Tap dispatches "start-tour" event (onboarding tour).
- Three sections, each a `div` with `space-y-4` (16px) and `pb-4` (16px) bottom padding, except budgets which has no `pb-4`:
  1. `#tour-emergency-fund` "Emergency Security"
  2. `#tour-savings-goals` "Savings Aspirations"
  3. `#tour-budgets` "Spending Limits"

### Section header variants
| Section | Icon | Chip color | Title |
|---|---|---|---|
| Emergency | `ShieldCheck` | `bg-primary` (slate-900 light) | Emergency Security |
| Goals | `Target` | `bg-indigo-600` #4F46E5 | Savings Aspirations |
| Budgets | `PieChart` | `bg-rose-600` #E11D48 | Spending Limits |

### Emergency Security hero card
- Card: `group relative overflow-hidden`, `border-none`, `text-white`, `rounded-2xl` (16px), hover shadow-lg, `active:scale-[0.98]`, transition-all 300ms.
- Gradient (diagonal, `bg-gradient-to-br` = to bottom-right):
  - **Critical** (coverageMonths < 2): `from-rose-600` #E11D48 to `red-950` #450A0A.
  - **Funded** (progress >= 100 and coverage >= 2): `from-emerald-600` #059669 to `teal-900` #134E4A.
  - **Default** (otherwise): `from-amber-500` #F59E0B to `orange-800` #9A3412.
- Content: `p-4` (16px), `space-y-4` (16px), `relative z-10`.
- Row 1 (flex, justify-between, items-start):
  - Left column `space-y-0.5` (2px):
    - Label: "Stability Buffer", text-[9px], font-black, uppercase, tracking-[0.2em], opacity 80%.
    - Value: `<h2>` text-2xl (24px), font-black, tracking-tighter, white. Value is `₹` + AnimatedCounter (decimals 0), e.g. "₹12,000".
  - Right: Badge, bg white at 20% (`bg-white/20`), no border, text-white, font-black, text-[9px], uppercase. Text: `{coverageMonths.toFixed(1)} MO COVER` e.g. "2.4 MO COVER".
- Row 2 (`space-y-1.5` = 6px):
  - Flex row, justify-between, text-[9px] font-black uppercase tracking-widest opacity 80%:
    - Left: `{progress.toFixed(0)}% FUNDED`
    - Right: `TARGET: ₹{target.toLocaleString()}`
  - Progress: h-10px (`h-2.5`), `bg-white/20`, rounded-full, indicator `bg-white`.
- Critical alert (only if coverageMonths < 2 AND target > 0):
  - Row, `gap-8px`, `bg-black/20` (black 20%), p-10px (`p-2.5`), rounded-xl 12px, border 1px `white/10`.
  - Icon `ShieldAlert` 14px (h-3.5 w-3.5), color rose-200 #FECDD3, mt 2px, shrink-0.
  - Text: "Critical Risk: Low Buffer", text-xs (12px), font-bold, uppercase, rose-100 #FFE4E6, leading snug.
- Tap: opens EmergencyFundSheet (wealth variant).
- Coverage formula: `fund / (target / 6)` months.

### Savings Aspirations (goals)
- Tabs (shadcn): TabsList `grid w-full grid-cols-2`, h-40px, p-4px, rounded-xl 12px, bg `muted/50` (#F1F5F9 at 50%).
  - Triggers: "Active" (default), "Completed". Text: text-[10px], font-bold, uppercase, tracking-widest, rounded-lg 8px.
  - Active trigger bg white, shadow-sm (shadcn active state).
- Tab content spacing: `space-y-2` (8px).
- Grid: 1 column, gap 8px.

**Goal card (`GoalProgressCard`), active:**
- Card: `cursor-pointer`, `border-none`, `text-white`, `relative overflow-hidden`, `shadow-lg`, hover `shadow-xl`, transition-all 300ms, `active:scale-[0.98]`, `rounded-[1.5rem]` (24px).
- Background: the goal's `progressColor` class. Gradient options come from the color picker (below).
- Inner padding `p-4` (16px), `space-y-4` (16px).
- Decorative background icon: `Goal` icon 120px, opacity 10%, positioned bottom-right, translated +25% x and y (clipped).
- Header row (flex, space-between, items-center, space-y-0):
  - Left: icon chip `p-1.5` (6px), `bg-white/20`, rounded-lg 8px, backdrop-blur-md. Icon `Goal` w-4 h-4 (16px), white. Gap 10px (`space-x-2.5`).
  - Title: text-base (16px), font-black, uppercase, tracking-tight, truncate, max-width 140px. Text = goal.name.
  - Right: date pill, text-[9px], font-black, uppercase, tracking-widest, `bg-black/10`, px-6px (px-1.5), py-2px (py-0.5), rounded-md 6px. Text = `MMM yyyy` (e.g. "DEC 2026" rendered uppercase) or "No Target Date".
- Stats row (flex, justify-between, items-end):
  - Left (`space-y-0.5`):
    - Label "Accumulated": text-[9px], font-black, uppercase, tracking-[0.2em], opacity 80%.
    - Value: text-2xl (24px), font-black, tracking-tighter. `₹` + counter (0 dp).
  - Right (text-right, `space-y-0.5`):
    - Label "Objective": same label style.
    - Value: text-sm (14px), font-bold, opacity 90%. `₹{target.toLocaleString()}`.
- Progress block (`space-y-1.5`):
  - Row (text-[9px], font-black, uppercase, tracking-widest, opacity 80%):
    - Left: `{pct.toFixed(0)}% MILESTONE` (pct capped at 100).
    - Right: if not achieved, `₹{remaining.toLocaleString()} LEFT`. If achieved, check icon `CheckCircle` 10px + "TARGET CLEARED" (gap 4px).
  - Progress: h-10px, rounded-full, track `bg-white/20`, indicator `bg-white`, transition-all 1000ms.
- Achieved landmark strip (only when achieved): row, centered, gap 6px, `bg-white/20`, p-6px (p-1.5), rounded-lg 8px, backdrop-blur-sm. Icon `PartyPopper` 12px, `text-yellow-300` #FDE047. Text "Financial Landmark Secured", text-[9px], font-black, uppercase, tracking-widest.
- Tap: if not achieved, haptic light, opens GoalFormSheet in edit mode. Achieved goals are not tappable (cursor-default).

**Achieved goal card:**
- Background: `bg-gradient-to-br` from `emerald-500` #10B981 to `teal-700` #0F766E. Text white. `cursor-default`. Rounded 24px. Shadow-lg.
- Same layout as active card.

**Gradient options for goal progress color (ColorSelector, wrap row gap 8px):**
Blue/Cyan `from-blue-500 to-cyan-500`; Purple/Pink `from-purple-500 to-pink-500`; Green/Teal `from-green-500 to-teal-500`; Yellow/Orange `from-yellow-500 to-orange-500`; Red/Pink `from-red-500 to-pink-500`; Indigo/Purple `from-indigo-500 to-purple-500`; Neutral/Gray `from-gray-500 to-gray-700`; Lime/Green `from-lime-500 to-green-500`; (one option not captured here); Fuchsia/Pink `from-fuchsia-500 to-pink-500`; Sky/Indigo `from-sky-500 to-indigo-500`; Amber/Red `from-amber-500 to-red-500`; Emerald/Blue `from-emerald-500 to-blue-500`; Rose/Orange `from-rose-500 to-orange-500`; Violet/Fuchsia `from-violet-500 to-fuchsia-500`.
Default color for new goal: `bg-indigo-500` #6366F1 (solid, not gradient).

**Empty states (Goals):**
- Active tab empty: icon `Target`, title "No Active Goals", description "Set your sights on something new.", button "Create New Goal" (opens create sheet).
- Completed tab empty: icon `PartyPopper`, title "No Victories Yet", description "Complete a goal to see it here." (no button).

### Spending Limits (budgets) section
- Tabs: "Current" (value active), "History" (value previous). Same tab styling as goals.
- Current tab list: `grid grid-cols-1 gap-4` (16px). Each item `relative group`.
- Below each budget card, `mt-2` (8px), `px-1` (4px), column gap 8px:
  - **Attempts pill**: `flex items-center gap-1.5` (6px), px-8px (`px-2`), py-4px (`py-1`), rounded-lg 8px, text-[9px] font-black uppercase tracking-widest, 1px border.
    - Locked: bg `rose-50` #FFF1F2, border `rose-100` #FFE4E6, text `rose-600` #E11D48. Text "Budget Locked".
    - Open: bg `blue-50` #EFF6FF, border `blue-100` #DBEAFE, text `blue-600` #2563EB. Text "{n} attempts left".
  - **Action row**: flex, justify-end, gap 6px.
    - Edit: `secondary` button, sm (h-28px? the code sets h-7 = 28px), text-[9px] font-black uppercase tracking-widest. Icon `Pencil` 10px (h-2.5 w-2.5), mr-4px. Text "Edit". Disabled when locked (opacity 50%).
    - Delete: `ghost`, h-28px, text-destructive (#EF4444), icon `Trash2` 10px, text "Delete".
- Previous (History) tab:
  - Month picker bar: `p-1` (4px), bg `muted/50`, rounded-xl 12px. Button full width, `ghost`, h-36px (h-9), rounded-lg 8px, justify-between, text-[9px] font-black uppercase tracking-widest.
    - Left: icon `CalendarIcon` 14px (h-3.5 w-3.5) primary, mr-8px. Label: selected month as "MMMM yyyy" (e.g. "MARCH 2026" uppercase), or placeholder "Select Analysis Period" when none selected.
    - Right: icon `ArrowRight` 12px, opacity 50%.
  - Popover calendar: w-auto, p-0, `shadow-2xl`, rounded-2xl 16px, overflow hidden, no border. Selecting any date sets the month to the first day of that month.
  - Default (none selected): shows the latest previous month that has data.
  - Card list: `grid grid-cols-1 gap-3` (12px).
- Empty (Current): icon `DollarSign`, title "No Active Budgets", description "Set spending limits for this month.", button "Define Category Limit".
- Empty (History): icon `Clock`, title "No Historical Data", description "Past budgets will appear here." (no button).

**Delete budget dialog:**
- AlertDialog content: `rounded-[1.5rem]` (24px), `border-none`, `shadow-2xl`.
- Title: "Delete Budget?", text-lg (18px), font-black, tracking-tight.
- Description: "This action is permanent.", text-xs (12px), font-medium.
- Footer: gap 8px.
  - Cancel: rounded-lg, font-bold, uppercase, text-[10px], tracking-widest, `border-none`, bg `muted`. Text "Cancel".
  - Confirm: rounded-lg, font-bold, uppercase, text-[10px], tracking-widest, bg destructive. Text "Confirm Delete".

### Goal form sheet (create/edit)
Drawer: height **90vh** on mobile, **80vh** on md+ (use 90% of screen height on phones). `max-w-md` 448px centered. Flex column.

- Header (`flex-shrink-0`, relative, text-left):
  - Title (text-2xl, 24px/32px, default weight from DrawerTitle): "Create New Goal" or "Edit Financial Goal".
  - Description: "Set a target for your savings or investment." (text-sm muted-foreground).
  - Close button: ghost, icon-size 32px (h-8 w-8), at top 16px right 16px. Icon `X` 16px.
- Scroll body: `px-4` (16px). Form `space-y-6` (24px), bottom pad 24px.

**Field order (top to bottom):**

1. **Goal achieved banner** (only if current >= target and target > 0):
   - `p-4` (16px), bg `green-100` #DCFCE7, text `green-800` #166534, rounded-lg 8px, flex row, gap 12px (`space-x-3`).
   - Icon `PartyPopper` 20px (h-5 w-5). Text "Goal Target Reached!" font-semibold.

2. **Goal Name**
   - Label: "Goal Name" (text-sm 500).
   - Input placeholder: "e.g., Bali Vacation Fund".
   - Error (below, text-sm, destructive): "Name is required."

3. **Target Amount (₹)**
   - Label: "Target Amount (₹)".
   - Input: `pl-10` (40px left padding for icon), `text-lg` (18px), `h-12` (48px). Type number, step 1, min 0.01, placeholder "0.01", inputMode decimal. Blocks typing "-" and "e".
   - Left icon: `IndianRupee` 16px, muted-foreground, positioned left 12px, vertically centered.
   - Error: "Target amount must be greater than zero."

4. **Current Saved Amount (₹)** (display only, not an input)
   - Label (no htmlFor).
   - Box: `p-3` (12px), bg `muted` (#F1F5F9), rounded-lg 8px.
   - Row (flex, space-between, items-center):
     - Value: `₹{current.toFixed(0)}`, text-lg (18px), font-semibold.
     - If achieved: `CheckCircle` 20px (h-5 w-5), `text-green-500` #22C55E, springs in (scale 0 → 1, spring stiffness 500, damping 20).
   - Sub text: text-xs (12px), muted-foreground, mt-4px.
     - Achieved: "Goal achieved! 🎉"
     - Else: "Remaining: ₹{(target - current).toFixed(0)}"
   - Progress (only if target > 0): mt-8px, h-8px (`h-2`), track `bg-muted`, indicator color = selected progress color class.

5. **Update Goal Savings** (edit mode only)
   - Container: `space-y-4` (16px), `p-4` (16px), bg gradient `from-green-50` #F0FDF4 to `teal-50` #F0FDFA (to-r = left to right), rounded-lg 8px, 1px border `green-200` #BBF7D0. Dark: border `green-800` #166534.
   - Header row (gap 12px): icon `Target` 24px (h-6 w-6), `text-green-500` #22C55E. Title h3 font-semibold, text `green-800` #166534 (dark `green-200` #BBF7D0). Text "Update Goal Savings".
   - **Withdrawal Discipline notice:**
     - Row, `p-2.5` (10px), rounded 6px (`rounded` = 4px default, use 4px), 1px border, text-xs, flex, gap 8px, items-start.
     - Allowed state: bg `blue-100` at 50% (#DBEAFE80), border `blue-200` #BFDBFE, text `blue-800` #1E40AF. Icon `Clock` 16px (h-4 w-4), mt 2px.
     - Limit reached: bg `red-100` at 50%, border `red-200` #FECACA, text `red-800` #991B1B. Icon `AlertTriangle` 16px.
     - Title: "Withdrawal Discipline", font-bold, uppercase, tracking-tight.
     - Body (mt 2px, opacity 90%):
       - Allowed: "You have {2 - count} withdrawals left this month from your savings."
       - Limit reached: "Limit reached for this month (2/2). Stay committed!"
   - **Available Balance line:** text-sm (14px), `green-600` #16A34A (dark `green-300` #86EFAC). Value span font-bold, color `green-800` #166534, or destructive if balance < 0. Text: "Available Balance: ₹{balance.toFixed(2)}".
   - **Amount (₹)** (`space-y-1`, label text-xs font-bold uppercase, muted-foreground):
     - Label text: "Amount (₹)".
     - Input: `pl-10 w-full`, type number, step 1, min 0.01, placeholder "0.01", inputMode decimal. Blocks "-" and "e". Icon `IndianRupee` left.
     - Value clamps to ≥ 0.
   - **Transaction Date** (`space-y-1`, label text-xs font-bold uppercase):
     - Button: outline, `w-full justify-start text-left font-normal bg-background`. Icon `CalendarIcon` 16px (mr-2 = 8px). Text: `PPP` format (e.g. "Oct 10th, 2026"), or "Pick a date" in muted.
     - Popover calendar opens below.
   - **Action buttons** row: `flex space-x-2` (8px), pt-8px.
     - Add: `flex-1`, bg `green-500` #22C55E hover `green-600` #16A34A, white text. Icon `Plus` 16px, mr-4px. Text "Add". Disabled if submitting, amount empty/<=0, or amount > balance.
     - Remove: `flex-1`, destructive variant. Icon `Minus` 16px. Text "Remove". Disabled if submitting, amount empty/<=0, amount > current, or withdrawal limit reached.

6. **Target Date (Optional)**
   - Label: "Target Date (Optional)".
   - Button: outline, full width, left-aligned, font-normal, icon `CalendarIcon` 16px. Text `PPP` or "Pick a date" (muted).
   - Calendar popover: shadcn Calendar, auto width.

7. **Progress Color**
   - Label: "Progress Color".
   - ColorSelector (gradient swatches, wrap, gap 8px). Selected swatch shows ring/border.
   - Error: "Color is required."

**Footer** (`p-4` 16px, border-top 1px, bg background, flex-shrink 0):
- Row, gap 16px (`gap-4`).
  - Primary button: flex-1, h-12 (48px), text-lg (18px). Icon `Save` 20px + gap 8px + text:
    - Create: "Create Goal"
    - Edit: "Save Changes"
    - Submitting: spinner `Loader2` 20px, animate-spin.
  - Edit mode only: destructive icon button, 40x40px. Icon `Trash2` 20px (h-5 w-5).
    - Opens AlertDialog:
      - Title "Delete Goal?"
      - Body: "This will return any saved funds (₹{current.toLocaleString()}) to your available balance. This action cannot be undone."
      - Cancel: "Cancel". Confirm: "Delete & Refund" (bg destructive, hover destructive/90). Spinner while submitting.

**Goal form toasts (success/error):**
- Create success: "New goal '{name}' created!"
- Edit success: "Goal '{name}' updated successfully!"
- Delete success: "Goal '{name}' deleted. Funds returned to balance."
- Save failure: "Failed to save goal."
- Delete failure: "Failed to delete goal."
- Target validation fail (submit): "Target amount must be greater than zero."
- Not logged in: "You must be logged in."
- Add savings: "Amount must be greater than zero." / "Insufficient balance. Available: ₹{balance.toFixed(2)}." / "Please save the goal first." / success "Added ₹{amt.toFixed(2)} to goal '{name}'!" / failure "Failed to record contribution."
- Withdraw: "Withdrawal limit reached (2/2)." / "Cannot withdraw more than ₹{current.toFixed(2)}." / "Goal data missing." / success "Removed ₹{amt.toFixed(2)} from goal '{name}'." / failure "Failed to record withdrawal."

**Goal form rules:**
- Withdrawals max **2 per calendar month** (count ledger entries of type WITHDRAWAL in current month).
- Achieved state uses `current >= target && target > 0`.
- Toast style: see global toast (bottom, short). Not specified here.

---

## Budgets

Two screens use budgets: the Goals page section (above) and a standalone AddBudgetSheet. Budget card and form details below.

### Budget progress card (`BudgetProgressCard`)
- Card: `group relative overflow-hidden`, hover shadow-lg, transition-all 300ms, `active:scale-[0.98]`, `border-none`, `rounded-[1.5rem]` (24px).
- **Background by state:**
  - Breached (spent > limit): `bg-rose-50/50` #FFF1F2 at 50%; dark `rose-950/10`.
  - Warning (utilization >= 80% and not breached): `bg-amber-50/50` #FFFBEB at 50%; dark `amber-950/10`.
  - Healthy: `bg-muted/30` (#F1F5F9 at 30%).
- **Left accent bar:** absolute, top 0, left 0, width 6px (`w-1.5`), full height. Color:
  - Breached: `rose-500` #F43F5E.
  - Warning: `amber-500` #F59E0B.
  - Healthy: the category's color class (default `bg-blue-500` #3B82F6).
- Header (`flex-row items-center justify-between`, `p-4` (16px), `pb-2` (8px), space-y-0):
  - Left (gap 10px, `space-x-2.5`):
    - Category icon chip: 36x36px (`w-9 h-9`), rounded-lg 8px, shadow-sm, flex-shrink 0. Background = category color class. Icon = category's Lucide icon (default `Tag`), size 18px, white.
    - Text column (min-w-0):
      - Category name: text-sm (14px), font-black, uppercase, tracking-tight, truncate, max-width 120px. Default "Uncategorized".
      - Month: text-[10px], font-black, muted-foreground, uppercase, tracking-widest. Format "MMMM yyyy" (e.g. "OCTOBER 2026") or "No Date".
  - Right (text-right):
    - Label "Budget Limit": text-[10px], font-black, muted-foreground, uppercase, tracking-widest, mb-2px.
    - Value: `₹{limit.toLocaleString()}`, text-sm (14px), font-black.
- Content (`p-4` top 0, `space-y-4`):
  - Row (flex, justify-between, items-end):
    - Left (space-y-0.5):
      - Label "Category Spend": text-[10px], font-black, uppercase, tracking-[0.2em], muted-foreground.
      - Value `<h3>`: text-2xl (24px), font-black, tracking-tighter. Color: breached `rose-600` #E11D48, else `text-primary`. Value = `₹` + counter (0 dp).
    - Right (text-right): status Badge, variant outline, text-[10px], font-black, uppercase, px-6px (px-1.5), py-0, border none.
      - Breached: bg `rose-500` #F43F5E, text white, label **"BREACHED"**.
      - Warning: bg `amber-500` #F59E0B, text white, label **"WARNING"**.
      - Healthy: bg `muted`, text muted-foreground, label **"HEALTHY"**.
  - Progress block (`space-y-1.5`):
    - Row (text-[10px], font-black, uppercase, tracking-widest, muted-foreground):
      - Left: `{pct.toFixed(0)}% UTILIZATION` (pct is not capped in text, e.g. "135% UTILIZATION").
      - Right: breached `OVER BY ₹{|remaining|.toFixed(0)}` in `rose-600`; otherwise `₹{remaining.toFixed(0)} LEFT` in `emerald-600` #059669.
    - Progress: h-8px (`h-2`), track `bg-muted`, rounded-full. Indicator: breached `rose-500`, warning `amber-500`, healthy `bg-primary`. Transition-all 1000ms (fills on mount).
    - Bar width is capped at 100%.
  - Breach notice (only when breached):
    - Row, gap 6px, `bg-rose-500/10` (10% rose-500), p-8px (`p-2`), rounded-lg 8px, border 1px `rose-500/20`.
    - Icon `AlertTriangle` 12px, `rose-600`, shrink 0.
    - Text: "Financial Boundary Violated. Stop further outflows.", text-[10px], font-black, uppercase, tracking-tight, `rose-700` #BE123C.

**Thresholds:** warning when `utilization >= 80%` and not over. Breached when `spent > limit` (strictly greater).

**Tap:** opens BudgetTransactionsSheet.

### Budget transactions sheet (`BudgetTransactionsSheet`)
Drawer height **85vh** (mobile), **75vh** (md+). Max-w-md, flex column.

- Header (`flex-shrink-0`, relative, text-left, padding default):
  - Row (gap 12px, pr-32px so it doesn't overlap close button):
    - Category chip: 40x40px circle (`rounded-full`), category color bg, icon 20px white (default `Tag`/`DollarSign`).
    - Title (DrawerTitle text-xl = 20px): category name.
    - Description (DrawerDescription, text-sm): "{MMMM yyyy} Spending Breakdown".
  - Close button: ghost, 32x32px, top 16px, right 16px, icon `X` 16px.
- Summary card (`px-4 py-2`, inner `p-4` 16px, bg `muted/50` (#F1F5F9 at 50%), rounded-xl 12px, space-y-4):
  - Row (flex, justify-between, items-end):
    - Left: label "Total Spent" (text-xs (12px), font-bold, muted-foreground, uppercase, tracking-wider). Value text-3xl (30px), font-black. Color destructive (#EF4444) if over, else `text-primary`. Value = `₹` + counter (2 dp).
    - Right (text-right): label "Limit" (same label style). Value `₹{limit.toLocaleString()}` text-lg (18px), font-bold.
  - Progress block (`space-y-2`):
    - Progress h-8px (`h-2`). Indicator: destructive (#EF4444) if over, else primary.
    - Row (text-xs (12px), font-medium, mt 0):
      - Left: over → "Limit exceeded" (destructive). Else `{pct.toFixed(0)}% utilized` (muted-foreground).
      - Right: over → "Over by ₹{|remaining|.toFixed(0)}" (destructive, font-bold). Else "₹{remaining.toFixed(0)} left" (`green-600` #16A34A, font-bold).

- Section title row: `px-4 pt-4 pb-2` (16px 16px 8px 16px), border-bottom 1px, flex-shrink 0.
  - Heading h3: text-sm (14px), font-bold, uppercase, tracking-widest, muted-foreground. Icon `Clock` 16px (h-4 w-4), mr-8px. Text "Transaction History".

- Transaction list (ScrollArea flex-1, px-4, inner `space-y-3` (12px), py-4 (16px)):
  - Row card: flex, justify-between, items-center, `p-3` (12px), bg `card` (white / #020817), 1px border, rounded-xl 12px. Hover bg `muted/30` with color transition.
    - Left (flex, gap 12px, overflow hidden):
      - Icon chip: 32x32px, rounded-lg 8px, bg `muted`, icon 14px (`Icon name = tx.category.icon or DollarSign`), color muted-foreground.
      - Text (min-w-0):
        - Title: text-sm (14px), font-bold, truncate. Uses notes if present, else category name.
        - Date: text-[10px], uppercase, font-medium, muted-foreground. Format "MMM dd, yyyy" (e.g. "OCT 10, 2026").
    - Right (text-right, flex-shrink 0, ml-12px):
      - Amount: text-sm (14px), font-black, `text-destructive` #EF4444. Format "-₹{amount.toFixed(2)}".
      - Payment mode: text-[9px], muted-foreground, uppercase, font-bold (e.g. "UPI", "CARD").
- Empty state (inside list, py-48px (py-12) center):
  - Icon circle: 48px (`w-12 h-12`), bg `muted`, rounded-full, mb-12px. Icon `Info` 24px (h-6 w-6), color muted-foreground at 50%.
  - Text: "No transactions found for this budget period.", text-sm, muted-foreground.
- Footer (`p-4` 16px, border-top 1px, bg background):
  - Button outline, full width, h-48px (`h-12`), font-bold. Text "Close History".

### Add budget sheet (`AddBudgetSheet`, `src/components/budget/`)
Drawer height **90vh** mobile, **80vh** md+. Max-w-md (layout uses max-w-sm inner = 384px).

- Header (px-0):
  - Title (text-2xl, font-black, flex, gap 8px): icon `LayoutGrid` 24px (h-6 w-6), `text-primary`. Text "Set Budget".
  - Description: "Define monthly limits for categories."

- **Monthly Limit** (`space-y-2` label):
  - Label: text-[10px], font-black, uppercase, tracking-widest, muted-foreground. Text "Monthly Limit".
  - Input: `pl-10`, h-48px (`h-12`), rounded-2xl 16px, font-black, text-lg (18px), `border-2` (2px border), focus ring primary. Placeholder "e.g. 5000". Icon `IndianRupee` 16px left-12px.
  - No validation on this screen beyond the Activate button disabled state.

- **Select Category** (flex-1 column, fills space):
  - Row (space-between): label "Select Category" (same label style as above). Right: ghost button, h-28px, text-[10px], font-black, uppercase, primary text, icon `Plus` 12px (h-3 w-3), mr-4px. Text "Add Custom Category". Opens AddCategorySheet.
  - Grid area: scroll, `-mx-2`. Inner `px-2 grid grid-cols-2 gap-2` (8px), pb-24px.
  - Category tile (button, text left):
    - Flex, items-center, gap 12px, `p-3` (12px), rounded-2xl 16px, **2px border**, transition-all.
    - Default: border `muted` (#F1F5F9), hover border `primary/30`.
    - Selected: border `primary` (slate-900 light), bg `primary/5`, `ring-1 ring-primary` (1px ring).
    - Icon chip: 32x32px, rounded-xl 12px, flex-shrink 0, white icon 16px. Bg = category color (default `bg-primary`).
    - Name: text-xs (12px), font-bold, truncate.
    - Selected check: `CheckCircle2` 16px (h-4 w-4), primary, ml-auto.
  - Haptic light on tap.

- **Selected summary card** (only when a category is picked):
  - `bg-primary/5` (5%), 1px border `primary/20` (20%), rounded-2xl 16px, p-12px (`p-3`), flex, space-between, items-center. Animations: fade-in, slide-in-from-bottom 8px (`slide-in-from-bottom-2`), 300ms.
  - Left (gap 12px):
    - Icon chip: 32x32px, rounded-lg 8px, category color, icon 16px white.
    - Label "Selected": text-xs (12px), font-bold, uppercase, tracking-tight, primary.
    - Category name: text-sm (14px), font-black.
  - Right: ghost clear button, 28x28px (h-7 w-7), p-0, `X` icon 16px, muted-foreground. Hover destructive.

- **Footer** (`DrawerFooter`, px-0, pt-16px, flex-shrink 0):
  - Button full width, h-56px (`h-14`), rounded-2xl 16px, font-black, uppercase, tracking-widest, shadow-lg with primary tint (`shadow-primary/20`).
  - Idle: icon `Plus` 20px (h-5 w-5), mr-8px. Text **"Activate Budget"**.
  - Submitting: spinner `Loader2` 20px.
  - Disabled when: submitting, no category, or amount empty.

- Create validation (toast on error): "Please select a category and enter an amount."
- Success toast: "Budget set successfully!"; failure: "Failed to set budget."

### Budget form sheet (`BudgetFormSheet`, `src/components/budgets/`) (edit + create)
Drawer height **85vh** mobile, **75vh** md+. Max-w-md. Contents render after a 300ms delay on close.

- Header:
  - Title (text-2xl): edit "Modify Spending Limit", create "New Budget Entry".
  - Description: "Define your monthly boundaries."
  - Close: ghost 32x32, top 16px right 16px, `X` 16px.

- **Discipline Tracker card** (edit mode only):
  - Container: `p-4` (16px), rounded-2xl 16px, 1px border, flex row, space-between, transition-all.
    - Allowed: bg `blue-50` #EFF6FF, border `blue-200` #BFDBFE.
    - Locked: bg `rose-50` #FFF1F2, border `rose-200` #FECDD3.
  - Left (gap 12px):
    - Icon chip: `p-2` (8px), rounded-xl 12px. Allowed: bg `blue-500` #3B82F6 with `ShieldCheck` 16px white. Locked: bg `rose-500` #F43F5E with `AlertTriangle` 16px white.
    - Text column (space-y-2px):
      - Label "Discipline Tracker": text-[10px], font-black, uppercase, tracking-widest. Allowed color `blue-700` #1D4ED8; locked `rose-700` #BE123C.
      - Status: text-xs (12px), font-bold, foreground. Text: "Attempt {n+1} of 2" (allowed) or "Budget is now locked." (locked).
  - Badge (right): h-24px (`h-6`), font-black. Variant `destructive` if locked, else `secondary`. Text "{remaining} LEFT" (e.g. "1 LEFT", "0 LEFT").

- **Spending Category** (label style: text-[10px], font-black, uppercase, tracking-widest, muted-foreground, `ml-4px`):
  - Create mode: category selector (grid chips, see CategorySelector) filtered to expense categories. Under it, a link (block, center, text-[10px], muted-foreground, hover primary, font-bold, leading tight, mt-8px, px-16px):
    - Text: "can't find category? don't worry you can create your own custom category click here" (lowercase as written). Navigates to Categories page and closes sheet.
  - Edit mode (locked to existing category): card `p-4` (16px), bg `muted/50`, rounded-2xl 16px, 1px border, flex, gap 12px.
    - Icon chip: 40x40px, rounded-xl 12px, shadow-sm, category color, icon 20px white (default `Tag`).
    - Name: font-black, text-sm, uppercase, tracking-tight.
    - Subcategory line: text-[10px], muted-foreground, font-medium, italic, leading-none, mt-4px. Text = category's `subCategories` value.

- **New Limit (₹)** (label style as above):
  - Input: `pl-10`, text-xl (20px), h-56px (`h-14`), font-black, rounded-2xl 16px. Type number, step 0.01, min 0.01, inputMode decimal. Blocks "-" and "e". Disabled when edit limit reached.
  - Left icon `IndianRupee` 20px (h-5 w-5), left-12px.
  - Error (text-sm, destructive, mt-4px): "Limit must be greater than zero." (form) or "Budget limit must be greater than zero." (submit toast).
  - Edit hint (edit mode and not locked): text-[10px], `amber-600` #D97706, font-bold, italic, px-4px. Text "* Updating this counts as your final allowed attempt."

- **Footer** (`p-4`, border-top 1px, bg background):
  - Full-width button, h-56px (`h-14`), text-lg (18px), font-black, uppercase, tracking-widest, rounded-2xl 16px. Disabled when submitting or edit locked.
  - Idle: icon `Save` 20px, mr-8px. Text: edit "Commit Change", create "Initialize Budget".
  - Submitting: spinner `Loader2` 20px.

- Toasts: success "Budget updated!" (edit) / "Budget created!" (create). Failure: server error message, else "Failed to save budget."

**Attempt rule:** 2 edits max per budget. Edit button disabled after 2 edits. Edit count 0 shows "2 attempts left", 1 shows "1 attempts left" (text as written, no pluralization fix), 2 shows "Budget Locked".

---

## Emergency Fund

Two sheets exist:
- `src/components/wealth/EmergencyFundSheet.tsx` — **this is the one Goals opens.** Specified in full below.
- `src/components/emergency/EmergencyFundSheet.tsx` — a simpler sibling sheet with the same spirit (not used from Goals). Differences listed at the end.

### Entry card (on Goals page)
See "Emergency Security hero card" in the Goals section. Value, months-cover badge, funded %, target, low-buffer alert, color states.

### Wealth emergency fund sheet (`wealth/EmergencyFundSheet.tsx`)
Drawer height **90vh** mobile, **80vh** md+. Max-w-md, flex column.

- Loading state: while fund data loads, sheet shows **85vh** drawer with a centered `Loader2` 32px (h-8 w-8), primary color, spinning, padding 32px.

- Header:
  - Title (text-2xl, flex, gap 8px): icon `Scale` 24px (h-6 w-6), **`text-yellow-500` #EAB308**. Text "Manage Emergency Fund".
  - Description: "Track and update your savings buffer."
  - Close button: ghost 32x32, top 16px right 16px, `X` 16px.

- Scroll body (`px-4`, inner `space-y-6` 24px, pb 24px):

1. **Suggested Goal card**
   - Card: `p-4` (16px), bg `muted/50`, 1px border (`border-border`), rounded-lg 8px (Card default; shadow-sm).
   - Top row (flex, space-between, items-center, mb-16px):
     - Title: "Suggested Goal (6 mo)", text-sm (14px), font-semibold.
     - Button: outline, sm (h-36px), icon-only refresh-style button `SortAsc` 16px. While calculating, `Loader2` 16px spinning. Disabled while calculating.
   - Value row (flex, space-between, items-center, bg `background`, p-8px (`p-2`), rounded 4px (`rounded` default), 1px border):
     - Value: text-sm (14px), font-medium: `₹{suggested.toFixed(0)}`.
     - Button: ghost, sm, h-28px (`h-7`), text-xs (12px), color `blue-600` #2563EB. Text **"Use This"**. Sets target to suggested and months to 6.

2. **Duration (Months)**
   - Label: "Duration (Months)" (text-sm 500).
   - Input: type number, min 1, max 24, numeric keyboard, `text-lg` (18px), h-48px. Value shows blank if 0.
   - Clamp: parseInt; invalid → 0.
   - Validation (schema, not shown inline here): "Months must be at least 1." / "Months cannot exceed 24." (not rendered inline in this sheet; shown only as a form error if present).

3. **Target Amount (₹)**
   - Label: "Target Amount (₹)".
   - Input: `pl-10`, text-lg (18px), h-48px. Icon `IndianRupee` 16px left-12px, muted. Type number, step 1, min 0.01, placeholder "0.01", inputMode decimal. Blocks "-" and "e". Value ≥ 0. Auto-set from months × average monthly expense (6-month window). Editable.

4. **Fund status panel**
   - Box: `p-4` (16px), bg `muted` (#F1F5F9), rounded-lg 8px, 1px border `yellow-200` #FEF08A.
   - Row (flex, space-between, items-center, mb-8px):
     - Value: text-2xl (24px), font-semibold: `₹{current.toFixed(2)}`.
     - Right: if achieved (current >= target), `CheckCircle` 24px (h-6 w-6) `text-green-500`.
   - Progress: h-8px (`h-2`). Indicator `bg-yellow-500` #EAB308. Track bg muted (default).
   - Caption: text-xs (12px), muted-foreground, mt-8px. Text: "{pct.toFixed(1)}% of ₹{target.toFixed(0)} target."
   - Percent is capped at 100 for the bar, displayed value is uncapped (note: the text uses `progressPercentage`, which is capped at 100).

5. **Update Fund Value panel**
   - Box: `space-y-4` (16px), `p-4` (16px), bg `yellow-50` #FEFCE8 (dark `yellow-900/10`), rounded-lg 8px, 1px border `yellow-200` #FEF08A.
   - Label "Update Fund Value": font-bold (text-sm 500 → bold).
   - **Withdrawal Discipline notice** (same pattern as Goals):
     - Row, `p-2.5` (10px), rounded 4px, 1px border, text-xs, bg white (`bg-background`), flex, gap 8px.
     - Allowed: border `blue-200` #BFDBFE, text `blue-800` #1E40AF, icon `Clock` 16px.
     - Limit reached: border `red-200` #FECACA, text `red-800` #991B1B, icon `AlertTriangle` 16px.
     - Title: "Withdrawal Discipline", font-bold, uppercase, tracking-tight.
     - Body: "You have {2 - count} withdrawals left this month." or "Monthly limit reached (2/2). Keep saving!"
   - **Amount (₹)** (label text-[10px], uppercase, font-bold, muted):
     - Input: `pl-10 w-full bg-background`, type number, min 0.01, placeholder "0.01", inputMode decimal, icon `IndianRupee` left. Blocks "-" and "e". Value ≥ 0.
   - **Available Balance row** (flex, space-between, items-center, text-xs, font-medium, `bg-background/50` (50%), p-8px, rounded 4px, 1px border):
     - Label: "Available Balance:" (muted-foreground).
     - Value: `₹{balance.toFixed(2)}`, font-bold. Color `text-primary`, or destructive if negative.
   - **Transaction Date** (label text-[10px], uppercase, font-bold, muted):
     - Button: outline, full width, left-aligned, font-normal, bg-background. Icon `CalendarIcon` 16px (mr-8px). Text `PPP` or "Pick a date".
     - Calendar popover (auto width, p-0).
   - **Action buttons** (flex, gap 8px, pt-8px):
     - Add: `flex-1`, bg `green-500` #22C55E hover `green-600` #16A34A, white text. Text "Add". Disabled if submitting or amount empty.
     - Remove: `flex-1`, destructive. Text "Remove". Disabled if submitting, amount empty, or withdrawal limit reached.

- Footer (`p-4`, border-top 1px, bg background):
  - Row, gap 16px.
    - Close: outline, flex-1, h-48px (`h-12`), text-lg (18px). Text "Close".
    - Update: flex-1, h-48px, bg `green-600` #16A34A (default hover). Text **"Update Goal"**. Disabled if submitting or target <= 0.

**Toasts:**
- Update success: "Emergency Fund updated successfully!"; failure: "Failed to update emergency fund."
- Add success: "Added to emergency fund!"; failure: "Error updating fund."
- Remove success: "Removed from emergency fund."; failure: "Error updating fund."
- Insufficient: "Insufficient balance." (shown when amount > available).
- Withdrawal limit: "Withdrawal limit reached (2/2 this month)."
- Empty/invalid amount: "Amount must be greater than zero."

**Rules:**
- Suggested target = average monthly expense over last 6 months × 6.
- Changing months auto-sets target = average monthly expense × months.
- Withdrawals max 2 per calendar month.
- Add/Remove close the sheet after success. Update Goal does too.

### Emergency fund sheet (`emergency/EmergencyFundSheet.tsx`) — sibling, not used from Goals
Differences from wealth version:
- Drawer height **85vh** mobile, **70vh** md+, `max-w-sm` inner with `p-4`, `space-y-6`.
- Title (text-2xl font-black, flex, gap 8px): icon `ShieldCheck` 24px `text-primary`. Text "Emergency Fund". Description: "Secure your future with a safety net."
- Two stat tiles, `grid grid-cols-2 gap-3` (12px):
  - Current Fund: `p-4` (16px), bg `primary/5` (5%), rounded-2xl 16px, 1px border `primary/10`. Label text-[10px], font-black, uppercase, muted, mb-4px. Value text-xl (20px), font-black, text-primary. `₹` + counter (0 dp).
  - Available Cash: `p-4`, bg `muted/30`, rounded-2xl, 1px border `border`. Value text-xl font-black, default foreground.
- Target Amount input: label text-[10px], font-black, uppercase, tracking-widest. Input `pl-10 h-48px rounded-xl 12px font-bold`. Icon `IndianRupee` 16px. No placeholder.
- "Manage Funds" toggle: two buttons, flex, gap 8px, mb-8px, each `flex-1 rounded-xl h-40px font-bold`.
  - Active: default (slate-900 bg, white). Inactive: outline.
  - Deposit: icon `ArrowUpRight` 16px, mr-4px. Text "Deposit".
  - Withdraw: icon `ArrowDownRight` 16px. Text "Withdraw".
- Amount input: placeholder "Enter amount...", `pl-10 h-48px rounded-xl font-bold`.
- Save button: full width, h-48px, rounded-xl, font-black, uppercase, tracking-widest. Icon `Save` 16px, mr-8px. Text "Save Changes". Spinner while pending.
- Deposit over balance toast: "Insufficient balance. You only have ₹{available.toFixed(0)}."
- Success toasts: deposit "Fund updated!", withdraw "Funds withdrawn!". Failure: "Update failed."
- Note: no withdrawal limit in this version.

---

## Pending / Split Transactions Screen

Route: Pending page. Heading "Pending", sub "Unsettled Ledger".

### Layout
- Root: `p-3` (12px), `pt-4` (16px), `pb-24` (96px bottom), `space-y-5` (20px) between blocks.
- Header row: flex, space-between, items-center, `pt-1` (4px).
  - Left:
    - `<h1>` "Pending": text-2xl (24px), font-black, tracking-tighter.
    - Subtitle: "Unsettled Ledger": text-xs (12px), font-bold, muted-foreground, uppercase, tracking-widest.
  - Right: ghost icon button, 40x40px, rounded-full, `HelpCircle` 24px, muted. Starts onboarding tour.

- **Search row** (flex, gap 8px, `space-x-2`):
  - Search input wrapper: flex-1, relative.
    - Icon `Search` 14px (h-3.5 w-3.5), muted, left 12px, vertically centered.
    - Input: placeholder "Search items...", `pl-9` (36px left), h-44px (`h-11`), rounded-xl 12px, **border-2** (2px), focus ring `violet-500` (2px), text-sm. Value bound to search text.
  - Add button: flex-shrink 0, 44x44px (`h-11 w-11`), rounded-xl 12px, bg `violet-600` #7C3AED, hover `violet-700` #6D28D9, shadow-lg with `violet-500/20` (20% violet-500 #8B5CF6). Icon `Plus` 20px (h-5 w-5), white. Haptic medium. Opens AddPendingSheet.

- **Filter block** (`space-y-4`, 16px):
  1. **Group type segmented control** wrapper: `bg-muted/30` (#F1F5F9 at 30%), p-4px (`p-1`), rounded-xl 12px, 1px border.
     - TabsList: `grid w-full grid-cols-3`, h-32px (`h-8`), bg transparent.
     - Triggers (text-[9px], font-black, uppercase, tracking-widest, rounded-lg 8px):
       - "All" (value all), "Single" (value single), "Splits" (value split).
       - Active: bg white (dark `zinc-800` #27272A), shadow-sm.
     - Haptic selection on change.
  2. **Status tabs** (Tabs with `space-y-4`):
     - Row (flex, space-between, items-center). TabsList h-40px (`h-10`), p-4px, bg `muted/50`, rounded-xl 12px.
     - Triggers (text-[10px], font-bold, uppercase, tracking-wide, rounded-lg, px-12px (`px-3`)):
       - "Active (N)" where N = count of unsettled groups (remaining due > 0.01). Value pending.
       - "Cleared" (value history).

### Tab content: Active
- Section header: `SectionHeader` icon `Filter`, title **"Unsettled Items"**, color chip `bg-violet-500` #8B5CF6.
- List below: `space-y-2` (8px), grouped by date.

### Tab content: Cleared
- Section header: icon `CheckCircle`, title **"Settled History"**, chip `bg-green-600` #16A34A.
- Month navigator (mb-12px): `flex items-center justify-between`, `bg-muted/30`, p-6px (`p-1.5`), rounded-xl 12px, 1px border.
  - Prev button: ghost sm, h-28px (`h-7`), w-28px (`w-7`), p-0, rounded-lg 8px. Text "←" (left arrow glyph).
  - Label: text-[10px], font-black, uppercase, tracking-widest. `MMMM yyyy` (e.g. "OCTOBER 2026").
  - Next button: same, "→".
  - Month change: list fades (opacity 50%) and pulses for 500ms (`animate-pulse`).
- Filter: items shown only for the selected month (based on main transaction date).
- List: same grouped list.

### Date group header
- Sticky (`sticky top-0`), bg `background` at 95% (`bg-background/95`), backdrop-blur-sm, z-10.
- Text: `EEEE, MMM dd` (e.g. "Friday, Oct 10"), text-[9px], font-black, uppercase, tracking-widest, muted-foreground.
- Padding: pt-8px (`pt-2`), py-6px (`py-1.5`), border-bottom 1px.
- Group spacing: `space-y-2` (8px) between date blocks' contents.

### Empty list
- Centered text, `py-12` (48px), text-[10px], font-medium, uppercase, tracking-widest, opacity 50%, muted:
  - "No ledger items found"

### Pending card: single (`PendingSingleCard`)
- Card: `p-4` (16px), `rounded-2xl` (16px), `border-l-4` (4px left border), hover shadow-lg, transition-shadow, `cursor-pointer`. Tap opens details (split details for active, payment sheet for cleared).
  - Border color:
    - Active, I owe (debt): `border-destructive` #EF4444.
    - Active, I receive: `border-green-500` #22C55E.
    - Cleared: `border-green-500/30` (30%).
- Body (`p-0`) row, flex, space-between, items-center:
  - Left (flex, gap 12px, min-w-0, flex-1):
    - Icon chip: 40x40px (`w-10 h-10`), rounded-xl 12px, flex-shrink 0.
      - Active debt: bg `destructive/10` (10% red), icon `User` 20px, text destructive.
      - Active receive: bg `green-500/10`, icon `User` 20px, text `green-600` #16A34A.
      - Cleared debt: bg `destructive/10`, icon `CheckCircle` 20px, destructive.
      - Cleared receive: bg `green-500` #22C55E solid, icon `CheckCircle` 20px, **white**.
    - Text column (min-w-0, flex-1):
      - Title line: text-sm (14px), font-bold, tracking-tight, **capitalize**. Color: destructive (debt) or `green-600` (receive).
        - Active creator, expense: "you have to send to {name}"
        - Active creator, income: "you will receive from {name}"
        - Active recipient, expense: "you will receive from {name}"
        - Active recipient, income: "you have to send to {name}"
        - Cleared debt: "Sent to {name}"; cleared receive: "Received from {name}".
        - Name fallbacks: "Someone".
      - Subline: text-[10px], muted-foreground, truncate, font-medium, uppercase, tracking-tight, mt-2px. Notes if present, else payment mode (e.g. "UPI", "CARD", "CASH", "BANK TRANSFER").
  - Right (text-right, flex-shrink 0, ml-16px):
    - Amount: text-lg (18px), font-black, tracking-tighter, leading-none. Color destructive (debt) or `green-600`.
      - Format: sign + ₹ icon + number, 0 dp. Sign "-" for debt, "+" for receive.
      - Active shows remaining due; cleared shows original amount.
      - The ₹ is an `IndianRupee` icon 16px (h-4 w-4), inline, mr-2px, not a text glyph.
    - Badge: outline variant, text-[8px], font-black, uppercase, h-16px (`h-4`), px-4px (`px-1`), mt-4px.
      - Active partial: "Partial". Active pending: "Pending" (muted bg `muted`, muted text).
      - Cleared: "Settled" (bg `green-500` solid, white text, no border).

- Footer row: `flex justify-between items-center`, `pt-12px` (`pt-3`), `mt-12px`, 1px top border (dark `gray-700` #374151).
  - Left: text-[9px], font-black, muted, uppercase, tracking-widest.
    - Active: "Original ₹{amount.toFixed(0)}". Cleared: "Closed {MMM dd}" (e.g. "Closed OCT 10").
  - Right (flex, gap 8px):
    - **Creator, active:**
      - Edit: ghost sm, h-28px (`h-7`), w-28px (`w-7`), p-0. Icon `Pencil` 12px (h-3 w-3). Disabled while deleting. Opens edit sheet.
      - Delete: destructive, icon size, h-28px w-28px. Icon `Trash2` 12px. While deleting: spinner `Loader2` 12px. Opens AlertDialog:
        - Title "Delete Entry?"
        - Body: "This will remove this item from your records."
        - Cancel: "Cancel". Confirm: "Delete" (bg destructive).
      - Settle: sm, h-28px, px-12px, text-[10px], uppercase, tracking-widest, font-black, bg `blue-500` #3B82F6 hover `blue-600` #2563EB, shadow-lg with `blue-500/20`. Icon `Clock` 12px (h-3 w-3), mr-4px. Text "Settle". Disabled when remaining <= 0.01 or deleting.
    - **Recipient, active:**
      - "View Details" button: sm, outline, h-28px, px-12px, text-[10px], font-black, uppercase, tracking-widest.
    - **Cleared:** no buttons.

### Pending card: split (`PendingSplitCard`)
- Card: `p-4` (16px), `border-l-4`, `rounded-2xl`, hover shadow-lg, cursor-pointer. Tap opens Split Breakdown sheet.
  - Border: cleared `green-500/30`; active debt `destructive`; active receive `green-500`.
- Left icon chip: 40x40px, rounded-xl. Icon `Users` 20px.
  - Cleared debt: bg destructive/10, icon destructive. Cleared receive: bg green-500, icon white.
  - Active debt: bg destructive/10, icon destructive. Active receive: bg green-500/10, icon `green-600`.
- Title: text-sm font-bold capitalize, tracking-tight.
  - Cleared debt: "Settled with {creator}" ; cleared receive: "Split fully settled".
  - Active creator: "you will receive shares from group".
  - Active participant: "you have to send to {creator}".
  - Fallback creator name "Organizer".
- Subline: text-[10px], muted, uppercase, italic, truncate, tracking-tight. Notes or "Group Expense".
- Amount: text-lg font-black tracking-tighter, sign + ₹ icon + number 0 dp.
  - Participant (not creator): shows my share amount.
  - Creator active: remaining group due. Cleared: group total.
- Badge: outline, text-[8px], font-black, uppercase, h-16px, px-4px, mt-4px.
  - Cleared: "Cleared". Active: "{n} Pending" (count of shares with status PENDING).
- Footer row: flex, space-between, `pt-12px` (`pt-3`), `mt-12px`, border-top 1px.
  - Left text-[9px], font-black, muted, uppercase, tracking-widest:
    - Creator: "Group Total: ₹{total.toFixed(0)}".
    - Participant: "Your specific portion".
  - Right (gap 8px):
    - **Creator, active:**
      - Edit: ghost sm, h-28px w-28px p-0, icon `Pencil` 12px. Opens split edit sheet.
      - "Manage": sm, h-28px, px-12px, text-[10px], uppercase, tracking-widest, font-black, bg `blue-500`, hover `blue-600`, shadow-lg `blue-500/20`. Opens settle drawer.
    - **All users, active or cleared:** "Details" button: sm, outline, h-28px, px-12px, text-[10px], font-black, uppercase, tracking-widest.

**Manage / Settle Shares drawer:**
- Drawer height **70vh**, max-w-md, inner `p-4`, flex column.
- Title (text-xl, font-black): "Settle Shares".
- Description (text-xs): "Mark participants as paid when they return their share."
- List `space-y-3` (12px), pb 32px. Each pending share row:
  - Row: flex, space-between, items-center, `p-3` (12px), 1px border, rounded-xl 12px, bg `muted/20`.
  - Left: name (text-sm, font-black, uppercase, tracking-tight, block). Subline text-[10px], font-bold, muted, uppercase: "Owing you money".
  - Right (gap 12px): amount `₹{amount.toFixed(0)}` (font-black, `green-600`). Button "Paid": sm, h-32px (`h-8`), rounded-lg 8px, font-black, uppercase, text-[10px], tracking-wider. Spinner when processing. Disabled while any is processing.
- Toasts: "Settled with {name}." / "Failed to settle."

### Split details sheet (`SplitDetailsSheet`)
Drawer height **85vh** mobile, **80vh** md+. Max-w-md.

- Header (`px-4 py-3` (16px / 12px), border-bottom 1px, flex-shrink 0, relative, text-left):
  - Left row (flex, gap 8px): icon `Users` 20px (h-5 w-5), primary.
  - Text: Title (text-lg, 18px) "Split Breakdown". Under it, sub-label (text-[10px], font-black, uppercase, tracking-widest):
    - Owes: "You have to send to {name}" in destructive.
    - Receives: "You will receive from {name}" in `green-600`.
    - Name fallbacks: "group members" (creator view) / "Organizer".
  - Close button: ghost 32x32, top 8px, right 8px. Icon `X` 16px.

- Scroll body (`px-4`, inner `space-y-6` (24px), py-16px, pb-48px):
  1. **Summary card**: `p-4` (16px), bg `muted/50`, rounded-2xl 16px, 1px border, space-y-4 (16px).
     - Row (flex, space-between, items-end):
       - Left (space-y-0.5):
         - Label "Remaining Group Due": text-[9px], font-black, muted-foreground, uppercase, tracking-widest.
         - Value h3: text-3xl (30px), font-black, tracking-tighter. Color destructive if remaining > 0.01, else `green-600`. `₹` + counter (0 dp).
       - Right (text-right):
         - Label "Total Value": same label style.
         - Value: text-sm (14px), font-bold, `₹{total.toLocaleString()}`.
     - Bar: h-6px (`h-1.5`), w-full, bg muted, rounded-full, overflow hidden. Fill: `bg-primary`, width = paid / total %, transition-all 1000ms. Note: no cap in style (use min(100%) in Flutter).
  2. **Participant Shares** section (`space-y-3`):
     - Heading h4: text-[10px], font-black, uppercase, tracking-widest, muted, flex, gap 8px. Icon `User` 12px (h-3 w-3). Text "Participant Shares".
     - Rows (`space-y-2` = 8px): each share row flex, space-between, items-center, `p-3` (12px), 1px border, rounded-xl 12px, bg `card`.
       - Left: name (text-sm, font-bold, truncate). Date text-[9px], muted, uppercase, font-medium, "MMM dd, yyyy".
       - Right (text-right):
         - Amount: text-sm, font-black. `green-600` if PAID, else destructive. Format `₹{amount.toFixed(0)}`.
         - Status badge: outline, text-[8px], h-14px (`h-3.5`), px-4px, uppercase, font-black, tracking-tighter. Text = raw status: "PAID" or "PENDING" or "PARTIAL_PAID".

- Empty: none specified (sheet returns null if no group).

### Payment / Record Settlement sheet (`PendingPaymentSheet`)
Drawer height **85vh** mobile, **75vh** md+. Max-w-md, flex column.

- Header (`flex-shrink-0`, relative, border-bottom 1px, text-left):
  - Row (gap 8px, mb-4px): icon `Clock` 20px (h-5 w-5), primary. Title (text-xl, font-black, uppercase, tracking-tight): "Record Settlement".
  - Description (font-black, uppercase, text-[10px], tracking-widest): perspective line.
    - Owes: "you have to send to {name}" (destructive `#EF4444`).
    - Receives: "you will receive from {name}" (`green-600`).
  - Close: ghost 32x32, rounded-full, top 16px right 16px, `X` 16px.

- Scroll body (`px-4`, inner `space-y-6` (24px), py-24px, pb-48px):
  1. **Summary card**: `Card` with `p-4`, `border-none`, `shadow-sm`, relative overflow hidden. Bg:
     - Owes: `bg-rose-500/10` (10% #F43F5E).
     - Receives: `bg-emerald-500/10` (10% #10B981).
     - Top row (`pb-12px`, border-bottom 1px at 5% black/white, z-10, flex, space-between, items-center):
       - Label "Original Total": text-[10px], font-black, uppercase, tracking-widest, muted.
       - Value `₹{original.toLocaleString()}`, font-bold.
     - Bottom row (`pt-16px`, items-end, flex, space-between):
       - Left (space-y-0.5):
         - Label "Remaining Due": text-[10px], font-black, uppercase, tracking-[0.2em], muted.
         - Value h3 text-3xl (30px), font-black, tracking-tighter. Destructive if owes, else `green-600`. `₹` + counter (0 dp).
       - Right (only if owes): text-right, label "Available Cash" (text-[9px], font-black, muted, uppercase, tracking-widest, mb-2px); value `₹{balance.toLocaleString()}` text-xs font-black.

  2. **Settlement form** (only when remaining > 0.01). Wrapper `space-y-5` (20px), slide-in-from-bottom-4 + fade-in animation.
     - **Payment Amount (INR)** (label text-[10px], font-black, uppercase, tracking-widest, muted, ml-4px):
       - Input: `pl-10`, h-56px (`h-14`), text-2xl (24px), font-black, rounded-2xl 16px, **border-2**, focus ring primary. Type number, step 1, inputMode decimal. Icon `IndianRupee` 20px (h-5 w-5), left-12px.
       - Note: the label says "INR" (not ₹).
     - **Quick mode toggle** (`grid grid-cols-2 gap-3` = 12px), two buttons each h-48px (`h-12`), rounded-xl 12px, font-black, uppercase, text-[10px], tracking-widest:
       - "Full Settlement": variant default when active, outline when not. On click: sets amount to ceil(remaining).
       - "Partial Payment": default when active, outline when not. On click: sets mode to partial (amount not changed).
     - **Notes** (label same style): Input placeholder "Optional reference...", h-48px, rounded-xl 12px, border-2.
     - Submit: full width, h-56px, text-base (16px), font-black, uppercase, tracking-widest, rounded-2xl 16px, shadow-xl `shadow-primary/20`.
       - Idle icon `CheckCircle` 20px, mr-8px. Text "Commit Settlement".
       - Disabled when submitting or amount <= 0. Spinner while submitting.
  3. **Fully Settled state** (remaining <= 0.01):
     - Wrapper: centered, `py-48px` (py-12), `space-y-4` (16px).
     - Circle: 64x64px (`w-16 h-16`), bg `green-500` #22C55E, rounded-full, white check icon 32px, shadow-lg `green-500/20`.
     - Title: "Fully Settled", text-xl (20px), font-black, uppercase, tracking-tight.
     - Body: "This transaction has no remaining due amount.", text-sm, muted, font-medium.
     - Button: outline, full width, h-48px (`h-12`), rounded-xl 12px, font-bold. Text "Close Window".

- Toasts: success "Payment recorded! Balance updated."; insufficient (owes): "Insufficient balance. You have ₹{balance.toFixed(0)} available."; failure: server message or "Failed to record payment."
- Default amount on open = ceil(remaining). Notes default when empty: "Full Settlement" (if full) or "Partial Payment".
- Validation: "Amount must be greater than zero."

### Edit pending item sheet (`PendingFormSheet`)
Drawer height **90vh** mobile, **80vh** md+. Max-w-md.

Three alternate states:
1. **Partial payment entry** (cannot edit): drawer height **40vh**, centered content `p-32px` (p-8), text-center.
   - Icon `AlertTriangle` 32px (h-8 w-8), destructive, mx auto.
   - Title "Cannot Edit Payment Entry" (text-lg, font-semibold, mt-16px).
   - Body "This is a partial payment record. Only the main pending item can be edited or deleted." (text-muted-foreground).
   - Button "Close", full width? (default size), mt-16px.
2. **Read-only (other user's item)**: drawer height **60vh**, `p-16px` content.
   - Title "View Pending Item" (text-2xl).
   - Description: "This item was created by another user and is read-only."
   - Close X button (top 16px right 16px).
   - Summary box: `p-4`, bg `muted`, rounded-lg 8px, space-y-4 (16px). Rows (text-sm, font-medium, gap 8px):
     - `Pencil` 16px muted + person name.
     - `IndianRupee` 16px muted + "Amount: ₹{amount.toFixed(2)}".
     - `Clock` 16px muted + "Status: {status}" (text-sm, muted-foreground).
   - Button "Close", full width, mt-24px.
3. **Edit / Add** (standard): see below.

**Standard header:**
- Title (text-2xl): "Edit Pending Item" or "Add Pending Item".
- Description: "Update details for this outstanding financial item."
- Close X: ghost 32x32, top 16px right 16px.

**Scroll body** (`px-4`, form `space-y-6` 24px, pb 24px):

1. **Transaction Type** (radio group):
   - Label "Transaction Type".
   - Row, `space-x-4` (16px). Each option label flex, gap 8px, cursor pointer.
   - Native radio (`form-radio text-primary`). Labels: "Send" (value expense), "Receive" (value income). Disabled in edit mode.

2. **Person's Name**
   - Label "Person's Name" (htmlFor personName).
   - Input: `pl-10`, placeholder "e.g., John Doe, Client Name". Left icon `User` 16px. Disabled when read-only or item linked to an app user.
   - Error: "Please enter the person's name."

3. **Original Amount**
   - Label "Original Amount".
   - Input: `pl-10 text-lg h-12`, type number, step 0.01, placeholder "0.00", inputMode decimal. Icon `IndianRupee` 16px. Disabled when read-only.
   - Error: "Amount must be greater than zero."

4. **Date Created**
   - Label "Date Created".
   - Button outline, full width, left-aligned, font-normal, icon `CalendarIcon` 16px. Text `PPP` or "Pick a date". Disabled when read-only.
   - Calendar popover.

5. **Notes (Optional)**
   - Label "Notes (Optional)".
   - Textarea placeholder "e.g., Dinner bill, Loan repayment, Gift". Disabled when read-only.

**Footer** (`p-4`, border-top 1px, bg background):
- Row, gap 16px.
  - Save: flex-1, h-48px, text-lg. Icon `Save` 20px, mr-8px. Text "Save Changes". Spinner while submitting (not deleting). Disabled when submitting or read-only.
  - Delete (edit mode only): destructive icon, h-48px, w-48px. Icon `Trash2` 20px. Spinner while deleting. Disabled when submitting or read-only.
    - AlertDialog:
      - Title "Delete Pending Item?"
      - Body "This action will permanently delete this pending item and all related partial payments."
      - Cancel "Cancel" (disabled while deleting).
      - Confirm "Delete Everything" (bg destructive, hover destructive/90). Spinner while deleting.

**Toasts:** update success "Pending item for {name} updated successfully!"; delete success "Pending item for {name} deleted successfully."; update failure "Failed to update transaction."; delete failure "Failed to delete transaction."; missing data "Transaction data missing."

### Add pending sheet (`AddPendingSheet`)
Drawer height **90vh** mobile, **80vh** md+. Max-w-md, flex column. Has two modes:
- Create (both tabs visible).
- Edit: single-item edit is not separate here; edit of a split opens this sheet in split-edit mode (no tab bar). Header title "Edit Item", description "Modify split group details.".

**Header:**
- Title (text-2xl): "Add Pending Item" (create) or "Edit Item" (edit).
- Description (text-sm): "Record unsettled transactions." (create) or "Modify split group details." (split edit).
- Close X: ghost 32x32.

**Tabs** (create only), `px-4 pb-8px` wrapper, TabsList grid grid-cols-2 (default h-40px):
- "Single User" | "Split Expense".
- Split edit opens directly on "split" tab with no tab bar.

### Single User tab (`TabsContent`, mt-0, pb-40px)
Form `space-y-6` (24px), pt-8px.

1. **Transaction Type** (label "Transaction Type", radios, `space-x-5` = 20px gap):
   - "Send (I Owe)" (value expense).
   - "Receive (They Owe Me)" (value income).

2. **Recipient Type** (label "Recipient Type"):
   - Grid 2 columns, gap 8px. Two buttons h-36px (`h-9`):
     - "Non-App User" (default when selected, outline otherwise). Default selected.
     - "App User".

3a. **If Non-App User**:
   - Label "Person's Name" (htmlFor name). Input `pl-10`, placeholder "e.g., John Doe", left icon `User` 16px.
   - Error: "Please enter the person's name."

3b. **If App User**: user search selector (see below).

4. **Amount (₹)** (label, htmlFor amount):
   - Input: `pl-10 text-lg h-12`, type number, step 0.01, min 0.01, placeholder "0.01", inputMode decimal. Icon `IndianRupee` 16px. Blocks "-" and "e".
   - Error: "Amount must be greater than zero."
   - If type = Receive (income): row, flex, justify-between, text-xs, mt-4px:
     - Label "Available Cash:" (muted-foreground).
     - Value `₹{balance.toFixed(2)}`, font-bold. Green-600 normally; destructive if this amount exceeds balance.
   - If amount exceeds balance (income only): line text-xs, destructive, mt-4px, flex, items-center, with `AlertTriangle` 12px (h-3 w-3, mr-4px). Text "Amount exceeds available balance.". Submit disabled.

5. **Date** (label htmlFor date):
   - Button outline, full width, left-aligned, font-normal. Icon `Calendar` 16px (mr-8px). Text `PPP` or "Pick a date" (muted).
   - Calendar popover.

6. **Notes (Optional)**: Textarea placeholder "Details...".

7. **Submit**: full width, h-48px, text-lg. Icon `Save` 20px mr-8px. Text "Save Item". Spinner while submitting. Disabled when submitting, app user not selected, or amount exceeds balance.

Validation toasts: "Amount must be greater than zero." / "Please select an app user." / "Insufficient balance. You have ₹{balance.toFixed(2)} available." / success "Pending transaction recorded! Balance updated." / failure "Failed to save transaction."

### Split Expense tab (`TabsContent`, mt-0, pb-40px)
Form `space-y-6`, pt-8px.

1. **Total Expense (Paid by You)** (label htmlFor totalAmount):
   - Input: `pl-10 text-lg h-12`, type number, step 0.01, min 0.01, placeholder "0.01", inputMode decimal. Icon `IndianRupee` 16px. Blocks "-" and "e".
   - Error: "Total amount must be greater than zero."
   - Row (flex, space-between, text-xs, mt-4px):
     - "Available Cash:" (muted). Value `₹{balance.toFixed(2)}` font-bold, green-600 normally, destructive if over.
   - If over balance: line text-xs destructive, mt-4px, flex items-center, `AlertTriangle` 12px. Text "Insufficient balance to cover this split.".

2. **Add Participants** (label):
   - Search input: `pl-10`, placeholder "Start typing username (min 3 chars)...". Icon `Search` 16px left. Spinner `Loader2` 16px (right-12px, primary, spinning) while searching.
   - Results: shown only when query length >= 3. Box `ScrollArea h-40px` (`h-40` = 160px), 1px border, rounded-lg 8px, mt-8px. Inner `p-2`, `space-y-1` (4px).
     - Loading: centered row py-16px, text-sm muted, spinner `Loader2` 16px mr-8px, text "Searching...".
     - Result row: button full width, flex, items-center, `p-2` (8px), rounded-lg 8px, hover bg `accent/50`, transition-colors 150ms, text-left.
       - Icon `User` 16px mr-12px, muted.
       - Name block (flex-1, min-w-0): username (text-sm, font-medium, truncate). Display name below (text-xs, muted, truncate).
       - Right icon: if already added, `CheckCircle` 16px `green-500`; else `Plus` 16px primary. Row disabled when already added.
     - Empty: centered py-16px, text-sm, muted: "No users found matching search."

3. **Split Mode** (label "Split Mode"):
   - Grid 2 columns, gap 8px. Buttons h-36px:
     - "Equal" (default variant when active, outline otherwise).
     - "Manual".

4. **Participants (N)** (label font-semibold, `Participants ({count})`):
   - List `space-y-2` (8px). Each row: flex, items-center, gap 12px, `p-2` (8px), bg `muted` (#F1F5F9), rounded-lg 8px.
     - Name: flex-1, text-sm, font-medium, truncate. Current user shows "You"; others show name.
     - Share input wrapper: w-96px (`w-24`), relative.
       - Icon `IndianRupee` 12px (h-3 w-3), left 8px.
       - Input: h-32px (`h-8`), `pl-6` (24px), text-sm, step 0.01, min 0, inputMode decimal. Blocks "-" and "e". **Read-only in Equal mode.**
   - Summary box (only when total > 0): `p-3` (12px), rounded-lg 8px, 1px border, text-sm.
     - Valid: border `green-500` #22C55E, bg `green-50/50` (#F0FDF4 at 50%).
     - Invalid: border destructive, bg `red-50/50` (#FEF2F2 at 50%).
     - Row (flex, space-between, font-semibold): "Sum: ₹{sum.toFixed(2)}" left, "Total: ₹{total.toFixed(2)}" right.
     - If invalid and mode is Manual: text-xs, destructive, mt-4px: "Difference: ₹{remaining.toFixed(2)}".

5. **Submit row** (flex, gap 16px):
   - Save: flex-1, h-48px, text-lg. Icon `Save` 20px, mr-8px. Text "Save Split" (create) or "Update Split" (edit). Spinner while submitting. Disabled when submitting, Manual sum invalid, fewer than 2 participants, or exceeds balance.
   - Delete (edit split only): destructive, icon, h-48px w-48px. Icon `Trash2` 20px.
     - AlertDialog: title "Delete Entire Split?". Body "This will remove all shares and related payments for this group expense.". Cancel "Cancel". Confirm "Delete Split" (bg destructive).

**Split validation toasts:**
- "Total split amount must be greater than zero."
- "Add at least one other participant."
- "Shares must sum up to the total amount."
- "Insufficient balance."
- Success: "Split recorded! Balance deducted by ₹{total.toFixed(2)}." (create) / "Split updated!" (edit). Failure: "Failed to save split."
- Delete: success "Split deleted successfully." / failure "Failed to delete split."

**Split behavior:**
- Equal mode: each share = total / participants, rounded to 2 dp, auto-updated.
- Manual mode: user edits shares; must sum to total within 0.01.
- Current user included as "Me" (displayed as "You") and is excluded from shares saved.
- Edit: rebuilds group (delete + recreate under same group id).

### User search selector (`UserSearchSelector`, single user tab when App User)
- **Selected state:**
  - Label "Recipient (App User)".
  - Row: `p-3` (12px), bg `green-50/50`, 1px border `green-200` #BBF7D0, rounded-lg 8px, flex, space-between, items-center.
    - Left (gap 12px): `CheckCircle` 20px (h-5 w-5), `green-600`. Name: username or display name, font-medium.
    - Right: ghost icon button 40x40px, `X` 16px. Clears selection.
- **Search state:**
  - Label "Search App User by Username" (htmlFor username-search).
  - Input wrapper relative. Icon `Search` 16px left-12px, muted. Input: `pl-10`, placeholder "Start typing username (min 3 chars)...". Spinner `Loader2` 16px right-12px, primary, spinning while searching.
  - Results (when query >= 3 chars): ScrollArea h-160px, 1px border, rounded-lg 8px, mt-8px, inner `p-2 space-y-1`.
    - Loading: "Searching..." with spinner (same as above).
    - Results: buttons as in the Split tab (User icon 16px, username text-sm font-medium, display name text-xs muted). Hover `accent/50`.
    - Current user filtered out.
    - Empty: "No users found matching search." (text-sm, muted, py-16px centered).

### Visual states summary (Pending)
- Card left border: destructive (I owe, active), green-500 (I receive, active), green-500/30 (cleared).
- Settle button only enabled when remaining > 0.01.
- Count badge in tab: "Active (N)".
- Group type filter: All / Single / Splits.
- Search matches on person name, notes, or amount string (case-insensitive).
- Grouping: single items and split groups keyed by split group id or parent id. Active = remaining > 0.01 (sorted newest first). Cleared = remaining <= 0.01 (filtered by selected month, sorted newest first).
- Date headers are sorted newest first.

---

## Cross-cutting Flutter notes

- **Gradient cards:** `LinearGradient(begin: topLeft, end: bottomRight)` for `bg-gradient-to-br`; `LinearGradient(begin: centerLeft, end: centerRight)` for `bg-gradient-to-r`.
- **Opacity colors:** `bg-white/20` = `Colors.white.withOpacity(0.2)`. `bg-black/10` = black 10%.
- **Shadows:** `shadow-sm` ≈ 0 1px 2px rgba(0,0,0,0.05). `shadow-md` ≈ 0 4px 6px -1px rgba(0,0,0,0.1). `shadow-lg` ≈ 0 10px 15px -3px rgba(0,0,0,0.1). `shadow-xl` ≈ 0 20px 25px -5px rgba(0,0,0,0.1). `shadow-2xl` ≈ 0 25px 50px -12px rgba(0,0,0,0.25). Colored shadows (`shadow-blue-500/20`, `shadow-violet-500/20`, `shadow-primary/20`) use the color at that alpha.
- **Transitions:** 300ms standard for hover/scale. Progress fill 1000ms ease. Shadow on hover 300ms.
- **Scale on press:** `active:scale-[0.98]`.
- **Inputs:** number inputs block "-" and "e" keys. Amounts clamp to >= 0.
- **Icons:** all `lucide` (Flutter: use the matching Material/Cupertino icon or a Lucide port). Names listed above are exact.
- **Currency:** prefix `₹`. Counters count from 0 on show.
- **Dates:** `PPP` renders like "Oct 10th, 2026". `MMM dd, yyyy` renders "Oct 10, 2026". `EEEE, MMM dd` renders "Friday, Oct 10".

---



## Conventions and assumptions

- Tailwind px: 1 unit = 4px. p-1.5=6, p-2=8, p-2.5=10, p-3=12, p-4=16, p-5=20, p-6=24, p-8=32, pt-20=80, pb-20=80, pb-32=128, gap-2=8, gap-3=12, gap-4=16, space-y-2=8, space-y-4=16, space-y-6=24, space-y-12=48.
- Radius: rounded-md=6, rounded-lg=8, rounded-xl=12, rounded-2xl=16, rounded-[1.25rem]=20, rounded-[2rem]=32, rounded-full=9999.
- Font sizes (Tailwind default line-heights): text-[8px]/[9px]/[10px]/[13px] are literal px; text-xs=12/16, text-sm=14/20, text-base=16/24, text-lg=18/28, text-xl=20/28, text-2xl=24/32, text-3xl=30/36, text-4xl=36/40, text-5xl=48/1, text-6xl=60/1.
- Weights: font-medium 500, font-semibold 600, font-bold 700, font-extrabold 800, font-black 900.
- Tracking: tracking-tighter -0.05em, tracking-tight -0.025em, tracking-wider 0.05em, tracking-widest 0.1em, tracking-[0.2em].
- Not read in this pass (values assumed, verify in src/components/ui and src/index.css): shadcn Button default h-10 px-4 rounded-md; `size="icon"` = 40x40; Input h-10 rounded-md border; Label text-sm font-medium; Card rounded-lg bg-card; Progress track bg-primary/20; Drawer handle and top radius; AnimatedCounter; EmptyState; theme tokens (`primary`, `background`, `muted`, `muted-foreground`, `border`, `destructive`, `card`, `foreground`) which live as CSS variables in index.css. Light and dark token values must be read from there.
- Hex values below are Tailwind v3 default palette values.

### Tailwind hex reference used on these screens

| Name | Hex |
|---|---|
| zinc-100 | #f4f4f5 |
| zinc-400 | #a1a1aa |
| zinc-950 | #09090b |
| stone-100 | #f5f5f4 |
| stone-200 | #e7e5e4 |
| stone-300 | #d6d3d1 |
| stone-400 | #a8a29e |
| stone-500 | #78716c |
| stone-600 | #57534e |
| stone-700 | #44403c |
| stone-800 | #292524 |
| stone-900 | #1c1917 |
| stone-950 | #0c0a09 |
| emerald-100 | #d1fae5 |
| emerald-400 | #34d399 |
| emerald-500 | #10b981 |
| emerald-600 | #059669 |
| emerald-700 | #047857 |
| emerald-800 | #065f46 |
| emerald-950 | #022c22 |
| green-100 | #dcfce7 |
| green-200 | #bbf7d0 |
| green-400 | #4ade80 |
| green-500 | #22c55e |
| green-600 | #16a34a |
| green-700 | #15803d |
| blue-50 | #eff6ff |
| blue-100 | #dbeafe |
| blue-400 | #60a5fa |
| blue-500 | #3b82f6 |
| blue-600 | #2563eb |
| blue-700 | #1d4ed8 |
| blue-950 | #172554 |
| indigo-50 | #eef2ff |
| indigo-950 | #1e1b4b |
| violet-500 | #8b5cf6 |
| violet-600 | #7c3aed |
| purple-50 | #faf5ff |
| purple-500 | #a855f7 |
| pink-100 | #fce7f3 |
| pink-500 | #ec4899 |
| pink-950 | #500724 |
| purple-950 | #3b0764 |
| orange-100 | #ffedd5 |
| orange-500 | #f97316 |
| amber-50 | #fffbeb |
| amber-100 | #fef3c7 |
| amber-200 | #fde68a |
| amber-500 | #f59e0b |
| amber-600 | #d97706 |
| amber-800 | #92400e |
| amber-950 | #451a03 |
| yellow-100 | #fef9c3 |
| yellow-500 | #eab308 |
| yellow-700 | #a16207 |
| yellow-800 | #854d0e |
| red-100 | #fee2e2 |
| red-400 | #f87171 |
| red-600 | #dc2626 |
| red-700 | #b91c1c |
| red-950 | #450a0a |
| rose-400 | #fb7185 |
| rose-500 | #f43f5e |
| sky-600 | #0284c7 |
| slate-600 | #475569 |
| gray-50 | #f9fafb |
| gray-950 | #030712 |

---

## Login & OTP

### Login (/login)

**Page shell**
- Root: `p-3 pt-6 flex flex-col items-center min-h-screen`, background `gray-50` (#f9fafb) light, `gray-950` (#030712) dark. Padding 12px sides, 24px top.
- Loading gate (auth still resolving): full block `p-8 text-center`, 32px padding, text muted-foreground, copy: `Loading authentication...`.
- If already signed in, redirect to `/`.

**Card**
- `w-full max-w-md` (max width 448px). Mobile: `shadow-xl`, `border-none`. md and up: `border` (1px, border token) and `shadow-md`.
- Header `text-center pb-4` (16px bottom).
  - Title: `FINN`, text-3xl (30px/36px), font-bold, color primary.
  - Subtitle: `Sign in or Sign up with Email OTP`, text-sm (14px), muted-foreground.
- Content: form `space-y-6` (24px gap).

**Email field**
- Label: `Email Address` (shadcn Label, assumed text-sm 14px font-medium), `htmlFor="email"`. Label to input gap `space-y-2` (8px).
- Input wrapper `relative`. Icon: `Mail` (lucide), 16x16, `absolute left-3` (12px), vertically centered, muted-foreground.
- Input: type `email`, placeholder `you@example.com`, class `pl-10` (left padding 40px so text clears icon). Height assumed h-10 (40px).
- Error (only after failed validation): text-sm (14px) destructive color, `mt-1` (4px). Copy: `Invalid email address.`
- Validation: required and must be a valid email (zod `.email()`), checked on submit (react-hook-form default mode, so error shows after first submit attempt).

**Primary button**
- Full width, `h-10` (40px tall), default primary style (shadcn default, assumed rounded-md 6px).
- Label: `Send Verification Code`.
- Submitting state: label replaced by `Loader2` spinner at 20x20 (`h-5 w-5`), `animate-spin`. Button disabled while submitting.

**Toasts (top, shadcn/sonner toast)**
- Success: `Verification code sent! Check your email.`, then navigate to `/verify-otp?email=<url-encoded email>`.
- Provider error: shows the provider's error message as-is.
- Unexpected exception: `An unexpected error occurred.`

**States**
- Default, validation error (red line under field), submitting (spinner in button, button disabled).
- No empty state, no loading skeleton beyond the auth gate.

### Verify OTP (/verify-otp?email=...)

**Guards**
- No `email` query param: redirect to `/login`.
- Auth still loading: `Loading...` centered, 32px padding, muted.
- Already signed in: redirect to `/`.
- Email present but invalid request state: `Invalid request.` centered, muted.

**Shell**
- Same shell as Login (`p-3 pt-6`, gray-50 / gray-950 background, card `max-w-md`, `shadow-xl` / md `border shadow-md`).
- Header `text-center pb-4`. Title: `Verify Account`, text-3xl (30px) font-bold primary.

**Pending state (default)**
- Content form, `space-y-6` (24px).
- Top block `text-center space-y-2` (8px):
  - Icon `Mail`, 32x32, primary color, centered.
  - Heading `Enter Verification Code`, text-xl (20px) font-bold, foreground.
  - Body text-sm (14px) muted: `We sent a 6-digit code to ` + email in `font-medium text-primary` span + `.`
- OTP input: container `flex justify-center`. `InputOTP` with maxLength 6, disabled while verifying.
  - Layout: group of 3 slots, then a `-` separator in a `mx-2` (8px side margin) div, then group of 3 slots.
  - Slot styling from `components/ui/input-otp` (not read; assumed 40px-ish square, border, rounded-md, focus ring).
- Primary button `w-full h-10`: label `Verify Code`. Disabled until exactly 6 digits entered or while verifying. Verifying state shows `Loader2` 20x20 spinner in place of label.
- Below button, centered: text button variant `link`, label `Resend Code`, disabled while verifying.

**Pending-state toasts**
- Code not 6 digits when submitted: `Please enter the 6-digit code.` (button is disabled, so this is mostly unreachable).
- Success: `Verification successful! Welcome to FINN.` Then status switches to success.
- Verify returned no session: `Verification failed. Please check the code and try again.` Status switches to error.
- Provider error: provider message text as-is. Status switches to error.
- Unexpected exception: `An unexpected error occurred during verification.`

**Resend**
- Success toast: `New OTP sent! Check your inbox.`
- Failure: provider message, or `Failed to resend OTP.` on exception.

**Success state**
- Centered `space-y-4` (16px).
  - `CheckCircle` 48x48, green-500 (#22c55e).
  - Heading `Verification Complete!` text-2xl (24px) font-bold green-600 (#16a34a).
  - Body muted: `You are now signed in. Redirecting to the dashboard...`
- Auto-redirect to `/` (replace) after 1000ms.

**Error state**
- Centered `space-y-4`.
  - `AlertTriangle` 48x48, destructive color.
  - Heading `Verification Failed` text-2xl bold destructive.
  - Body muted: `The code was invalid or expired. Please try signing in again.`
  - Button variant `outline`, label `Go to Login`, navigates to `/login`.
- Note: error is terminal in this screen. Changing the code does not return to pending state. The only way out is `Go to Login` (or Resend, which does not reset status).

**Logic that affects visuals**
- Verifying the code also tries to set the profile as activated. If that fails, it only logs and still shows success.
- Button enablement: `otp.length === 6`.

---

## Insights Screen

Route: Insights page (bottom-nav tab). Title `Spending Insights`. All amounts are in INR with `₹` prefix and `toLocaleString()` grouping (en-US style, e.g. `12,345`). Percentages are fixed decimals. Animated counters are described below.

### Page shell

- Root: `p-2 space-y-4 pt-3 pb-20`. Padding 8px sides, 12px top, 80px bottom (clears bottom nav). Vertical gap 16px between sections.

### Loading state

- Whole page replaced, `p-8 text-center pt-20` (32px padding, 80px top).
- `Loader2` 40x40 (`h-10 w-10`), primary color, spinning, centered.
- Text (mt-4 = 16px): `Crunching Numbers...`, muted, font-black, uppercase, tracking-widest.

### Header row
- Row `flex items-center justify-between`.
- Left group `flex items-center space-x-2` (8px gap):
  - `BarChart3` icon 20x20, primary.
  - Title `Spending Insights`: text-xl (20px) on mobile, md:text-2xl (24px); font-black; uppercase; tracking-tight.
- Right: ghost icon button, rounded-full, muted-foreground, default 40x40 (`size="icon"`), icon `HelpCircle` 24x24. Click dispatches `start-tour` (guided tour).

### Hero card (id tour-insights-hero)
- Card: `p-5` (20px padding), `shadow-2xl`, `border-none`, background `zinc-950` (#09090b), text white, `relative overflow-hidden`, radius `rounded-[2rem]` (32px).
- Content: `flex flex-col relative z-10`.
- Top row `flex justify-between items-start mb-2` (8px bottom):
  - Left column `space-y-0.5` (2px):
    - Label `Monthly Spending`: text-[10px] font-black uppercase tracking-[0.2em], color zinc-400 (#a1a1aa).
    - Amount: text-4xl (36px) on mobile, md:text-5xl (48px); font-black; tracking-tighter; white. Value = current-month expense, `₹` prefix, 0 decimals, animated count-up.
    - Change pill: `inline-flex items-center px-2 py-0.5` (8px x 2px), rounded-full, text-[10px] font-black, `mt-1.5` (6px) top margin.
      - If change <= 0%: `bg-emerald-500/20` (emerald-500 at 20%) with text `emerald-400` (#34d399). Icon `TrendingDown` 12x12, `mr-1` (4px).
      - Else: `bg-rose-500/20` with text `rose-400` (#fb7185). Icon `TrendingUp` 12x12.
      - Copy: `{abs(change).toFixed(1)}% vs last month`.
  - Right: icon tile 40x40, rounded-2xl (16px), `bg-white/10`, `backdrop-blur-md`, centered. Icon `Wallet` 20x20 colored blue-400 (#60a5fa).
- Divider: `h-[2px] w-full`, horizontal gradient from transparent to white/50 and back to transparent, `my-3.5` (14px vertical).
- Stats row `grid grid-cols-3 gap-4` (16px gap). Each cell `space-y-0.5`:
  - Left (left aligned): label `Income` (text-[9px] font-black zinc-400 uppercase tracking-widest); value `₹{income}` text-lg (18px) font-bold zinc-100.
  - Center (text-center): label `Net Saved`; value `₹{savings}` text-lg font-bold. Color emerald-400 if savings >= 0, rose-400 if negative.
  - Right (text-right): label `Rate`; value `{savingsRate.toFixed(1)}%` text-lg font-bold, colored by savings status (see below).

### Stat tiles (id tour-insights-stats)
- Grid `grid grid-cols-2 gap-3` (12px gap).
- Each tile: `Card p-3` (12px), background `muted/20` (muted at 20% opacity), default card radius (assumed rounded-lg 8px).
- Tile 1 (left): top row `flex items-center justify-between mb-1` (4px). Label `Savings Rate` text-[9px] font-bold muted uppercase. Right: Badge outline, `text-[8px] px-1 py-0 h-4` (16px tall), no border, font-black, colored with status color. Value below: `{rate.toFixed(1)}%` text-lg (18px) font-black, same status color.
- Tile 2 (right): label `Daily Burn`. Value `₹{avgDaily.toFixed(0)}` text-lg font-black, default foreground color. No badge.
- Tile 3 (full width, `col-span-2`): label `Lifestyle Ratio` with badge. Value `{discretionary%.toFixed(1)}%` text-lg font-black, colored by lifestyle status. Caption below, `mt-1` (4px): `Discretionary vs Total Spend`, text-[8px] font-bold muted uppercase.

Savings-rate status (badge label and color):
| Condition | Label | Color |
|---|---|---|
| rate >= 30 | Excellent | green-500 (#22c55e) |
| rate >= 20 | Good | blue-500 (#3b82f6) |
| rate > 0 | Fair | yellow-500 (#eab308) |
| otherwise | Negative | rose-500 (#f43f5e) |

Lifestyle-ratio status:
| Condition | Label | Color |
|---|---|---|
| discretionary % > 40 | High | rose-500 |
| otherwise | Balanced | green-500 |

Savings rate = (current-month net savings / income) * 100, clamped to -100..100. Shows 0 if income <= 0.

### Top Spending Categories (id tour-insights-categories)
- Card `p-4` (16px), `rounded-2xl` (16px).
- Title: text-xs (12px) font-black uppercase tracking-widest muted, `mb-4` (16px). Copy: `Top Spending Categories`.
- List `space-y-4` (16px). Each row `space-y-1.5` (6px):
  - Row top `flex justify-between items-center`:
    - Name: text-xs font-black uppercase tracking-tight.
    - Amount: text-xs font-black, `₹{value}`.
  - Progress bar: `h-1.5` (6px tall), track assumed primary/20. Fill color comes from each category's data `color` (per-category, not fixed).
- Shows up to top 5, sorted by value descending. Bar width = category / total of all categories.
- No empty copy. If there are no categories the card shows only its title.

### Payment Methods (id tour-insights-methods)
- Card `p-4 rounded-2xl`. Title: `Payment Methods` (same title style as above).
- Grid `grid grid-cols-2 gap-3` (12px).
- Tile: `p-3 bg-muted/30 rounded-2xl space-y-2` (8px), border transparent, on hover border `border` token.
  - Top row: icon 16x16 muted-foreground on left; percentage right: text-[10px] font-black, opacity 40%. Rounded to 0 decimals.
  - Name block: label text-[9px] font-black uppercase tracking-widest muted; amount `₹{value}` text-sm (14px) font-black italic.
  - Progress bar h-1 (4px), default track/fill.
- Icon by method name:
  - `UPI` → Smartphone
  - `Card` → CreditCard
  - `Cash` → Banknote
  - `Bank Transfer` → Building2
  - anything else → Wallet
- Share % = method total / sum of all methods in current month (PAID expenses only).
- No empty state copy. Empty means empty grid.

### Computations that drive visuals
- Current month expense: sum of PAID expenses in current month.
- Change vs last month: `(expense - prevExpense) / prevExpense * 100`. If prev is 0: +100% when expense > 0, else 0%.
- Daily burn: expense / today's day-of-month.
- Lifestyle (discretionary) keywords matched in category name (case-insensitive): dining, restaurant, coffee, shopping, entertainment, travel, games, movies, subscription, fun, luxury.
- Discretionary % = discretionary total / expense * 100 (0 if no expense).
- Net saved this month: contributions minus withdrawals in current month's savings ledger.

---

## Timeline / Story Screen

Route: Timeline page. Title `Timeline`, subtitle `Your Financial Story`. The screen is a vertical story: a month "chapter" header and a central spine with event cards alternating over it.

### Loading state
- Full screen `min-h-screen flex flex-col items-center justify-center p-8 text-center bg-background`.
- `BookOpen` 64x64 (`w-16 h-16`), primary at 50% opacity, `mb-4` (16px). Pulses scale 1 → 1.1 → 1 over 2s, infinite.
- Text: `Stringing your story...`, text-lg (18px) font-medium muted, `animate-pulse`.

### Page shell
- Root: `min-h-screen pb-32 relative overflow-hidden bg-background`. Bottom padding 128px.
- Content wrapper `p-4 pt-6 space-y-6` (16px sides, 24px top, 24px gap).
- Header wrapper `pt-2`:
  - `Timeline`: text-3xl (30px/36px), font-black, tracking-tighter.
  - `Your Financial Story`: text-sm (14px), font-bold, muted, uppercase, tracking-widest.

### Month navigator (sticky)
- Row `flex items-center justify-between px-3 sm:px-4 py-2` (12px sides mobile, 16px sm and up; 8px vertical).
- Background `bg-background/80` with `backdrop-blur-md`, `sticky top-0 z-40`, bottom border `border-b border-border/40`.
- Left and right: ghost icon buttons, `h-8 w-8` (32px), fully round, icons `ChevronLeft` / `ChevronRight` 16x16.
  - Disabled when there is no older month (left) or newer month (right). Disabled state is the default shadcn disabled style.
- Center label: `MMMM yyyy` format (e.g. `October 2026`). Text-sm (14px), font-bold, uppercase, tracking-widest, primary color. Animates on month change: slides from y -10px to 0 and fades in from opacity 0 to 1.
- Month list: all months that have events, plus the current month always included, sorted newest first. Default selection is the current month.

### Chapter area
- Wrapper `w-full max-w-md mx-auto px-1 mt-4` (max 448px, centered, 4px side padding, 16px top).
- Transition between months: fade (opacity 0 to 1 on enter, 1 to 0 on exit), mode "wait" (old fades out before new fades in).

**If the month has events:**

#### Chapter header (StoryChapter)
- Column `relative z-10 flex flex-col items-center text-center px-6 mb-4` (24px sides, 16px bottom). Enters from y -20 with fade.
- Icon tile: 48x48 (`w-12 h-12`), rounded-2xl (16px), centered, `mb-4` (16px), `shadow-sm`, 1px border in the theme color, and `animate-bounce` (Tailwind bounce: 1s loop, moves up 25% and back).
  - Background is theme `bg` (color at 10% opacity). Border is the theme color (name `border-<color>`). Icon 24x24 in theme color.
- Text block `space-y-1` (4px):
  - Month label, e.g. `OCTOBER 2026`: text-[10px] font-black uppercase tracking-[0.2em], muted-foreground at 60% opacity.
  - Chapter name: text-2xl (24px), font-black, tracking-tighter, leading-none, theme text color.
  - Summary, in quotes: text-sm (14px), font-medium, muted, `max-w-[200px]` (200px max, centered), leading-tight, `pt-2` (8px top).
- Count row `mt-6 flex items-center gap-2` (24px top, 8px gap):
  - Hairline `h-[1px] w-8` (32px wide), border color.
  - Label: `{n} Key Moments`, text-[9px] font-bold, muted, uppercase, tracking-widest. (Copy is always plural, even for 1: `1 Key Moments`.)
  - Hairline mirror.

**Chapter themes** (chosen by first matching rule, using counts of event types in the month):

| Priority | Rule | Name | Icon | Text / icon color | Tile background | Summary |
|---|---|---|---|---|---|---|
| 1 | any event with rarity MYTHIC | The Legendary Era | Sparkles | amber-500 #f59e0b | amber-500 at 10% | Significant milestones were achieved this month. |
| 2 | more than 2 events of type containing LOAN | The Debt Slayer | Scale | orange-500 #f97316 | orange-500 at 10% | Aggressive action taken against liabilities. |
| 3 | more than 1 event of type containing GOAL | The Visionary Path | Target | violet-500 #8b5cf6 | violet-500 at 10% | Future self is thanking you for these choices. |
| 4 | INCOME_RECEIVED count > EXPENSE_PAID count | The Wealth Spring | TrendingUp | green-500 #22c55e | green-500 at 10% | Your resources grew more than they flowed out. |
| 5 | EXPENSE_PAID count > 1.5 x INCOME_RECEIVED count | The Great Inflow | Zap | blue-500 #3b82f6 | blue-500 at 10% | Major investments and lifestyle shifts occurred. |
| default | none of the above | The Steady Stream | BookOpen | stone-500 #78716c | stone-500 at 10% | A balanced chapter in your financial story. |

Note: no event currently has a `rarity` field, so rule 1 never fires in practice.

#### Spine
- Absolutely positioned, `left-1/2 top-[180px] bottom-0 -translate-x-1/2 z-0` (starts 180px from top of chapter block, runs to bottom).
- Layers:
  - Soft shadow: full height, 6px wide, stone-900 at 5% opacity, 2px blur.
  - Main rod: 4px wide, full height, rounded-full, stone-300 (#d6d3d1) light / stone-800 (#292524) dark, side borders 1px stone-400 at 20% (dark stone-700 at 50%).
  - Hatch texture overlay: opacity 20% light / 40% dark. Diagonal stripes from `linear-gradient(45deg, transparent 45%, #57534e 45%, #57534e 55%, transparent 55%)` with tile size 4px x 8px.

#### Event list
- Wrapper `pt-8 space-y-12` (32px top, 48px gap between items).
- Each item (StoryItem) is a column, `relative flex flex-col items-center w-full z-10`.

**Date pill (above card)**
- Wrapper `relative z-20 mb-2` (8px bottom).
- Pill: `px-3 py-1` (12px x 4px), rounded-full, background `background/80` with `backdrop-blur-md`, 1px border (border token), `shadow-sm`, text text-[10px] font-bold uppercase tracking-wider, muted.
- Date format `MMM do` (e.g. `OCT 5TH`), uppercase via class.
- Connector below pill: 1px wide, 16px tall (`h-4`), stone-400 (light) / stone-600 (dark), centered.

**Event card**
- Enter animation (once, when scrolled into view, with 50px margin): opacity 0 to 1, scale 0.9 to 1, duration 0.4s each.
- Idle motion: continuous rotation (hanging pendulum feel) between `-angle` and `+angle` degrees, where angle is random per card in [1.0, 2.5]. Duration random in [3s, 7s], start delay random in [0s, 2s], ease in-out, infinite. Transform origin is top center.
- Container: `relative group cursor-pointer w-full flex justify-center`. Tap triggers light haptic and opens the detail sheet.
- Card body: `relative p-5` (20px padding), radius `rounded-[1.25rem]` (20px), text-center, `backdrop-blur-md`, `shadow-sm`, border 2px (color per theme), width `w-[85%]` of the column (85% of 448px max, so about 380px at max width).
  - Hover: `shadow-xl`, scale 1.02, transition 300ms on all properties.
- Hanging hole: absolute `-top-3` (12px above card top), centered, 24x24 box holding a 12px circle with 2px border stone-400 (dark stone-500) and transparent fill.
- Emoji: text-4xl (36px), md:text-5xl (48px). Margin `mb-3 mt-1` (12px bottom, 4px top). On hover scales to 1.1. Drop shadow subtle.
- Title: text-base (16px), font-bold, tracking-tight, leading-snug, `mb-1` (4px), theme text color.
- Description: text-xs (12px) on mobile, sm:text-sm (14px) from sm up. font-medium, opacity 90%, leading-relaxed, `px-4` (16px sides), `mb-3` (12px). Theme text color. Fades in from y +5 to 0 and opacity 0 to 0.9 with 0.2s delay, 0.5s duration.
- Amount pill row: `flex flex-row items-center justify-center gap-3 mt-2` (8px top).
  - Pill: inline-block, `px-3 py-1` (12px x 4px), rounded-full, background white at 60% (dark: black at 20%), backdrop blur md, font-bold text-sm, 1px border black at 5% (dark white at 10%), `shadow-sm`, theme text color.
  - Text: `₹` prefix, 0 decimals, count-up animation on mount.

**Event card theme colors** (`color` field from story engine). Border is 2px at 50% opacity of the 600 shade (so border-yellow-600/50 etc.), tile background is 500 shade at 15% (light) or 10% (dark), text is 700 (light) / 400 (dark), except neutral.

| Theme key | Border (light) | Shadow | Background light / dark | Text light / dark |
|---|---|---|---|---|
| celebration | yellow-600 @ 50% | yellow-500 @ 10% | yellow-500 @15% / @10% | yellow-700 / yellow-400 |
| success | green-600 @ 50% | green-500 @ 10% | green-500 @15% / @10% | green-700 / green-400 |
| warning | red-600 @ 50% | red-500 @ 10% | red-500 @15% / @10% | red-700 / red-400 |
| fun | pink-600 @ 50% | pink-500 @ 10% | pink-500 @15% / @10% | pink-700 / pink-400 |
| adventurous | orange-600 @ 50% | orange-500 @ 10% | orange-500 @15% / @10% | orange-700 / orange-400 |
| growth | indigo-600 @ 50% | indigo-500 @ 10% | indigo-500 @15% / @10% | indigo-700 / indigo-400 |
| neutral | stone-500 @ 50% (dark stone-400 @ 50%) | black @ 5% | stone-500 @10% both | stone-700 / stone-300 |
| vision | violet-600 @ 50% | violet-500 @ 10% | violet-500 @15% / @10% | violet-700 / violet-400 |
| victory | amber-600 @ 50% | amber-500 @ 20% | amber-500 @15% / @10% | amber-700 / amber-400 |
| asset | emerald-600 @ 50% | emerald-500 @ 10% | emerald-500 @15% / @10% | emerald-700 / emerald-400 |
| freedom | sky-600 @ 50% | sky-500 @ 10% | sky-500 @15% / @10% | sky-700 / sky-400 |

Unknown theme falls back to neutral.

#### Closing anchor
- Wrapper `relative z-10 flex flex-col items-center mt-16 pb-10` (64px top, 40px bottom). Gently bobs y 0 to +2 to 0 over 3s, infinite.
- Disc 48x48 (`w-12 h-12`), fully round, background stone-200 (dark stone-800), 4px border stone-300 (dark stone-700), shadow-xl.
- Icon `Anchor` 24x24, stone-500.

**If the month has no events (empty state)**
- Uses `EmptyState` (shared component, internals not read; styling overrides below).
  - Icon: `BookOpen`.
  - Title: `The line is empty`.
  - Description: `Add major events like buying assets or paying off debt to hang them on your timeline.`
  - Class overrides: `mt-12` (48px top), `bg-transparent`, border stone-300 at 30% (dark stone-700 at 30%).
- No spine, no chapter header, no anchor.

### Mood background (MoodBackground)
- Full-screen layer: `fixed inset-0 -z-10`, `transition-colors duration-1000` (color cross-fades over 1s).
- The page passes `positive` when the chosen month contains at least one event whose color is `celebration`. Otherwise `neutral`. (The code also defines `warning` and `fun`, but this screen never selects them.)

| Mood | Gradient light | Gradient dark | Ambient animation |
|---|---|---|---|
| positive | `bg-gradient-to-br` from emerald-100 @ 80% to blue-100 @ 80% (#d1fae5 to #dbeafe, slightly transparent) | from emerald-950 @ 40% to blue-950 @ 40% | scale 1 to 1.05 to 1, 10s, infinite, ease in-out |
| warning (not used here) | to-br from orange-100 @80% to amber-100 @80% | from red-950 @40% to amber-950 @40% | rotate 0, 0.5, -0.5, 0 deg; 5s |
| fun (not used here) | to-br from pink-100 @80% to purple-100 @80% | from pink-950 @40% to purple-950 @40% | y 0, -5, 0, 5, 0 px; 8s |
| neutral | `bg-gradient-to-b` from stone-100 (#f5f5f4) to stone-200 (#e7e5e4) | from stone-900 (#1c1917) to stone-950 (#0c0a09) | none |

### Event detail sheet (TimelineDetailSheet)
- Bottom drawer. Content `h-[80vh] md:h-[70vh] max-w-md mx-auto rounded-t-xl flex flex-col` (80% viewport height on mobile, 70% on md+, top corners 12px, max width 448px).
- Close button: ghost icon, `absolute right-4 top-4` (16px from edges), 32x32, `X` icon 16x16.
- Header: `text-center pb-2 pt-8` (32px top).
  - Emoji bubble: 80x80 (`w-20 h-20`), fully round, centered, `mb-4`, background muted at 50%, `shadow-inner`, `backdrop-blur-sm`. Enters with scale 0.5 to 1 and rotate -10deg to 0.
  - Emoji text-5xl (48px), drop shadow.
  - Title: text-2xl (24px), font-black, tracking-tight. Event title, unchanged.
- Scroll area `px-6` (24px sides). Content `space-y-6 pb-6`.
  - Status pill (if event has status), centered. `px-2 py-0.5` (8px x 2px), rounded-full, text-[10px] font-bold uppercase tracking-wider, 1px border.
    - Green when status is PAID, COMPLETED or SETTLED: bg green-100 (light) / green-900 at 30% (dark), text green-700 / green-300, border green-200 / green-800.
    - Otherwise yellow: bg yellow-100 / yellow-900 @30%, text yellow-700 / yellow-300, border yellow-200 / yellow-800.
  - Amount block: centered, `py-2`. Value `h3` text-5xl (48px), font-black, tracking-tighter.
    - Positive types (income, split settled, goal achieved, loan completed, goal created, asset created): green-600 (#16a34a) light, green-400 (#4ade80) dark. Prefix `₹`.
    - Otherwise: destructive color. Prefix `-₹`.
    - 0 decimals, count-up.
  - Detail rows (each `flex gap-3 items-start`, space-y-4 pt-2 between rows):
    - Note/description (only if description exists): icon tile 32x32 (`w-8 h-8`), fully round, bg blue-50 (light) / blue-900 @20% (dark), icon `AlignLeft` 16x16 blue-500. Label `Note / Description`: text-xs font-bold muted uppercase tracking-wider. Body: text-sm (14px) font-medium, leading-relaxed.
    - Date: icon tile 32x32 fully round, bg purple-50 / purple-900 @20%, icon `Calendar` 16x16 purple-500. Label `Date & Time` (text-xs, bold, muted, uppercase, tracking-wider). Value: text-sm font-medium, format `MMMM do, yyyy` (e.g. `October 5th, 2026`). The time is not shown despite the label.
- Footer `p-4 border-t bg-background flex-shrink-0`.
  - Button: outline variant, full width, `h-12` (48px), `rounded-xl` (12px), font-bold, label `Close Details`.

---

## Settings Screen

Route: Settings page (bottom-nav tab). Sections stack vertically with a section header above each card. Note: ThemeToggle component exists in src/components/settings/ThemeToggle.tsx (Dark Mode switch) but the Settings page does not render it, so there is no on-screen theme toggle in the current UI.

### Page shell
- Root: `p-3 space-y-6 pt-4 pb-20`. Padding 12px sides, 16px top, 80px bottom. Sections separated by 24px gap.
- Header row `flex items-center justify-between pt-1` (4px top):
  - Title `Settings`: text-xl (20px), font-black, tracking-tighter.
  - Ghost icon button, `rounded-full h-10 w-10` (40x40), muted-foreground, `HelpCircle` 24x24. Dispatches start-tour.

### Section header (shared by all four sections)
- Wrapper `space-y-0.5 mb-3 px-1` (2px gap, 12px bottom, 4px sides).
- Row `flex items-center gap-2` (8px):
  - Colored tile: `p-1.5` (6px padding, so 26x26 total), rounded-lg (8px), `shadow-sm`, background color per section; icon 14x14 (`h-3.5 w-3.5`) white.
  - Title: text-xs (12px) font-black, uppercase, tracking-tight, foreground.
- Description: text-[13px] font-bold, muted-foreground at 70%, `pl-8` (32px left, aligns under title), leading-tight.

| Section | Title | Description | Icon | Tile color |
|---|---|---|---|---|
| Identity | Identity | Manage Your Public Profile And Personal Details. | User | blue-600 #2563eb |
| Configuration | Configuration | App Preferences And Categorization. | Sliders | violet-600 #7c3aed |
| Data Backup | Data Backup | Export Your Financial Records. | Download | emerald-600 #059669 |
| Security | Security | Session Management And Account Control. | Shield | slate-600 #475569 |

### Setting row (shared pattern, used in Configuration, Data Backup, Security)
- Row: `flex items-center justify-between p-2.5` (10px padding), `rounded-xl` (12px), `cursor-pointer`, `transition-all duration-200`. Border transparent; on hover border `border` token and background `muted/50`.
- Left group `flex items-center space-x-3` (12px gap):
  - Icon tile: `p-1.5` (6px), `bg-muted`, rounded-lg (8px). Icon 14x14 (`h-3.5 w-3.5`) in row icon color.
  - Label: text-xs (12px), font-bold, foreground at 80%.
- Right: `ChevronRight` 14x14, muted-foreground at 50%. (Hidden for rows that set hideChevron.)
- Press feedback: light haptic on tap.

### Identity card
- Card: `border-none shadow-lg`, background gradient `bg-gradient-to-br` from blue-50 (#eff6ff) to indigo-50 (#eef2ff). Dark: from blue-950 @20% to indigo-950 @20%.
- Content padding `p-4` (16px).

**Loading** (profile still loading): centered block `text-center py-8` (32px vertical), `Loader2` 24x24 spinning, primary color. Rest of the page still renders.

**Loaded**, `space-y-4` (16px gap):

1. Handle tile: `flex items-center justify-between` row, `bg-white/50` (light) / `bg-black/20` (dark), `p-3` (12px), rounded-xl (12px), `backdrop-blur-sm`, border 1px white at 20%.
   - Left block `space-y-0.5`:
     - Label `Current Handle`: text-[9px] font-black, uppercase, tracking-widest, muted.
     - Row `flex items-center gap-1.5` (6px): `@{username}` text-base (16px), font-black, tracking-tight. Color primary if username set, destructive if not. Right icon: `CheckCircle` 14x14 green-500 when username set; `AlertTriangle` 14x14 destructive when not.
     - Fallback copy when no username: `@Not Set`.
   - Right avatar: 36x36 (`h-9 w-9`), fully round, background primary at 10%, text primary, font-black, text-lg (18px). Shows the first letter of display name, uppercase. If no display name, shows `N` (from `Not Set`).
2. Profile form (below, in same card).

**Profile form (ProfileForm)**
- Wrapped in inner `Card p-4`. Content `p-0 pt-4` (16px top).
- Form `space-y-6` (24px gap between fields and button).

*Display Name field*
- Label `Display Name` (shadcn Label), `space-y-2` (8px).
- Input wrapper `relative`. Icon `User` 16x16 absolute left-3, vertically centered, muted.
- Input: placeholder `Your preferred name`, class `pl-10`.
- Error (red text-sm, mt-1): `Display name is required.` (empty) or `Display name cannot exceed 50 characters.` (longer than 50).

*Username field*
- Label `Username (Unique)`.
- Input wrapper `relative`. Icon `Tag` 16x16 absolute left-3, muted.
- Input: placeholder `unique_handle`, `pl-10`. When a username already exists: background `muted/50` and input disabled (cannot be edited).
- Helper text (text-xs, muted): `Your unique identifier (used for sharing/splits). ` followed by `Cannot be changed once set.` when set, or `Set once.` when not set.
- Errors (red text-sm, mt-1):
  - `Username must be at least 3 characters.` (under 3)
  - `Username cannot exceed 20 characters.` (over 20)
  - `Username can only contain letters, numbers, and underscores.` (characters outside a-z, A-Z, 0-9, _)

*Save button*
- Full width, `h-10` (40px), default primary style. Disabled while saving.
- Label: `Save` icon (20x20, `h-5 w-5`, mr-2) + `Save Profile`.
- Saving: spinner `Loader2` 20x20 (mr-2) replaces the content, spinning.

*Toasts*
- No changes: `No changes detected.` (error style). Does not save.
- Success: `Profile updated successfully!` then navigate to `/` (replace).
- Username taken: `Username is already used. Please try another.`
- Other failure: provider message, or `Failed to update profile. Please try again.`

### Configuration card
- Card `border-none shadow-md`. Content `p-1 space-y-0.5` (4px padding, 2px gap).
- Row 1, Email (not clickable): `flex items-center justify-between p-2.5` (10px).
  - Left group `flex items-center space-x-3` (12px): icon tile `p-1.5 bg-muted rounded-lg` with `Mail` 14x14 violet-500. Text column `flex flex-col`:
    - `Email Address`: text-xs font-bold, foreground at 80%.
    - Email value: text-[10px] muted, font-medium. Shows the signed-in email, or `N/A` if missing.
  - Right: badge `px-1.5 py-0.5` (6px x 2px), bg green-100 (#dcfce7) light / green-900 at 30% dark, text green-700 (#15803d) / green-400 (#4ade80), text-[9px] font-black uppercase tracking-wider, rounded-md (6px). Copy: `Verified` (always shown, not conditional).
- Row 2, Manage Categories (setting row): icon `Tag` in pink-500 (#ec4899), label `Manage Categories`, chevron right. Navigates to the categories page.

### Data Backup card
- Card `border-none shadow-md`. Content `p-1 space-y-0.5`.
- Single row: icon `Database` in purple-500 (#a855f7), label `Full Backup & Restore`, chevron right. Tap opens the Backup & Restore sheet.

### Backup & Restore sheet (BackupRestoreSheet)
Bottom drawer, `h-[90vh] md:h-[85vh] max-w-md mx-auto flex flex-col`. Inner wrapper `mx-auto w-full max-w-md flex flex-col h-full overflow-hidden`.

**Header** `text-left flex-shrink-0 relative border-b p-4` (16px padding, bottom hairline):
- Top row `flex items-center gap-2 text-primary mb-1` (4px bottom): `Database` icon 20x20 primary, title `Data Management`: text-xl (20px), font-black, uppercase, tracking-tight.
- Description text-xs (12px), muted: `Securely export your financial DNA or restore from a previous backup.`
- Close button: ghost, `absolute right-4 top-4` (16px), 32x32, `X` 16x16.

**Body** `ScrollArea` with `flex-1 px-4` (16px sides). Inner `space-y-6 py-6` (24px gap, 24px vertical padding).

*Export section*
- Header row `flex items-center gap-2` (8px):
  - Icon tile `p-1.5 rounded-lg`, background blue-100 (#dbeafe) light / blue-900 @30% dark, icon color blue-600 (#2563eb) / blue-400 (#60a5fa). Icon `Download` 16x16.
  - Label `Export Data`: text-sm (14px), font-bold.
- Panel `p-4` (16px), bg muted at 30%, rounded-xl (12px), border border-border at 50%.
  - Copy (text-xs, muted, leading-relaxed, mb-4 = 16px): `Create a full JSON backup of your transactions, loans, goals, and settings. Useful for migrating devices or keeping a personal archive.`
  - Button full width, `h-10` (40px), rounded-lg (8px), bg blue-600 (#2563eb), hover blue-700 (#1d4ed8), text white, font-bold, `shadow-md` with blue-500 at 10% shadow color.
    - Idle: `FileJson` 16x16 (mr-2) + `Download Full Backup`.
    - Exporting: spinner `Loader2` 16x16 (mr-2) + `Packaging Data...`. Disabled while exporting.
  - Toasts: loading `Generating full backup...`, success `Backup downloaded successfully!`, failure `Export failed. Please try again.`

*Import section*
- Header row same pattern as Export: icon tile background emerald-100 (#d1fae5) / emerald-900 @30%, icon color emerald-600 / emerald-400, icon `Upload` 16x16, label `Import Data` (text-sm bold).

**State A: no file selected (default)**
- Dropzone-looking panel: `p-6` (24px), bg muted at 30%, rounded-xl, `border-2 border-dashed` border muted-foreground at 20%. Column, centered, text-center.
  - Button outline variant, `h-10` (40px), rounded-xl (12px), `mb-2` (8px), label `Select Backup File`. Opens a native file picker.
  - Hidden file input accepts `.json` only.
  - Caption text-[10px] muted: `Supported format: .json (FiNN Backup)`.
- Toasts: loading `Parsing backup file...`, failure `Invalid backup file.` (file stays unselected).

**State B: backup loaded**
- Wrapper `space-y-4` (16px), entering animation (fade in and slide up 8px).

*Backup Found card*
- `p-3` (12px), rounded-xl, bg emerald-50 at 50% (light) / emerald-900 at 10% (dark), border emerald-100 (dark emerald-900 at 20%).
- Top row `flex justify-between items-center mb-2` (8px):
  - Title `Backup Found`: text-xs (12px), font-bold, emerald-800 (#065f46) / emerald-300 (#6ee7b7).
  - Clear button: ghost, `h-6 w-6 p-0` (24x24), muted, hover destructive. Icon `X` 12x12. Clears the loaded backup and returns to State A.
- Grid `grid grid-cols-2 gap-2` (8px), two cells, each `bg-background/50 p-1.5` (6px) rounded (4px) with 1px border:
  - `Date` label (block, text-[10px], muted) over bold value: export date formatted with the device's locale date format.
  - `Version` label over bold value: backup version string.

*Select Data to Restore*
- Label: text-xs (12px), font-bold, uppercase, tracking-widest, muted, `ml-1` (4px).
- Grid of 1 column with 8px gap. Each row:
  - `flex items-center space-x-3` (12px gap), `p-2` (8px), rounded-lg (8px), hover bg muted at 50%, border transparent to border token on hover, transition colors.
  - Shadcn Checkbox (id matches item key), toggles on tap.
  - Label (flex-1, text-sm font-medium, pointer cursor, `flex justify-between items-center`): item name on left; record count on right inside a chip `text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded-md` (6px x 2px, 6px radius).
  - Rows and their copy, in order:
    1. `Transactions` (count = transactions)
    2. `Loans & Debt` (count = loans)
    3. `Goals & Savings` (count = goals)
    4. `Assets` (count = assets)
    5. `Subscriptions` (count = subscriptions)
    6. `Categories` (count = categories)
  - All six default to checked. Each can be toggled.

*Warning panel*
- `p-3` (12px), rounded-xl, bg amber-50 (#fffbeb) light / amber-900 @10% dark, border amber-100 / amber-900 @20%. Flex row, gap-2 (8px), items-start.
  - Icon `AlertTriangle` 16x16, amber-600 (#d97706), shrink-0, mt-0.5 (2px).
  - Text text-[10px], font-medium, leading-relaxed, amber-800 (#92400e) light / amber-200 (#fde68a) dark. Copy: `Importing will add to your existing data. Existing records with matching IDs will be updated. New records will be created.`

*Confirm button*
- Full width, `h-12` (48px), rounded-xl (12px), bg emerald-600 (#059669), hover emerald-700 (#047857), text white, font-bold, `shadow-lg` with emerald-500 at 20% shadow color. Disabled while importing.
- Idle: `Upload` 16x16 (mr-2) + `Confirm Import`.
- Importing: spinner `Loader2` 16x16 (mr-2) + `Restoring...`.
- Toasts: loading `Restoring data...`; success `Data restored successfully!` (closes the sheet and clears the loaded backup); failure `Import failed partially or completely.`

Note: the sheet has no Profile checkbox. Pending and Budgets are restored with defaults that are not shown in the UI.

### Sign Out row (Security card)
- Card `border-none shadow-md`. Content `p-1`.
- Row `flex items-center justify-between p-2.5` (10px), rounded-xl, cursor-pointer, `transition-all duration-200`, group hover bg red-50 (light) / red-950 at 20% (dark).
  - Left `flex items-center space-x-3`:
    - Icon tile `p-1.5` (6px), bg red-100 (#fee2e2) light / red-900 @30% dark, rounded-lg; on group hover bg red-200 / red-800 @40%.
    - `LogOut` 14x14, red-600 (#dc2626) light / red-400 (#f87171) dark.
    - Label `Sign Out`: text-xs font-bold, red-600 / red-400.
  - Right: spinner `Loader2` 14x14 red-600 when signing out. No chevron on this row.
- Tap fires light haptic and opens the confirm dialog.

**Confirm dialog (AlertDialog, centered modal)**
- Title: `Confirm Logout`.
- Description: `Are you sure you want to log out? You will need to sign in again to access your financial data.`
- Buttons (footer):
  - Cancel (default outline style): `Cancel`. Closes dialog.
  - Action (destructive): bg destructive, hover destructive at 90%. Idle label `Confirm Logout`. While signing out: `Loader2` 16x16 spinner (mr-2) + `Logging out...`, disabled.
- Logout result: success or failure both show toast `Successfully signed out.` and navigate to `/login` (replace). Dialog closes.

### Theme toggle (not on screen)
- Component exists but is not rendered. If it is added later, its spec is:
  - Row `flex items-center justify-between p-4` (16px), bg card, rounded-lg (8px), border.
  - Left: `Moon` 20x20 primary when dark, `Sun` 20x20 yellow-500 when light. Label `Dark Mode` (text-base 16px, font-medium).
  - Right: shadcn Switch, checked = dark mode.

---

## Not Found (404)

Route: any unmatched path.

- Wrapper `p-4 pt-20 flex flex-col items-center justify-center h-full`. Padding 16px, 80px top. Centered column.
- Inner `text-center`, no card.
  - `404`: text-6xl (60px), font-extrabold, primary color, `mb-4` (16px). Line-height 1.
  - `Oops! Page not found`: text-xl (20px), muted-foreground, `mb-6` (24px).
  - Link `Return to Home`, href `/`: text-blue-500 (#3b82f6), hover text-blue-700 (#1d4ed8), underline, font-medium. Hard-coded blue, not the primary token.
- No icon, no animation, no empty-state graphic.

---

## Shared notes for Flutter port

- Page background: solid `background` token on Timeline and Login-family screens, `muted/background` on others. Only Login, VerifyOtp and AuthCallback use gray-50 / gray-950.
- Cards on Settings and Insights use shadcn `Card` default radius (assumed 8px). Hero and stat tiles on Insights override to 32px and 16px respectively.
- Every amount is `₹` with no decimal places except Timeline amount pills (0 decimals), Daily Burn (0 decimals), Insights categories and methods (whole numbers via toLocaleString, no decimals).
- Count-up animation (AnimatedCounter) is used for: Insights hero amount, Timeline amount pills, and the Timeline detail sheet amount. Duration and easing were not read.
- Toast position and style come from the shared toast component (not read).

---

## Story generation rules

Output: one story "event" per important moment, grouped by `yyyy-MM`, sorted newest first. Each event has: title, description (body copy shown on card), emoji icon, theme color key, and amount (shown in the amount pill).

### Baselines (computed from the last 3 months of PAID transactions)
- `avgExpense` = mean amount of PAID expenses in the last 3 months. Default 1000 if none.
- `avgIncome` = mean amount of PAID income in the last 3 months. Default 20000 if none.
- `avgPending` = mean amount of single-user pending items (no split group). Default 2000 if none.

### Transactions (PAID only)
- Ratio = amount / max(baseline, 1), where baseline is `avgExpense` for expenses and `avgIncome` for income.
- Expense is a story event only if ratio >= 1.4 AND amount > 500.
- Every income transaction is a story event, regardless of size.
- Narrative (first matching):
  1. Expense with ratio >= 2.0: emoji `🌪️`, theme warning, title `Major Splash!`, description `A significant {category} purchase! You're making big moves.`
  2. Income with ratio >= 2.0: emoji `⚡`, theme celebration, title `Incredible Leap!`, description `A massive boost to your wealth! Keep the momentum.`
  3. Expense, category contains "food" or "dining": emoji `🍔`, theme fun, title `Fueling Up!`, description `Enjoying life's flavors.`
  4. Expense, category contains "travel": emoji `✈️`, theme adventurous, title `Expanding Horizons`, description `Investing in experiences.`
  5. Expense, category contains "shopping": emoji `🛍️`, theme fun, title `Personal Upgrade`, description `Investing in your lifestyle.`
  6. Other expense: emoji `💳`, theme neutral, title `Notable {category}`, description `Managing resources effectively.` (category defaults to `General`)
  7. Income, category contains "salary": emoji `💰`, theme success, title `Hard Work Paid Off`, description `Replenishing your war chest.`
  8. Other income: emoji `💵`, theme success, title `Resource Inflow`, description `Keeping the momentum going.`
- Category matching is case-insensitive substring match.
- Event type: `EXPENSE_PAID` or `INCOME_RECEIVED`. Event status: `PAID`.

### Pending transactions
- Single-user pending with amount >= 2.5 x avgPending: emoji `⏳`, theme warning, title `Big Things in Motion`, description `A heavyweight item with {person}. Mastering your cash flow!`. Type `PENDING_SETTLED`, status = the item's status.
- Split-group item with status PAID: emoji `🤝`, theme growth, title `Squared Away!`, description `Shared moment with {person} settled. Perfect harmony!`. Type `SPLIT_SETTLED`, status PAID.

### Goals (every goal)
- Always: emoji `🔭`, theme vision, title `Vision Locked: {goal name}`, description `Started the journey for {goal name}. Target: ₹{target, 0 decimals}`. Type `GOAL_CREATED`, status ACTIVE, dated at creation.
- If current amount >= target: emoji `👑`, theme victory, title `Victory Unlocked! 🏆`, description `You conquered your target for {goal name}. Be proud!`. Type `GOAL_ACHIEVED`, status COMPLETED, dated at last update.

### Loans
- Created (always): if borrowed, emoji `🤝`, theme warning, title `Strategic Commitment`, description `Secured ₹{principal, 0 decimals} from {person}.`. If lent, emoji `🤲`, theme growth, title `Helping Hand`, description `Supported {person} with ₹{principal, 0 decimals}.`. Type `LOAN_CREATED`, dated at loan start.
- Major repayment: a PRINCIPAL payment >= 20% of principal gives emoji `💥`, theme growth, title `Power Move! 🚀`, description `You just crushed a massive 20%+ chunk of your debt!`. Type `LOAN_PAYMENT`, status PAID.
- Completed: loan status Settled or Closed, or outstanding balance <= 1.0. If borrowed: emoji `🕊️`, theme freedom, title `Freedom Achieved: {person}`, description `Fully cleared debt to {person}. Huge win!`. If lent: title `Karma Returned: {person}`, description `{person} has fully repaid. Trust rewarded.`. Type `LOAN_COMPLETED`. Dated at the latest payment date, or now if no payments.

### Assets
- Acquired (always): emoji `🏠` for Home, `🚗` for Vehicle, `💎` otherwise. Theme asset. Title `Asset Secured: {name}`. Description `Expanded your empire with {name} ({type}).`. Type `ASSET_CREATED`, dated at creation.
- Sold (sell price and sold date both set): profit = sell price - value. Title `Smart Exit: {name}` with description `Profit realized: ₹{profit, 0 decimals}! Nice exit.` if profit >= 0 (theme celebration). Otherwise title `Strategic Shift: {name}` with description `Asset liquidated. Moving capital to better spots.` (theme neutral). Emoji `💰`. Type `INCOME_RECEIVED`, status SOLD, dated at sale.

### Chapter-level rules (what the screen does with events)
- Month key from event date. Current month is always listed even if empty.
- Chapter theme: see Timeline chapter table (counts by event type: INCOME_RECEIVED, EXPENSE_PAID, types containing LOAN, types containing GOAL, rarity MYTHIC).
- Mood: `positive` if any event in the month has color `celebration`, else `neutral`.
- Event count in chapter header is the total number of events for that month (not plural-aware).


---

