# Double-Tap UI Toggle Implementation

## Overview
Changed the UI visibility behavior from automatic timer-based hiding to manual double-tap toggle control, while keeping the preview auto-hide functionality during recording.

## Changes Summary

### UI Visibility Control
**Before:**
- UI buttons automatically faded out after 5 seconds of inactivity
- Any interaction (taps, button clicks, slider adjustments) would reset the timer
- Required complex timer management and state tracking

**After:**
- UI buttons remain visible until user explicitly hides them with a double-tap gesture
- Double-tap anywhere on the screen to toggle UI visibility (show/hide)
- Much simpler and more predictable behavior

### Preview Visibility (Unchanged)
- Preview still auto-hides after 1 minute of inactivity (normal mode)
- Preview still auto-hides after 5 minutes during recording
- Single tap shows preview and resets the preview timer

## Implementation Details

### 1. UIVisibilityManager Changes
**Removed:**
- `uiHideTimer` - No longer needed
- `uiHideDelay` constant - No longer needed
- UI timer creation and management in `startTimers()`
- `hideUI()` automatic hiding logic

**Added:**
- `toggleUI()` - New method to manually toggle UI visibility
- Simplified `userDidInteract()` - Now only manages preview timer

**Kept:**
- `previewHideTimer` - Still manages automatic preview hiding
- Preview hide delays (1 min normal, 5 min recording)
- Recording state tracking for preview timing

### 2. CameraViewModel Changes
**Already had:**
- `handleUserInteraction()` - Shows UI/preview and resets preview timer
- `toggleUIVisibility()` - Toggles UI on/off

### 3. ContentView Changes

#### Tap Gesture Handling
```swift
// Double-tap gesture (must be declared FIRST to take priority)
.onTapGesture(count: 2) {
    viewModel.toggleUIVisibility()  // Toggle UI visibility
}
// Single-tap gesture
.onTapGesture {
    viewModel.handleUserInteraction()  // Show preview, reset preview timer
}
```

**Important:** The double-tap gesture must be declared before the single-tap gesture in SwiftUI, as gestures are evaluated in the order they're added.

#### Removed Timer Reset Calls
Removed `viewModel.handleUserInteraction()` from:
- All button actions (capture, flash, mode switch, gallery)
- Zoom slider changes
- Other UI interactions

These no longer need to reset any timer since UI visibility is now manual.

## User Experience

### Gesture Controls
1. **Single Tap**: 
   - Shows preview if hidden
   - Resets preview auto-hide timer
   - Does NOT affect UI button visibility

2. **Double Tap**:
   - Toggles UI buttons visibility (on ↔ off)
   - Allows clean, unobstructed view of camera preview
   - UI state persists until next double-tap

3. **Button Interactions**:
   - No longer affect timers
   - Can be used freely without worrying about UI hiding

### Visual Behavior
- **UI Elements** (flash, mode, gallery buttons, zoom slider):
  - Start visible
  - Stay visible indefinitely
  - Hide only when user double-taps
  - Smooth 300ms fade animation

- **Capture Button**:
  - Always visible when preview is visible (landscape & portrait)
  - Becomes the only visible button when preview is hidden

- **Preview**:
  - Auto-hides after inactivity (1 min / 5 min)
  - Single tap restores it
  - Hides UI controls when preview hides

## Benefits

### For Users
1. **More Control**: User decides when to hide/show UI
2. **Predictable**: No surprise auto-hiding while composing shots
3. **Cleaner**: Can easily hide all UI for unobstructed view
4. **Faster**: Don't need to "race" against a timer

### For Developers
1. **Simpler Code**: Less timer management complexity
2. **Fewer Bugs**: No race conditions or timer conflicts
3. **Better Performance**: One timer instead of two
4. **Easier Maintenance**: Clearer separation of concerns

## Testing Checklist

### UI Visibility
- ✅ UI starts visible on app launch
- ✅ Double-tap hides UI (buttons fade out)
- ✅ Double-tap again shows UI (buttons fade in)
- ✅ UI stays in chosen state (no auto-hiding)
- ✅ Smooth animations (300ms fade)

### Preview Visibility
- ✅ Preview auto-hides after 1 minute (not recording)
- ✅ Preview auto-hides after 5 minutes (while recording)
- ✅ Single tap restores preview
- ✅ Preview timer resets on single tap

### Gestures
- ✅ Double-tap recognized reliably
- ✅ Single-tap doesn't trigger after double-tap
- ✅ Works in both portrait and landscape
- ✅ Works when preview is visible or hidden

### Recording
- ✅ Can start/stop recording with UI hidden
- ✅ Recording indicator still visible when UI hidden
- ✅ Preview timer extends to 5 minutes during recording
- ✅ Capture button always accessible

## Code Quality Improvements

1. **Separation of Concerns**:
   - UI visibility = manual control
   - Preview visibility = automatic timer

2. **Clear Naming**:
   - `toggleUIVisibility()` - Explicit about what it does
   - `handleUserInteraction()` - Only affects preview now

3. **Reduced Complexity**:
   - One timer instead of two
   - Fewer state transitions to manage
   - Less debugging output needed

## Migration Notes

If updating from previous version:
1. Remove any code that was resetting UI timer on interactions
2. Update gesture handling to use double-tap for UI toggle
3. Keep preview timer logic unchanged
4. Test double-tap sensitivity on target devices

## Future Enhancements

Possible improvements:
1. Add haptic feedback on double-tap
2. Configurable gesture (triple-tap, long-press, etc.)
3. Remember UI state between app launches
4. Custom gesture sensitivity settings
5. Visual indicator when UI toggle is activated
