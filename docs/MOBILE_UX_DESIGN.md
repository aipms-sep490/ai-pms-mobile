# Mobile UX redesign — 0.5.0

## Shared direction

Preserve Flutter, API contracts, session and capability rules. Native student companion: calm neutral surfaces, the existing burnt orange brand accent, dark ink text, system sans with Vietnamese support. No stock imagery, gradients, decorative motion or new state library.

- One clear page title; avoid a large RemotePage heading directly below an AppBar title. Root will add `RemotePage(showHeading: false)` support. Agents may use that named argument in screens that already have an AppBar.
- One primary action per screen/state. Secondary actions belong in an overflow menu, contextual bottom sheet, or a quiet icon/text control; avoid piles of equal-weight outlined/filled buttons.
- Keep vertical reading and horizontal category selection separate. Root will provide `HorizontalChoices(children: [...])` in `lib/ui/mobile_components.dart`: horizontal native scrolling, 48dp touch targets, labels preserved. Import this for choice-chip rails. A visible text/selection state must explain every gesture; retain tap alternatives.
- Root owns shared `AppColors`, ThemeData, RemotePage, Surface, RecordTile, ContentSection and navigation. Reuse existing helpers; no parallel design systems. Surface remains a simple single container; avoid nested card borders.
- Typography: 24–26dp page headings, 18–20dp section titles, 14–16dp content, clear 500/600 weights. Body/controls wrap on narrow screens and at large text scale. Standard 16–20dp page inset and consistent 8/12/16/24 spacing.
- Primary actions stay easy to reach; long forms use grouped sections and a safe bottom save action. Keep fields and error messages visible above the keyboard. Never hide an important state only in color.
- Use short native transitions (roughly 180–240ms), optional horizontal main-page swipe and pull-to-refresh. Respect disableAnimations/accessibility settings. No motion that delays actions or changes business state.
- Every screen needs deliberate loading, empty, error/retry, denied and submitting states. Preserve 401/403/404 clearing, draft/conflict behavior and idempotency guards.

## Ownership for this pass

| Owner | Editable scope | Responsibility |
| --- | --- | --- |
| Root | app.dart; lib/ui; dashboard/auth/profile; project/inbox/activity/video screens; integration/docs | Common design, navigation, old-screen consistency, final browser QA, integration and release |
| Conversation agent | lib/features/ai and lib/features/chat | AI/chat hubs, mode selection, readable responses, compact composer, conversation rows and contextual actions |
| Task agent | tasks_screen.dart and task_editor_screen.dart | Task lists, filters, details, grouped authoring/assignment, keyboard and sticky save UX |
| QA agent | read-only audit first, then own test file(s) | Independent usability/accessibility findings, narrow/large-text/gesture regression checks, final assessment |

No agent edits another owner's files or commits/pushes independently. Root handles shared conflicts, format/analyze/tests/build and a PR into develop. Runtime QA must distinguish live backend reads from fixtures and native device acceptance.
