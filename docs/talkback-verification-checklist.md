# TalkBack Verification Checklist — kokoitta

**Purpose:** Manual accessibility verification on Android emulator using TalkBack.
**Scope:** Representative user flow (#90 AC #2): launch → main operations → completion.
**Device:** Android Emulator (Pixel 6 API 35 or equivalent).
**When to run:** After all automated tests pass, before closing #90.

---

## Prerequisites

### Emulator setup

```bash
# Create and start AVD (if not already available)
flutter emulators --launch Pixel_6_API_35

# Or use existing AVD
flutter emulators --list
```

### Enable TalkBack

1. Open **Settings** → **Accessibility** → **TalkBack**
2. Toggle **Use TalkBack** → ON
3. Confirm the TalkBack tutorial appears
4. Dismiss the tutorial (swipe right → right → right → double-tap "Close")

### TalkBack navigation basics (reference)

| Gesture | Action |
|---------|--------|
| Swipe right | Move to next item |
| Swipe left | Move to previous item |
| Double-tap | Activate focused item |
| Swipe up then down (L) | Scroll down |
| Swipe down then up (reverse L) | Scroll up |
| Two-finger swipe up/down | Scroll content |

---

## Test flow

### Phase 1: App launch (空home)

**Objective:** Verify the app launches without TalkBack errors and the home screen is readable.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 1.1 | Launch the app | App name "ここいった" announced | ☐ |
| 1.2 | Wait for home screen to load | "地図" tab announced as selected | ☐ |
| 1.3 | Swipe right to explore home | Tab labels read in visual order: 地図, 旅行 | ☐ |
| 1.4 | Swipe right through map area | Prefecture state labels announced (e.g. "東京都 訪問済み") | ☐ |
| 1.5 | Swipe right to bottom nav | "地図" (selected), "旅行" navigation destinations | ☐ |
| 1.6 | Double-tap "旅行" tab | Tab switches, "旅行" announced as selected | ☐ |
| 1.7 | Verify empty state | "旅行がありません" or equivalent empty state message announced | ☐ |
| 1.8 | Double-tap "地図" tab | Returns to map tab | ☐ |

**Issues found:** _________________________________

---

### Phase 2: Add photos via Android share

**Objective:** Verify the import flow is accessible end-to-end.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 2.1 | From home, swipe to "写真を共有" button | Button label announced with "double-tap to activate" hint | ☐ |
| 2.2 | Double-tap to open share picker | Share sheet / photo picker opens | ☐ |
| 2.3 | Select a synthetic test photo | Photo selected | ☐ |
| 2.4 | Confirm import | Progress indicator announced (e.g. "取り込み中") | ☐ |
| 2.5 | Wait for completion | Success message or trip card appears | ☐ |
| 2.6 | Swipe to the new trip card | Trip title announced with position (e.g. "旅行 1件目") | ☐ |

**Issues found:** _________________________________

---

### Phase 3: Trip list → Trip detail → Photo viewer

**Objective:** Verify navigation through trip screens with TalkBack.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 3.1 | Double-tap the trip card | Opens trip detail view | ☐ |
| 3.2 | Verify detail screen title | Trip name announced as screen title | ☐ |
| 3.3 | Swipe through photo grid | Each photo announces position (e.g. "写真 1/5") | ☐ |
| 3.4 | Double-tap a photo | Opens photo viewer (full screen) | ☐ |
| 3.5 | Verify viewer | "写真" or photo title announced | ☐ |
| 3.6 | Swipe right in viewer | Previous/next navigation announced | ☐ |
| 3.7 | Double-tap back button | Returns to trip detail | ☐ |
| 3.8 | Swipe to overflow menu (⋮) | "もっと見る" or menu button announced | ☐ |
| 3.9 | Double-tap overflow menu | Menu opens with options | ☐ |
| 3.10 | Verify menu items | "写真を共有", "旅行未設定へ移動", "旅行を削除" announced | ☐ |
| 3.11 | Double-tap "戻る" or back | Returns to trip list | ☐ |

**Issues found:** _________________________________

---

### Phase 4: Delete trip → Undo

**Objective:** Verify destructive action accessibility and undo.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 4.1 | Open trip detail, swipe to overflow menu | Menu button announced | ☐ |
| 4.2 | Double-tap menu, then "旅行を削除" | "旅行を削除" announced | ☐ |
| 4.3 | Confirmation dialog appears | Dialog title and both buttons announced | ☐ |
| 4.4 | Double-tap "削除" to confirm | Trip deleted, SnackBar appears | ☐ |
| 4.5 | Swipe to SnackBar | "Undo" button announced with trip name | ☐ |
| 4.6 | Double-tap "Undo" | Trip restored, SnackBar dismissed | ☐ |
| 4.7 | Verify trip is back | Trip card re-appears in list | ☐ |

**Issues found:** _________________________________

---

### Phase 5: Settings / Backup

**Objective:** Verify settings and backup flow accessibility.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 5.1 | Swipe to settings icon (top-right) | "設定" button announced | ☐ |
| 5.2 | Double-tap settings | Opens settings screen | ☐ |
| 5.3 | Swipe through settings items | "外観", "文字サイズと読み上げ" announced | ☐ |
| 5.4 | Swipe to backup section | "完全バックアップを作成" announced with subtitle | ☐ |
| 5.5 | Verify busy state (if applicable) | "処理中のため利用できません" announced when busy | ☐ |
| 5.6 | Double-tap "完全バックアップを作成" | Backup starts or confirmation appears | ☐ |
| 5.7 | If confirmation dialog | Dialog title and buttons announced | ☐ |
| 5.8 | Double-tap cancel/back | Returns to settings | ☐ |
| 5.9 | Swipe to restore section | "完全復元" announced | ☐ |
| 5.10 | Double-tap back | Returns to main screen | ☐ |

**Issues found:** _________________________________

---

### Phase 6: Prefecture list (fallback view)

**Objective:** Verify the prefecture list fallback is accessible.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 6.1 | From map tab, swipe to a prefecture | Prefecture name and state announced (e.g. "北海道 未訪問") | ☐ |
| 6.2 | Double-tap a prefecture | State picker or state toggle opens | ☐ |
| 6.3 | Select a state | State changes, announcement confirms | ☐ |
| 6.4 | Swipe back to map | Updated state reflected in map | ☐ |

**Issues found:** _________________________________

---

### Phase 7: Theme and text scale (200%)

**Objective:** Verify TalkBack works under stress conditions.

| Step | Action | Expected TalkBack announcement | Pass |
|------|--------|-------------------------------|------|
| 7.1 | Go to device Settings → Accessibility → Text size | Text size settings open | ☐ |
| 7.2 | Set text scale to 200% (最大) | Text enlarges across system | ☐ |
| 7.3 | Return to kokoitta app | App re-renders at 200% text | ☐ |
| 7.4 | Swipe through home screen | All text readable, no overflow, no clipping | ☐ |
| 7.5 | Navigate to trip list | Empty state or trip cards readable at 200% | ☐ |
| 7.6 | Open trip detail | Grid/layout remains usable at 200% | ☐ |
| 7.7 | Open settings | Backup/restore actions visible and accessible | ☐ |
| 7.8 | Verify dark theme (optional) | Switch to dark theme, repeat swipe-through | ☐ |

**Issues found:** _________________________________

---

### Phase 8: Focus and touch target audit

**Objective:** Verify focus order and touch target sizes.

| Step | Action | Expected | Pass |
|------|--------|----------|------|
| 8.1 | Swipe through entire home screen in order | Focus follows visual order (top→bottom, left→right) | ☐ |
| 8.2 | Verify no focus trap | Can always reach back/close via swipe | ☐ |
| 8.3 | Check primary action buttons | All primary buttons can be double-tapped without precision | ☐ |
| 8.4 | Verify dialog focus | When dialog opens, focus moves to dialog (not background) | ☐ |
| 8.5 | Close dialog | Focus returns to triggering element | ☐ |
| 8.6 | Check bottom sheet | When bottom sheet opens, focus moves to sheet content | ☐ |
| 8.7 | Close bottom sheet | Focus returns to triggering element | ☐ |

**Issues found:** _________________________________

---

## Issues log

| # | Phase | Step | Severity | Description | Status |
|---|-------|------|----------|-------------|--------|
| | | | | | |

### Severity definitions

- **Critical:** App unusable with TalkBack (crash, focus trap, invisible control)
- **Major:** Significant flow blocked or confusing (missing label, wrong order)
- **Minor:** Cosmetic or non-blocking (redundant announcement, suboptimal hint)
- **Info:** Observation, no fix needed

---

## Sign-off

| Item | Value |
|------|-------|
| Tester | |
| Date | |
| Emulator | |
| Android API level | |
| Flutter version | |
| App commit SHA | |
| Phases passed | / 8 |
| Critical issues | |
| Major issues | |
| Minor issues | |
| **Verdict** | PASS / FAIL (BLOCKER: ___) |
