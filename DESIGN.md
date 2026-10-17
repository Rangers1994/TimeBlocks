# TimeBlocks — Design Document

**Version:** 1.0
**Date:** 2026-10-11
**Platform:** iOS (iPhone first), SwiftUI + SwiftData

---

## 1. Purpose & Vision

TimeBlocks teaches students time management by making a day *visible*. Each day
is presented as a grid of 96 blocks — 24 rows (one per hour) × 4 columns (one
per 15-minute increment). Students "paint" the grid with color-coded,
emoji-labeled activity categories (sleep, school, homework, sports, free time,
travel, …), plan their day, save it, and later review monthly summaries of how
their time was actually allocated.

### Goals
- Make an abstract concept (a 24-hour day) concrete and tactile.
- Fast, fun block painting — planning a day should take under 2 minutes.
- Honest feedback: monthly summaries show where time really goes.
- Tiny footprint: a full year of schedules must cost almost nothing in storage
  or memory on a modern smartphone.

### Non-Goals (v1)
- No accounts, sync, or sharing (data stays on device; CloudKit is a future option).
- No notifications/reminders.
- No sub-15-minute granularity.
- No overlapping activities — each block holds exactly one category.

---

## 2. Core Concepts

| Concept | Definition |
|---------|------------|
| **Block** | One 15-minute slot. A day has exactly 96 blocks. |
| **Grid** | The 24×4 visual layout of a day. Row = hour (00–23), column = quarter (:00, :15, :30, :45). |
| **Category** | A reusable activity type: name + color + emoji symbol (e.g. 🌙 Sleep on dark purple). |
| **Day Schedule** | A date plus the category assignment for each of its 96 blocks. |
| **Template** | The default fill applied to a new day: Sleep from 22:00–06:00, Free Time everywhere else. |
| **Summary** | An aggregation of saved days over a month: hours per category, trends. |

---

## 3. Data Model

### 3.1 Design principle: one byte per block

The single most important efficiency decision: a day's schedule is stored as a
**96-byte `Data` blob**, one byte per 15-minute block, where each byte is a
category index (0–255).

```
Day storage:      96 bytes
One year (365d):  ~35 KB of block data
```

Even with SwiftData row overhead, indexes, and category metadata, a full year
of schedules comfortably fits in **well under 1 MB**. In-memory, an entire
year can be held at once for summaries without any paging strategy.

This beats the naive alternative (a `Block` entity per slot = 96 rows/day =
~35,000 database rows/year) by orders of magnitude in both space and query
cost, and makes save/load a single read/write.

### 3.2 SwiftData models

```swift
@Model
final class Category {
    var id: UInt8              // stable index used in day blobs (0–255)
    var name: String           // "Sleep", "School", …
    var emoji: String          // "🌙", "📚", … (any emoji, user-pickable)
    var colorHex: String       // "#4B2E83" — hex keeps the model Codable-simple
    var sortOrder: Int         // palette ordering
    var isBuiltIn: Bool        // built-ins can be edited but not deleted
}

@Model
final class DaySchedule {
    @Attribute(.unique) var dayKey: Int   // yyyymmdd as Int, e.g. 20261011
    var blocks: Data                      // exactly 96 bytes; blocks[i] = category id
    var modifiedAt: Date
}

@Model
final class MonthTemplate {
    @Attribute(.unique) var key: Int   // monthKey * 10 + kind
    var monthKey: Int                  // yyyymm — templates are per month
    var kind: Int                      // 0 = weekday, 1 = weekend
    var blocks: Data                   // 96 bytes, same format as DaySchedule
    var modifiedAt: Date
}
```

Notes:
- `dayKey` as an `Int` (e.g. `20261011`) gives cheap, index-friendly uniqueness
  and trivial month-range queries (`dayKey >= 20261001 && dayKey <= 20261031`).
  It avoids all time-zone ambiguity that raw `Date` keys suffer from.
- Category **id 0 is reserved for Free Time** and id 1 for Sleep, so a
  freshly-templated day is mostly zeros (also compresses well if we ever add
  export).
- Deleting a category remaps its blocks to Free Time (id 0) across stored days;
  since each day is 96 bytes, remapping a whole year is a trivial pass.
- The existing placeholder `Item.swift` model will be removed.

### 3.3 Built-in categories (seeded on first launch)

| ID | Name | Emoji | Color |
|----|------|-------|-------|
| 0 | Free Time | ⭐️ | Yellow |
| 1 | Sleep | 🌙 | Dark purple |
| 2 | School | 📚 | Orange |
| 3 | Homework | ✏️ | Blue |
| 4 | Sports | 🏃 | Green |
| 5 | Getting Ready / Travel | 🚌 | Gray |
| 6 | Meals | 🍽️ | Teal |

Users can edit these (rename, recolor, change emoji) and add their own, using
the **system emoji keyboard** for full emoji choice. Up to 255 custom
categories (practically unlimited).

### 3.4 Default day template

A new/unsaved day is pre-filled:
- **Sleep (id 1):** 22:00 → 24:00 and 00:00 → 06:00 (8 hours, starting 10 pm).
- **Free Time (id 0):** all remaining blocks (06:00 → 22:00).

v1 hardcodes this template; a user-editable template is a natural v1.1 feature.

### 3.5 Retention

- Target: **up to one year** of history.
- On launch, delete `DaySchedule` rows older than 366 days. At ~100 bytes/day
  this is about hygiene and summary-range honesty, not space pressure.

---

## 4. Visual Theme & Branding

### 4.1 Aesthetic

**Fun and playful.** The app should feel like a toy that happens to teach —
closer to a block-building game than a productivity tool.

- **Palette bias: blue and orange.** Primary blue (`#2D7DD2` family) for
  chrome, navigation, and backgrounds; warm orange (`#FF8C42` family) for
  accents, buttons, and highlights; sunny yellow as the supporting accent
  (free time, the pencil). Category colors stay fully saturated and cheerful.
- **Typography:** SF Rounded throughout (`.rounded` design), heavy weights
  for titles. No custom fonts needed.
- **Shape language:** generous corner radii, chunky controls, soft drop
  shadows — everything looks like a physical block you could pick up.
- **Motion:** springy, bouncy animations (scale-in, wobble); subtle haptics
  when painting blocks.

### 4.2 Logo

A cluster of **jenga-style wooden-toy blocks floating dynamically** in sample
category colors — dark purple 🌙, orange 📚, green 🏃, blue ⏰ — with a **big
yellow pencil** crossing the cluster diagonally. Blocks are drawn with a
simple 3D extrusion (lit top face, shaded side face) and gently bob as if
weightless.

The logo is **rendered entirely in SwiftUI vector shapes** — no image assets,
infinitely scalable, animatable, and ~zero storage cost (consistent with §3's
efficiency goals). The app icon is a static composition of the same elements.

### 4.3 Launch splash

On app start, a splash screen shows for **~2.5 seconds**:
- Blue gradient background.
- The animated logo: blocks float/bob with staggered phases; the pencil sways
  slightly.
- The title **TimeBlocks** in bubble-style letters — heavy rounded type,
  alternating orange/light-blue letters, each slightly rotated, popping in
  one-by-one with a spring.
- The splash then cross-fades into the Calendar screen.

The splash overlays the real root view (which loads underneath), so it never
*adds* to cold-start time — it masks it.

## 5. App Structure & Screens

```
TabView
 ├── 📅 Calendar  (MonthCalendarView → zoom into DayGridView)
 ├── 📊 Summary   (MonthSummaryView)
 └── 🎨 Categories (CategoryListView / CategoryEditorView)
```

### 5.1 Calendar screen (zoomed-out view)

The entry point of the app: a month-at-a-time calendar grid (7 columns ×
5–6 week rows) that shows **at a glance which days have been planned**.

**Day cell rendering**
- **Populated day:** a miniature thumbnail of that day's schedule — the 96
  blocks drawn as a tiny color strip/grid inside the cell. Even at thumbnail
  size, color dominance is legible (a mostly-orange day reads "school day").
- **Unpopulated (editable) day:** empty outlined cell with the day number.
- **Out-of-range day** (older than 1 year, or more than 1 month ahead):
  dimmed and non-interactive.
- **Today:** highlighted ring.

**Navigation**
- Swipe or ◀︎ ▶︎ to move between months; "Today" button jumps back.
- Browsable range: 12 months back → 1 month forward (matching the editable
  window, §7).

**Zoom interaction**
- Tapping a day cell zooms into the full `DayGridView` for that date using
  the system zoom transition (`navigationTransition(.zoom)` with
  `matchedTransitionSource`) — the thumbnail visually expands into the full
  24×4 editor, reinforcing that the editor *is* that calendar cell up close.
  Pinch-out on a cell triggers the same navigation.
- Back (or pinch-in / swipe-down) returns to the calendar, where the edited
  day's thumbnail now reflects the changes.

**Day copy/paste**
- Long-press a planned day → *Copy Day*; long-press a target → *Paste Day*.
- Pasting onto a non-blank day asks for overwrite confirmation.

**Month templates (weekday / weekend)**
- Each month has two template slots — **Weekday** and **Weekend** — shown in a
  tray at the bottom of the calendar. Templates are scoped per month, so
  October's school-day plan can differ from November's.
- Long-press a planned day → *Set as Weekday Template* / *Set as Weekend
  Template* captures that day's plan into the displayed month's slot.
- **Drag a template from the tray onto a day cell** to apply it. Blank days
  fill immediately; non-blank days ask for overwrite confirmation (same rule
  as paste). Long-press a slot to clear it.

**Efficiency**
- A month view needs ≤31 `DaySchedule` rows (≤3 KB of blob data). Thumbnails
  are drawn in the same single-`Canvas` pass as the calendar grid itself — no
  per-day image caching needed; redrawing from 96 bytes is cheaper than
  caching bitmaps.
- Templates add ≤2 × 96-byte rows per month (~2.3 KB/year).

### 5.2 Day screen (zoomed-in editor, core experience)

**Layout**
- Date bar at top: ◀︎ / date (tap for `DatePicker`) / ▶︎, plus a "Today"
  shortcut — so students can step between adjacent days without zooming out.
  Stepping is clamped to the editable window (§7).
- The 24×4 grid fills the remaining screen. Hour labels (12 AM … 11 PM) gutter
  on the left; column headers `:00 :15 :30 :45` on top.
- Each cell: rounded rect in the category color; the emoji is rendered once
  per *contiguous run* of a category within the row (centered on the run), not
  in every cell — keeps the grid readable rather than noisy.
- A horizontally scrolling **category palette** sits at the bottom: tap to arm
  a "brush".

**Interaction**
- Tap a cell → paints it with the armed category.
- Drag across cells → paints a range (the primary gesture; a whole day can be
  painted in a few swipes).
- Long-press a cell → eyedropper: arms that cell's category.
- Undo/redo via standard shake / toolbar buttons (`UndoManager`), since a
  stray drag can wipe out careful work.
- Changes **auto-save** (debounced ~1 s after last edit). No explicit Save
  button to lose work behind.

**Grid rendering strategy**
- The grid is a single `Canvas` (not 96 separate views). One view, one draw
  pass, trivial hit-testing by geometry (`row = y / cellHeight`,
  `col = x / cellWidth`). This is the memory/CPU-efficient choice and makes
  drag-painting smooth at 120 Hz.
- Cell size adapts to screen; on small iPhones the grid remains fully visible
  without scrolling (that "whole day at a glance" view *is the product*).

### 5.3 Summary screen

- Month picker (default: previous month; range limited to the last 12 months).
- **Hours-per-category** list: emoji + name, total hours, % of month, rendered
  with Swift Charts bars.
- Secondary visual: a mini month heatmap — each day as a tiny 96-block strip —
  so students can *see* consistency (e.g., sleep drifting later).
- Computation: fetch the month's `DaySchedule` rows (≤31 × 96 bytes ≈ 3 KB),
  count bytes per category id. This is fast enough to do on the fly — **no
  denormalized summary tables**, no cache invalidation bugs.

### 5.4 Categories screen

- List of categories (built-in + custom), reorderable.
- Editor sheet: name field, emoji field (system keyboard), `ColorPicker`.
- Delete (custom only) with confirmation: "Blocks using this will become Free
  Time."

---

## 6. Architecture

- **Pattern:** SwiftUI + SwiftData, `@Observable` view models where logic
  outgrows the view (grid editing, summaries). No Combine; async/await for
  anything asynchronous.
- **Key types:**
  - `DayGridModel` (`@Observable`): owns the working copy of a day's 96 bytes
    as `[UInt8]`, exposes paint/fill/undo operations, debounces persistence.
  - `TemplateProvider`: produces the default 96-byte array for a new day.
  - `SummaryCalculator`: pure function `(days: [DaySchedule]) -> [CategoryID: Int]`
    (block counts) — trivially unit-testable.
  - `DayKey`: small value type converting `Date ↔ Int(yyyymmdd)` in the user's
    current calendar/time zone.
- **Colors:** stored as hex strings, converted via a small `Color(hex:)`
  extension; category colors get a computed `Color` once and are cached per
  render pass.

### 6.1 Efficiency commitments (summary)

| Concern | Decision |
|---------|----------|
| Storage | 96 bytes/day blob; < 1 MB/year total including overhead |
| DB rows | 1 row per day (≤366) + ~dozens of categories; no per-block rows |
| Grid rendering | Single `Canvas`, one draw pass, no 96-view hierarchy |
| Summaries | Computed on demand from ≤3 KB of month data; nothing precomputed |
| Images/assets | Emoji are text — zero image assets for category symbols |

---

## 7. Edge Cases & Rules

- **DST days** (23/25-hour days): the grid always shows 24 nominal hours; v1
  deliberately ignores DST block-count differences for simplicity.
- **Time zone travel:** `dayKey` is derived from the user's current time zone
  at save time; a day is whatever the user's calendar says it is.
- **Editable window:** from 12 months before today through **1 month after
  today**. Planning ahead is the point, but capping it at one month keeps
  students focused on near-term planning rather than speculative filling.
  The window is evaluated against "today" at interaction time.
- **Past dates:** editable within the window (students correct "what actually
  happened").
- **Window edge:** a day planned in advance never becomes uneditable by
  moving *into* the window — only very old days (> 1 year) age out.
- **Unsaved template days:** a day that was never touched is *not* persisted;
  summaries only count days the student actually saved (otherwise the template
  would pollute statistics).

---

## 8. Testing Strategy

(Swift Testing for unit tests, XCUIAutomation for UI tests.)

- **Unit:** `DayKey` date↔key conversions (incl. year boundaries, time zones);
  `TemplateProvider` output (exactly 32 sleep + 64 free blocks, correct
  positions); `SummaryCalculator` aggregation; category deletion remap;
  retention pruning; editable-window clamping (−12 months … +1 month,
  inclusive boundaries).
- **UI:** calendar shows populated vs. empty day cells; tapping a cell zooms
  into the correct day; days beyond +1 month are not tappable; paint-by-tap
  updates a cell; drag paints a range; switching dates preserves saved data;
  summary reflects a painted day.

---

## 9. Future Ideas (explicitly out of scope for v1)

- Planned vs. actual comparison (two layers per day).
- CloudKit sync & multi-device.
- Streaks/gamification for consistent planning.
- Export month summary as image/PDF for parents or teachers.
