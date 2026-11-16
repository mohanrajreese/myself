---
paths:
  - "lib/**/presentation/**"
  - "lib/core/widgets/**"
  - "lib/app/theme.dart"
---

# UI rules

- A screen is built only after the owner approved its design on the design canvas (decision D6). New or changed screen: add or update its artboard, show it, wait.
- Use design tokens and components from `lib/core/widgets`. No literal colours, font sizes or paddings in feature code. Tokens: `docs/blueprint/04-ui-ux-spec.md` §1.
- Every screen handles loading, empty, error, success feedback, offline and validation states, and confirms destructive actions (§3 of the same file).
- Every interactive element performs its action. No disabled-forever or no-op controls.
- Semantic labels on all controls; touch targets at least 48 dp; layouts hold at font scale 2.0 on a 320 dp width.
- Status is never colour alone: add an icon or label.
- Tone: neutral for missed habits, no causal or diagnostic claims, no pressure in bowel or medication copy (§7 of the same file).
- Activity states are four distinct things: completed, missed, skipped, not scheduled.
