## Project Overview

- SwiftUI-based tvOS application targeting tvOS 26+.
- Swift 6+

## Mandatory Rules

- Before changing anything, read the relevant files end to end, including all call/reference paths.
- Don’t modify code without reading the whole context.

## File Header (Exact)

```swift
//
//  Filename.swift
//  ProjectName
//
//  Created by Sedoykin Alexey on DD/MM/YYYY.
//

import SwiftUI
```

## Build Commands

In general, you do not need to run `xcodebuild` commands unless explicitly requested.

## Code Style Guidelines

- Use PascalCase for structs/file names.
- Use camelCase for variables/functions.
- Use `// MARK: -` comments to separate logical sections within files:
  ```swift
  // MARK: - Properties
  // MARK: - Body
  // MARK: - Subviews
  // MARK: - Actions
  // MARK: - Helpers
  // MARK: - Preview
  ```
- Never add `// MARK: -` before single functions, tiny computed properties, or every small item (STRICT)

### Spacing & indentation

- 4 spaces
- One empty line before every MARK
- One empty line after every MARK
- One empty line before `var body: some View`
- Exactly one empty line at EOF

### Property Declaration Order (STRICT)

Declare properties in exactly this order, from top to bottom:
1. `@Environment`, `@EnvironmentObject`
2. `@State`, `@FocusState`, `@Binding`
3. `@Bindable`
4. `@Published` (inside `ObservableObject` classes)
5. `@ObservedObject`, `@StateObject` (legacy/heavyweight cases only)
6. Immutable `let` inputs / injected dependencies
7. `private let` constants and publishers (e.g. Timer, cancellables)
8. Computed formatters and helpers
9. Derived / computed `var` properties

No deviations allowed. When modifying a file, reorder existing properties to match this sequence.

## Software Architecture Rules (STRICT)

### 1. Architecture and State Management

- Use 100% declarative UI if possible. No mixing with UIKit unless explicitly marked.
- Use the Observation framework (`@Observable`) as the primary state management solution.
- The `@Observable` macro is the default choice for most view models and data models.
- Prefer `@State` and `@Bindable` over `@StateObject` and `@ObservedObject` in most cases.
- Reserve `@StateObject` for heavyweight objects that must survive view recreation.
- Maintain a single source of truth for application state; avoid duplicated mutable state.
- Prefer explicit data passing with `@Bindable` or value types; do not rely heavily on `@EnvironmentObject` for frequently changing data.
- Apply `@MainActor` to all code that interacts with the UI.
- Single quotes are not allowed; use double quotes (`"`).
- No force-unwrapping (`!`) except in `fatalError` or explicitly marked `// INTENTIONAL`.

### 2. View Design and Structure

- Views are `struct`s, never classes.
- Use `some View` return type everywhere.
- Keep views small and single-responsibility.
- If a `body` exceeds 30-40 lines, refactor into smaller subviews.
- Avoid complex conditional logic directly in `body`; use ternary operators, computed properties, or dedicated subviews.
- Leverage `@ViewBuilder` to build clean, composable view hierarchies.
- Prefer lazy containers for scrollable content: `LazyVStack`, `LazyVGrid`, `LazyHStack`, and `List`.
- Keep View files focused on UI composition and bindings.
- Never put `Timer`, `URLSession`, `UserDefaults`, or `JSONDecoder` directly inside a View file.
- `@State` may own local UI state and owned `@Observable` models, but must not duplicate external source-of-truth data.

### 3. Performance Best Practices

- Ensure `body` computes quickly.
- Move expensive operations out of `body` into cached computed properties, `.task`-driven loading, or dedicated data models.
- Design views with granular dependencies so only necessary parts of the view tree update when state changes.
- Avoid passing large observable objects deep into the view hierarchy; pass only needed properties or derived values.

### 4. Previews and Development Workflow

- Adopt Preview-Driven Development.
- Keep SwiftUI preview declarations at the bottom of each view file.
- Prefer `#Preview` for modern code. If `PreviewProvider` is used for compatibility, name it `Preview`.
- Create dedicated preview containers for complex state management.
- Use design-time implementations and preview-specific data to keep previews fast and reliable.

### 5. Code Quality and Modifiers

- Extract repeated styling into custom `ViewModifier`s or view extensions when modifier chains become long.
- Define constants for spacing, corner radii, and other design tokens.
- Always add accessibility modifiers (`.accessibility*`).
- Use `.privacySensitive()` for sensitive information.
- Eliminate magic numbers and hardcoded strings; centralize them in constants or extensions.

### 6. Swift Concurrency Rules

- Use modern Swift concurrency (`async/await`) with `.task`, `.refreshable`, and async functions instead of completion handlers.
- `.task` and `.refreshable` in Views must call model/ViewModel async entrypoints; do not embed business logic directly in the View.
- Mark async entrypoints clearly (e.g. `func loadData() async`).
- Never use `try?` silently — either use explicit error propagation or annotate `// INTENTIONAL: fire-and-forget`.

### 7. Data and Persistence

- Prefer SwiftData over Core Data for new projects unless complex migrations are required.

### Agent Instruction

When adding or modifying a View:
1. Default to an `@Observable` state model owned by `@State` and exposed with `@Bindable`.
2. If screen logic becomes complex (multiple data sources, heavy side effects, or > 80 lines of non-UI logic), extract a dedicated `FeatureViewModel`.
3. Keep View code focused on rendering, composition, and bindings; move business rules to the state owner.
4. Use a feature folder that contains related files (for example, `FeatureView.swift` and `FeatureViewModel.swift` when a ViewModel exists).

Violation = automatic refactor required.

### Error Handling

- Any screen state owner (`@Observable` model or ViewModel) that can fail must expose `var error: Error?` and derived `var showError: Bool`.
- Views should create `Binding<Bool>` adapters from `showError` in the View layer.
