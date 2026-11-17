# Mobile UX review — 0.5.0, 17/11/2026

Baseline `7fd7b11`. Whole student app reviewed, with deeper changes to task, AI, chat and meeting workflows. Backend authorization remains authoritative; no dependency, native permission or provider change.

## Team and review

| Workstream | Model / owner | Delivered |
| --- | --- | --- |
| Conversations | gpt-6.1-sol sub-agent | AI hub/reader/options, chat inbox/bubbles/composer, reply safety, local QA fixture API outside Git |
| Tasks and video | gpt-6.1-sol sub-agent | Task list/details/editor, persistent save, validation reveal, room prejoin and media controls |
| Independent QA | gpt-6-luna sub-agent | Ranked audit, responsive/keyboard/gesture tests, independent browser critique, peer review |
| Integration | Root | Design system, retained swipe navigation, dashboard/profile/project/inbox/calendar, integration and release |

Owners edited separate files and reviewed peer changes. Root handled integration/Git. No agent independently committed, pushed or sent real messages.

## Findings and resulting behavior

| Finding | Result |
| --- | --- |
| Duplicate AppBar/body titles | One active-page title; body headings suppressed under existing chrome |
| Too many equally weighted actions | One primary action; related secondary tools grouped or placed in contextual sheets |
| Filters consumed multiple vertical rows | Horizontal rails, 48dp targets, selected checkmarks and tap controls |
| Create control pushed tasks below the fold | Compact project/create row; status-specific record icons and tighter spacing |
| Save/errors lost in long forms | Grouped sections, persistent safe-area save, reveal first invalid field/error; preserve conflict draft |
| Retained search kept keyboard on another tab | Tab taps unfocus while preserving input; swipe disabled with keyboard open |
| AI/chat footer/error overflow | Errors scroll with content; composer bounded to available body height |
| Short AI landscape body overflow | Single AppBar options action; metadata scrolls with transcript; dedicated keyboard regression |
| Recalled/revoked reply preview remained visible | Reply follows current message state and clears when unavailable |
| Dashboard retained data after403 | Clear401/403/404, preserve temporary503 cache; retry regression |
| Busy refresh invisible when scrolled | Public refresh retains cache; progress pinned outside scroll content |
| Stale major selection after requirements reload | Remove out-of-scope selections with notice; preserve remaining draft |
| Video/RSVP action clutter | Single gated start/join CTA, three-control call dock, secondary overflow; RSVP choice sheet |
| Raw AI Markdown/repeated disclaimers | Inert native heading/list/bold reader and one advisory location; no HTML execution |

## Evidence and limits

- Flutter3.50.0/Dart3.14.0. Format/analyzer pass. **35 tests pass**: existing session/API/capability/draft regressions plus320dp/200% rails, keyboard-safe sign-in, swipe/tap state retention, focus dismissal, reduced motion and AI812×375 with244dp keyboard inset.
- Independent Chrome DevTools review at375×812 and320×667: task rows/readability, forms, AI/options and chat inbox/thread. No overlap found in reviewed rows. The initial tall create button was identified and replaced. Horizontal rails retain a partial next item;320dp chat titles may ellipsize while full text remains accessible.
- A separate local API/preview supplies synthetic privileged/populated/empty/error/denied states. Fixture data/source stays outside Git and is not part of the staging build. Root checks these states separately from live backend reads.
- Main navigation keeps tap tabs and adds adjacent-page swipes. Explicit animations respect reduced motion. Native pull refresh and accessibility refresh actions remain.
- CI validates final web and staging Android APK before merge. Browser/fixtures do not prove real media, Bluetooth, native storage, iOS or physical-device usability; these remain native acceptance work.

This is a code, interaction and visual assessment, not a user study or formal accessibility certification. No real academic writes or calls were performed for visual testing.

## Interaction follow-up — 0.5.1, 17/11/2026

Baseline `1476232`; the same three agents continued with separate ownership and independent review. This patch closes reproduced interaction failures without changing API payloads, dependencies, native permissions or the provider.

| Reproduction | Fix and regression evidence |
| --- | --- |
| Back from AI/chat with unsent text, attachments or a reply silently discarded the draft | Native route guard offers keep/discard, including system Back; pending sends show wait feedback and release the guard after completion. Drafts remain memory-only. |
| New-chat sheet overflowed by193px in812×375 at200% text | Scroll-controlled, safe-area sheet with native vertical scrolling. |
| Long edit dialog overflowed above the landscape keyboard | Scrollable native dialog; save remains reachable. |
| Inbox category403 removed the controls needed to return to notifications | Category rails remain outside data-only content; independent320dp/150% regression switches back successfully. The shared fix also covers activity status filters. |
| A failed task query left only retry for the same query | Error-state clear action restores a valid query while preserving the milestone scope; successful-content header ordering remains intact. |
| Removing the last row on page2 loaded page1 but subsequent refresh still requested page2 | Synchronize the page state, capture request inputs and ignore superseded loads; regression checks the next refresh requests page1 directly. |
| An old video poll completed after a newer403 and restored Join | Session request versions discard late results and invalidate pending reads on start/join/end/dispose; deterministic regression performs reads only. |

New regressions are in `conversation_interaction_test.dart`, `task_interaction_test.dart`, `mobile_interaction_test.dart` and `paged_records_test.dart`. The task draft/back regression also confirms existing behavior at320dp/200% without adding another create guard.

This Windows host has no Android SDK, emulator or connected device tooling. Android APK compilation is checked in CI; real mic/camera, Bluetooth, secure storage restart and iOS remain separate acceptance work.
