# AGENTS.md — AI Agent Rules for Submariner-Revamped

This file defines rules, conventions, and context for any AI agent working in this repository.
Read this file in full before making any changes to the codebase.

---

## Project Overview

**Submariner** is a native macOS Subsonic client written in Swift and Objective-C.
This fork (`Submariner-Revamped`) is a personal branch aimed at improving, modernizing, and
extending the upstream project with a focus on code quality, UX, and feature parity.

- **Platform:** macOS 26+ (using Xcode 26+)
- **Language:** Swift (primary) + Objective-C (legacy components)
- **UI:** AppKit (preparing for a future Liquid Glass aesthetic redesign; keep UI logic clean and separated)
- **Data:** Core Data
- **Networking:** Subsonic REST API (v1.16.1+)
- **Build system:** Xcode

---

## Core Principles

1. **Correctness first.** Never break existing functionality when refactoring or adding features.
2. **Prefer Swift over Objective-C.** When touching legacy `.h`/`.m` files, prefer migrating to Swift
   if it can be done safely and without regressions. Do not introduce new Objective-C code.
3. **Keep it native.** This is a native macOS app. Do not introduce Electron, web views, or
   cross-platform abstractions. Embrace AppKit, Core Data, and Apple frameworks.
4. **No unnecessary dependencies.** Do not add third-party libraries or packages without explicit
   approval. The project currently vendors only MGScopeBar — keep the footprint minimal.
5. **Incremental changes.** Prefer small, reviewable, focused commits over large sweeping rewrites.
   If a refactor is large, break it into a series of logical steps.

---

## Code Style & Conventions

### Swift
- Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
- Use `guard` for early exits; avoid deeply nested `if`-statements.
- Prefer `let` over `var` wherever possible.
- Use trailing closures, but do not over-chain to the point of obscuring intent.
- All types, methods, and properties should have meaningful, descriptive names.
- Prefer `async/await` over completion handlers for new code; do not introduce DispatchQueue soup.
- Use `@MainActor` appropriately for any UI-touching code.
- **Access Level Discipline**: Every `@IBOutlet`, `@IBAction`, and stored property that is referenced from an extension file must be declared at the `internal` level (the Swift default — no modifier needed) in the primary class file. Do not use `private` on any shared state. Swift extensions in separate files cannot access `private` members of their extended type.

### Objective-C (Legacy)
- Do not add new `.h`/`.m` files.
- When modifying legacy files, keep changes minimal and surgical.
- When bridging to Swift, use the existing bridging header (`Submariner-Bridging-Header.h`).

### Naming
- The existing `SB` prefix on types is legacy — **do not add it to new Swift types**.
  New types should use plain descriptive Swift names (e.g., `PlayerState`, not `SBPlayerState`).
- File names should match the primary type they define.
- Extensions should be named `TypeName+Functionality.swift`.

### Core Data
- Fetch requests should be centralized; avoid scattering `NSFetchRequest` construction
  throughout view controllers.
- Use the helpers in `NSManagedObjectContext+Fetch.swift` where applicable.
- Never perform Core Data operations on the main thread if they can block the UI.
- Use `@MainActor` for context saves that update the UI.

---

## Architecture Guidelines

- **View Controllers** should be thin — logic should live in model or service layers, not VCs.
- **Operations** (`SBOperation` subclasses) are the preferred pattern for background work.
  Continue using this pattern for new networked or long-running tasks.
- **Notifications vs. Delegation vs. Combine** — prefer delegation or Combine publishers for
  new code; avoid adding more `NotificationCenter` observers unless integrating with existing code.
- **XIB files** — do not create new XIBs. For any new UI, prefer SwiftUI (as a sheet or panel)
  or programmatic AppKit views.
- **Avoid massive view controllers.** `SBDatabaseController.m` (~90KB) and `SBPlayer.swift`
  (~39KB) are known hot spots. Do not make them larger; look for opportunities to extract
  focused sub-controllers or services.

---

## Testing

- There are currently no automated tests. Do not let this be an excuse to not think about
  testability — write code that *can* be tested (pure functions, injectable dependencies).
- When adding new networking or parsing logic, write it in a way that it could be unit-tested
  against a mock Subsonic server response.
- If you add tests, place them in a new `SubmarinerTests` target.

---

## Git Workflow

- **Commit messages:** Use the imperative mood in the subject line
  (e.g., `Fix cover art path collision`, not `Fixed cover art path`).
- **Branch naming:** `feature/short-description`, `fix/short-description`, `refactor/short-description`.
- **Do not commit:**
  - `DEVELOPMENT_TEAM.xcconfig` (it's in `.gitignore` and contains your personal signing ID)
  - `.DS_Store` files
  - Derived Data or build artifacts
- Run `git config core.hooksPath .githooks` after cloning (see README).

---

## What This Fork Wants to Improve

These are the primary goals of this fork. When evaluating changes, bias toward work that serves these:

1. **Migrate Objective-C to Swift** — especially `SBDatabaseController`, `SBViewController`,
   `SBMusicController`, and the server controllers.
2. **Reduce view controller bloat** — extract business logic out of controllers.
3. **Modernize networking** — the Subsonic request/parsing pipeline (`SBSubsonicRequestOperation`,
   `SBSubsonicParsingOperation`) is large and complex; consider splitting it up and using
   `async/await` throughout.
4. **Improve error handling** — surface errors to users clearly; avoid silent failures.
5. **UI polish** — small UX wins, accessibility improvements, and modern macOS design
   patterns (e.g., menus with icons, proper toolbar items).
6. **Optimize Playback Initiation** — Address latency when initiating playback (currently ~3 seconds, whereas other clients like Supersonic take <2 seconds).
7. **Optimize Cover Art Loading** — Fix slow cover art loading from the server when browsing artists and albums (some covers take 7-10 seconds to load instead of under 1-2 seconds).

---

## What to Avoid

- **Do not break the Core Data migration chain.** The schema has an existing migration from V7→V8.
  Any new schema changes must include a proper migration mapping model.
- **Do not change public-facing Scripting (`.sdef`) APIs** without careful thought —
  users may have automations that depend on them.
- **Do not silently remove features.** If something is being deprecated or removed, note it clearly
  in the commit message and, if user-visible, in the release notes section of `README.md`.
- **Do not over-engineer.** A simple, readable solution that works is always preferred over
  a clever one that's hard to follow.

---

## Release Notes

When you add or change something user-visible, add a bullet to the `### Not yet released` section
of `README.md`. Keep bullets concise and written from the user's perspective.
