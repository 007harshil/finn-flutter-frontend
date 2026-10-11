# Design system API (quick reference)

Import: `package:finn/design_system/design_system.dart` (tokens, theme, motion, components). Colors: `context.colors` (FinnColors), text: `context.text` (FinnTypography), motion: `context.motion`, `context.reduceMotion`. Tokens: `Space`, `Radii`, `Elevation`, `Dimens`, `Palette`, `AccentSwatches.gradient(i)/solid(i)`.

Amounts
- `AmountVisibility({hidden, child})`, `AmountVisibility.hiddenOf(ctx)`
- `AmountText(Money, {style, sign, decimals, colorize, color, compact, fit, textAlign, semanticsLabel})`
- `AnimatedAmount(Money, {...same, animateOnMount})`

Cards: `PressableScale({child, onTap, onLongPress, scale=.97, haptic, enabled, semanticLabel})`, `FinnCard({child, padding, onTap, variant: surface|muted|outlined|gradient, gradient, radius, shadow, border, haptic, semanticLabel})`, `GradientHeroCard({child, gradient, watermark, padding, onTap, radius=24})`

Headers/buttons: `SectionHeader({icon, title, tileColor, subtitle, trailing, onAction, actionLabel})`, `FinnButton({label, onPressed, icon, variant: primary|secondary|outline|ghost|destructive|positive|attention, size: sm|md|lg, loading, expand})`, `FinnIconButton({icon, onPressed, tooltip, variant: ghost|filled|outline, size, color})`

Inputs: `FinnTextField({label, hint, controller, errorText, prefixIcon, suffix, keyboardType, maxLines, minLines, maxLength, textInputAction, textCapitalization, inputFormatters, onChanged, onSubmitted, enabled, autofocus, focusNode})`, `AmountField({controller, label, hint, errorText, onChanged(Money?), onSubmitted, focusNode, autofocus, enabled, textInputAction})` + `AmountField.parse(String)`, `FinnSearchField({onChanged, controller, hint, debounce, onSubmitted, focusNode, autofocus})`, `DateField({value, onChanged, firstDate, lastDate, label, hint, errorText, enabled})`

Selectors: `SegmentedTabs<T>({items: [SegmentItem(value,label,{count})], selected, onChanged})`, `FilterChipBar<T>({items: [FilterChipItem(value,label,{icon})], selected: Set<T>, onChanged, multiSelect})`

Progress: `FinnProgressBar({value, color, trackColor, height=8})`, `ProgressRing({value, size, strokeWidth, color, child})`

Tiles: `IconTile({icon, background, foreground, size, radius, iconSize, gradient})`, `CategoryIconTile({icon, colorIndex, color, size, radius})`, `StatusPill({label, color, icon, filled})`, `CountBadge({count, child, color})`

States: `EmptyState({icon, title, message, actionLabel, onAction, actionIcon})`, `ErrorState({title, message, onRetry, retryLabel})`, `SkeletonPulse({child})`, `SkeletonBox({width, height, radius})`, `ListSkeleton({count, rowHeight})`, `CardSkeleton({height, radius})`

Overlays: `showFinnSheet<T>(ctx, builder:)`, `FinnSheetScaffold({child, title, description, footer, showClose, onClose, bodyPadding})`, `showFinnConfirm(ctx, title:, message:, confirmLabel:, cancelLabel, destructive, details) → Future<bool>`, `showFinnActionMenu<T>(ctx, title:, items: [FinnMenuItem(value:, label:, icon, destructive, enabled)])`, `FinnToast.success/error/warning/info(ctx, title, {subtitle})`, `SuccessCheck`, `showSuccessOverlay(ctx, title:, subtitle:)`

Display: `MonthSwitcher({month, onChanged, min, max})`, `KeyValueRow({label, value, valueWidget, valueColor})`, `StatTile({label, value, caption, accent, icon, onTap})`, `InfoBanner({message, tone: FinnTone, title, icon, actionLabel, onAction})`, `DotSeparator`, `FinnDivider`, `StaggeredEntrance({child, index})`, `ResponsiveCenter({child, maxWidth, padding})`. `FinnTone {info, positive, warning, negative}` with `.color(colors)`, `.soft(colors)`, `.icon`; `colors.onSolid`.

Note: app root must call `initializeDateFormatting('en_IN')` (DateFormats use en_IN).
