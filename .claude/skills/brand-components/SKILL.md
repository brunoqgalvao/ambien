# Brand Components Library

Use this skill when implementing UI in the MeetingRecorder app. This documents all available brand components, when to use them, and how to avoid common mistakes.

## Quick Reference

| Component | Use For | Example |
|-----------|---------|---------|
| `BrandPrimaryButton` | Main CTAs, submit actions | "Save", "Start Recording" |
| `BrandSecondaryButton` | Secondary actions | "Cancel", "Learn More" |
| `BrandGhostButton` | Tertiary/minimal actions | "Skip", "Maybe Later" |
| `BrandDestructiveButton` | Dangerous actions | "Delete", "Remove" |
| `BrandIconButton` | Toolbar icons, compact actions | Settings gear, close X |
| `BrandMenuButton` | Dropdown menu items | Menu bar items with shortcuts |
| `BrandTabButton` | Tab/segment selectors | "All", "Meetings", "Dictations" |
| `BrandListRow` | Selectable list items | Meeting list rows |
| `BrandSearchField` | Search inputs | Search bars with clear button |
| `BrandTextField` | Text inputs | API key input, form fields |
| `BrandCard` | Content containers | Cards, panels |
| `BrandBadge` | Labels, tags | "NEW", "3 min", "LIVE" |
| `BrandStatusDot` | Status indicators | Recording dot, online status |
| `BrandStatusBadge` | Meeting status | Recording, transcribing, ready, failed |
| `BrandDivider` | Separators | Horizontal/vertical lines |

## Brand Colors (from BrandAssets.swift)

```swift
// Primary
Color.brandViolet        // #8B5CF6 - Primary accent
Color.brandVioletBright  // #A78BFA - Hover state
Color.brandVioletDeep    // #6D28D9 - Pressed state

// Backgrounds
Color.brandCream         // #FAF7F2 - Main background
Color.brandCreamDark     // #F0EBE0 - Secondary background
Color.brandSurface       // White - Cards, inputs
Color.brandBackground    // Alias for brandCream

// Text
Color.brandTextPrimary   // brandInk - Main text
Color.brandTextSecondary // brandInk @ 60% - Secondary text
Color.brandInk           // #0F0F11 - Pure black text

// Semantic
Color.brandCoral         // #FF6B6B - Errors, destructive
Color.brandCoralPop      // #FF8787 - Coral hover
Color.brandMint          // #4ADE80 - Success
Color.brandAmber         // #F59E0B - Warnings
Color.brandYellow        // #FBBF24 - Highlights

// Borders
Color.brandBorder        // brandInk @ 10%
```

## Corner Radius (BrandRadius)

```swift
BrandRadius.small   // 8px - Buttons, inputs, small cards
BrandRadius.medium  // 16px - Cards, modals, toasts
BrandRadius.large   // 32px - Large panels
BrandRadius.pill    // 999px - Pills, badges
```

## Typography (from BrandAssets.swift)

```swift
Font.brandDisplay(size, weight: .semibold)  // Headings, buttons (rounded)
Font.brandSerif(size, weight: .regular)     // Body text (serif)
Font.brandMono(size, weight: .regular)      // Code, timestamps (monospaced)
```

---

## Component Details

### BrandPrimaryButton

Filled violet button for primary actions.

```swift
BrandPrimaryButton(
    title: "Get Started",
    icon: "arrow.right",      // Optional SF Symbol
    isDisabled: false,        // Optional
    size: .medium             // .small, .medium, .large
) {
    // action
}
```

**When to use:** Main CTAs, form submissions, primary actions
**When NOT to use:** Cancel buttons, secondary options

---

### BrandSecondaryButton

Outlined button for secondary actions.

```swift
BrandSecondaryButton(
    title: "Cancel",
    icon: "xmark",            // Optional
    size: .medium
) {
    // action
}
```

**When to use:** Cancel, back, secondary options
**When NOT to use:** Primary actions, destructive actions

---

### BrandDestructiveButton

Coral/red button for dangerous actions.

```swift
BrandDestructiveButton(
    title: "Delete",
    icon: "trash",
    size: .medium
) {
    // action
}
```

**When to use:** Delete, remove, irreversible actions
**When NOT to use:** Cancel (use secondary), regular actions

---

### BrandIconButton

Circular icon-only button.

```swift
BrandIconButton(
    icon: "gear",
    size: 32,                           // Default 32px
    color: .brandTextSecondary,         // Default color
    hoverColor: .brandViolet            // Hover color
) {
    // action
}

// For destructive icon buttons:
BrandIconButton(icon: "trash", size: 28, hoverColor: .brandCoral) { }
```

**When to use:** Toolbars, compact actions, close buttons
**When NOT to use:** Primary actions (use BrandPrimaryButton)

---

### BrandMenuButton

Menu item with icon, title, optional shortcut and badge.

```swift
BrandMenuButton(
    icon: "gear",
    title: "Settings",
    shortcut: ",",            // Shows as ⌘,
    isSelected: false,
    badge: nil                // Optional badge like "3"
) {
    // action
}
```

**When to use:** Menu bar dropdowns, sidebar navigation
**When NOT to use:** In-content buttons

---

### BrandTabButton

Tab/segment selector.

```swift
BrandTabButton(
    title: "Meetings",
    icon: "waveform",         // Optional
    isSelected: true
) {
    // action
}
```

**When to use:** Tab bars, segmented controls
**When NOT to use:** Navigation links, menu items

---

### BrandListRow

Selectable list row with rich content.

```swift
BrandListRow(
    icon: "waveform",
    iconColor: .brandViolet,
    title: "Team Standup",
    subtitle: "Today at 9:00 AM",
    accessory: "45m",
    isSelected: false,
    showChevron: true
) {
    // action
}
```

**When to use:** Meeting lists, file lists, selectable items
**When NOT to use:** Simple text lists, menu items

---

### BrandSearchField

Search input with icon and clear button.

```swift
BrandSearchField(
    placeholder: "Search meetings...",
    text: $searchText,
    onSubmit: {               // Optional
        // search action
    }
)
```

**When to use:** Search bars
**When NOT to use:** Regular text input (use BrandTextField)

---

### BrandTextField

Text input with optional icon.

```swift
BrandTextField(
    placeholder: "Enter API key...",
    text: $apiKey,
    icon: "key"               // Optional
)
```

**When to use:** Form inputs, settings fields
**When NOT to use:** Search (use BrandSearchField)

---

### BrandStatusBadge

Meeting status indicator with icon.

```swift
BrandStatusBadge(
    status: .recording,       // .recording, .transcribing, .pending, .ready, .failed
    size: 32                  // Default 32px
)
```

| Status | Color | Icon |
|--------|-------|------|
| `.recording` | brandCoral | waveform |
| `.transcribing` | brandViolet | text.bubble |
| `.pending` | brandAmber | clock |
| `.ready` | brandMint | checkmark |
| `.failed` | brandCoral | exclamationmark |

---

### BrandBadge

Text badge/pill.

```swift
BrandBadge(
    text: "NEW",
    color: .brandViolet,      // Any brand color
    size: .medium             // .small, .medium
)
```

**When to use:** Labels, counts, tags
**When NOT to use:** Status indicators (use BrandStatusDot)

---

### BrandStatusDot

Simple colored dot indicator.

```swift
BrandStatusDot(
    status: .active,          // .active, .warning, .error, .success, .inactive
    size: 8,                  // Default 8px
    animated: false           // Pulsing animation
)
```

---

### BrandCard

Container with consistent styling.

```swift
BrandCard(padding: 20, showBorder: true) {
    // content
}
```

---

### BrandDivider

Styled separator.

```swift
BrandDivider(vertical: false, color: .brandBorder)
```

---

## Common Mistakes to Avoid

### ❌ Don't use system colors
```swift
// BAD
.foregroundColor(.accentColor)
.background(Color(.textBackgroundColor))

// GOOD
.foregroundColor(.brandViolet)
.background(Color.brandCreamDark)
```

### ❌ Don't hardcode corner radius
```swift
// BAD
.cornerRadius(6)
.cornerRadius(10)

// GOOD
.cornerRadius(BrandRadius.small)   // 8px
.cornerRadius(BrandRadius.medium)  // 16px
```

### ❌ Don't use system button styles
```swift
// BAD
Button("Save") { }
    .buttonStyle(.borderedProminent)

// GOOD
BrandPrimaryButton(title: "Save") { }
```

### ❌ Don't create inline button components
```swift
// BAD - Creating a one-off button
Button(action: action) {
    HStack { ... }
        .padding()
        .background(Color.accentColor.opacity(0.1))
}

// GOOD - Use existing component
BrandMenuButton(icon: "gear", title: "Settings") { action() }
```

### ❌ Don't forget .contentShape(Rectangle())
```swift
// BAD - Only icon is tappable
Button { } label: {
    HStack { Image(...); Text(...) }
        .padding()
        .background(...)
}

// GOOD - Entire area tappable
Button { } label: {
    HStack { Image(...); Text(...) }
        .padding()
        .background(...)
        .contentShape(Rectangle())
}
```

---

## File Locations

- **Components:** `MeetingRecorder/BrandComponents.swift`
- **Colors & Typography:** `MeetingRecorder/BrandAssets.swift`
- **Toast System:** `MeetingRecorder/ErrorToast.swift`

## Toast Notifications

Use `ToastController.shared` for notifications:

```swift
// Success
ToastController.shared.showSuccess(
    "Transcript ready",
    message: "Meeting title",
    action: ToastAction(title: "View") { /* action */ },
    onTap: { /* tap anywhere action */ }
)

// Error
ToastController.shared.showError("Failed", message: "Details")

// Warning
ToastController.shared.showWarning("Low storage", message: "5GB remaining")

// Info
ToastController.shared.showInfo("Processing...", message: "Details")
```
