---
status: complete
---

# Phase 8: Onboarding

## Overview

Build the full onboarding flow for first launch: the scaffold (progress bar, kicker, footer), four screens (Welcome, Accessibility, Suggestions, Done), the OnboardingViewModel, and view model tests. Replace the placeholder in AppShellUI's MainWindowRootView with the real OnboardingRootView. The window is fixed 640x600, not resizable, with hidden title bar during onboarding.

## Steps

1. **OnboardingViewModel** (`OnboardingUI/OnboardingViewModel.swift`): An `@MainActor @Observable` class that holds the current step (1-4), permission state (polling during step 2), suggestions + selected IDs, and provides `advance()`, `grantAccessibility()`, `skip()`, `loadSuggestions()`, `applySuggestionsAndComplete()`. Depends on `AppCore`.

2. **OnboardingScaffold** (`OnboardingUI/OnboardingScaffold.swift`): The shared layout wrapper per ui_design section 5.1 — progress bar (accent capsule, step/4 fill, 240x3), kicker (caption, semibold, uppercase, wide tracking, secondary), centered content slot, primary button, optional skip button, and brand footer (app icon 16pt + "Squeegee" headline + tagline caption tertiary).

3. **ProgressHeader** (`OnboardingUI/ProgressHeader.swift`): The progress bar + kicker label as a standalone component.

4. **BrandFooter** (`OnboardingUI/BrandFooter.swift`): App icon + app name + tagline.

5. **WelcomeStepView** (`OnboardingUI/WelcomeStepView.swift`): Screen 1 — app icon 96pt above the title, "Welcome to Squeegee", lead text, Continue button.

6. **AccessibilityStepView** (`OnboardingUI/AccessibilityStepView.swift`): Screen 2 — lead text, a card with the accessibility row (icon tile, "Accessibility", subtitle, Grant/Granted state), help text, Continue (enabled when granted), Skip link.

7. **SuggestionsStepView** (`OnboardingUI/SuggestionsStepView.swift`): Screen 3 — lead text, SuggestionListView from SharedUI, Continue button.

8. **DoneStepView** (`OnboardingUI/DoneStepView.swift`): Screen 4 — "You're All Set", lead text with menu bar hint, Get Started button.

9. **OnboardingRootView** (`OnboardingUI/OnboardingRootView.swift`): The public entry point; creates the view model, switches on the current step to show the correct step view inside the scaffold.

10. **Update AppShellUI/MainWindowRootView**: Replace the onboarding placeholder with `OnboardingRootView(core:)`. Apply the 640x600 fixed size and hidden title bar during onboarding route.

11. **Remove OnboardingUI/Placeholder.swift**: Replace with real code.

12. **Add OnboardingUITests test target** to `Package.swift`.

## Tests

- `testInitialStepIsWelcome`: ViewModel starts at step 1 (welcome).
- `testAdvanceFromWelcome`: After `advance()`, step is 2 (accessibility).
- `testAdvanceThroughAllSteps`: Walking through all 4 steps in order.
- `testContinueBlockedWithoutPermission`: On step 2, `canContinue` is false when permission is denied.
- `testContinueEnabledWithPermission`: On step 2, `canContinue` is true when permission is granted.
- `testSkipAccessibility`: Calling `skip()` on step 2 advances to step 3 without requiring permission.
- `testGrantCallsRequestAccessibility`: `grant()` calls `core.requestAccessibility()`.
- `testSuggestionsLoadOnStep3`: When step reaches 3, suggestions are loaded from core.
- `testApplySuggestionsAndComplete`: Selected suggestions are applied through core, onboarding is completed, route changes to settings.
- `testPermissionStateUpdates`: When permission changes from denied to granted, the view model reflects it.
