# UI Visibility Timing Updates - December 10, 2025

## Issues Fixed

### 1. ✅ UI Not Hiding Without Orientation Change
**Problem**: UI would only hide when device was rotated, not based on timer alone
**Root Cause**: Missing `.animation()` modifiers on the main ZStack
**Solution**: Added explicit animation modifiers that trigger when `isUIVisible` and `isPreviewVisible` change

### 2. ✅ Preview Hiding Too Fast During Recording
**Problem**: Preview would hide after 10 seconds even during video recording
**Solution**: Implemented dynamic timing based on recording state

### 3. ✅ New Timing Requirements Implemented

## New Timing Configuration

| State | UI Buttons Hide | Preview Hides | Capture Button |
|-------|----------------|---------------|----------------|
| **Not Recording** | 5 seconds | 60 seconds (1 minute) | NEVER hides |
| **Recording Video** | 5 seconds | 300 seconds (5 minutes) | NEVER hides |

## Changes Made

### UIVisibilityManager.swift

#### 1. New Timing Constants
```swift
private let uiHideDelay: TimeInterval = 5.0                    // 5 seconds
private let previewHideDelayNormal: TimeInterval = 60.0        // 1 minute
private let previewHideDelayRecording: TimeInterval = 300.0    // 5 minutes
```

#### 2. Recording State Tracking
```swift
private var isRecording = false

func setRecordingState(_ recording: Bool) {
    let wasRecording = isRecording
    isRecording = recording
    
    if wasRecording != recording {
        print("👁️ UIVisibilityManager: 🎥 Recording state changed: \(recording)")
        startTimers()  // Restart with new timing
    }
}
```

#### 3. Dynamic Preview Timing
```swift
private func startTimers() {
    // Calculate preview delay based on recording state
    let previewDelay = isRecording ? previewHideDelayRecording : previewHideDelayNormal
    
    previewHideTimer = Timer.scheduledTimer(withTimeInterval: previewDelay, repeats: false) { timer in
        self?.hidePreview()
    }
}
```

#### 4. Fixed Timer Thread Issues
- Ensured timers are ALWAYS created on main thread
- Removed unnecessary `DispatchQueue.main.async` wrappers that could cause issues
- Added thread check to prevent timer creation on background threads

```swift
guard Thread.isMainThread else {
    DispatchQueue.main.async { [weak self] in
        self?.startTimers()
    }
    return
}
```

#### 5. Removed `withAnimation` from State Changes
**Before:**
```swift
withAnimation(.easeOut(duration: 0.3)) {
    isUIVisible = false
}
```

**After:**
```swift
isUIVisible = false  // Animation handled by ContentView
```

**Why**: Having animation in both the manager AND the view can cause conflicts

### ContentView.swift

#### 1. Added Recording State Tracking
```swift
.onChange(of: viewModel.isRecording) { oldValue, newValue in
    print("📱 ContentView: Recording state changed from \(oldValue) to \(newValue)")
    viewModel.uiVisibilityManager.setRecordingState(newValue)
}
```

#### 2. Added Animation Modifiers to Main ZStack
```swift
ZStack {
    // All UI content...
}
.animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isUIVisible)
.animation(.easeInOut(duration: 0.5), value: viewModel.uiVisibilityManager.isPreviewVisible)
```

**Why This Works:**
- `.animation()` triggers whenever the specified value changes
- Applies to ALL views in the ZStack that depend on that value
- Works regardless of orientation changes
- Ensures smooth transitions

#### 3. Improved Button Transitions
Changed from:
```swift
.transition(.opacity)
```

To:
```swift
.transition(.opacity.combined(with: .scale(scale: 0.8)))
```

Buttons now fade AND scale down slightly when hiding (more polished)

#### 4. Fixed Build Error
Removed invalid `else` block with `print()` statement that can't return a View

## Testing Instructions

### Test 1: UI Hiding (Portrait Mode) ✅
1. Open app in portrait mode
2. **Don't touch the screen**
3. After **5 seconds**: Flash, Mode, Gallery buttons should fade out
4. Capture button and recording timer should remain visible
5. After **60 seconds** (1 minute): Preview should fade to black
6. Only capture button and red dot should be visible

### Test 2: UI Hiding (Landscape Mode) ✅
1. Rotate to landscape mode
2. **Don't touch the screen**
3. After **5 seconds**: Three buttons (Flash, Mode, Gallery) should fade out
4. Capture button should remain visible on right side
5. After **60 seconds**: Preview should fade to black
6. Only capture button should be visible on right side

### Test 3: Preview Timing During Recording ✅
1. Start video recording
2. **Don't touch the screen**
3. After **5 seconds**: UI buttons should hide
4. After **60 seconds**: Preview should STILL be visible (not hidden yet!)
5. After **5 minutes** (300 seconds): Preview should fade to black
6. Capture button should remain visible to stop recording

### Test 4: Interaction Resets Timers ✅
1. Wait for UI to hide (5 seconds)
2. Tap the screen
3. **Expected**: All UI immediately reappears
4. **Expected**: Timers restart from 0

### Test 5: Orientation Changes Don't Affect Timers ✅
1. Wait 3 seconds (UI will hide in 2 more seconds)
2. Rotate device from portrait to landscape
3. **Expected**: UI should still hide after 2 seconds (not restart)
4. **Expected**: No layout glitches or duplicate buttons

## Console Output Examples

### App Launch:
```
👁️ UIVisibilityManager: ========== INITIALIZED ==========
👁️ UIVisibilityManager: UI hide delay: 5.0s
👁️ UIVisibilityManager: Preview hide delay (normal): 60.0s (60s = 1 min)
👁️ UIVisibilityManager: Preview hide delay (recording): 300.0s (300s = 5 min)
```

### Recording Starts:
```
📱 ContentView: Recording state changed from false to true
👁️ UIVisibilityManager: 🎥 Recording state changed: true
👁️ UIVisibilityManager: 🎥 Preview will hide after 300.0s
👁️ UIVisibilityManager: ========== STARTING TIMERS (Count: 2) ==========
```

### UI Hides:
```
👁️ UIVisibilityManager: ⏰⏰⏰ UI TIMER FIRED at 2025-12-10 20:45:33 +0000 ⏰⏰⏰
👁️ UIVisibilityManager: ========== HIDING UI ==========
👁️ UIVisibilityManager: ============ isUIVisible changed from true to false ============
```

### Preview Hides (Normal):
```
👁️ UIVisibilityManager: ⏰⏰⏰ PREVIEW TIMER FIRED at 2025-12-10 20:46:28 +0000 ⏰⏰⏰
👁️ UIVisibilityManager: ========== HIDING PREVIEW ==========
👁️ UIVisibilityManager: ============ isPreviewVisible changed from true to false ============
👁️ UIVisibilityManager: ⚫️⚫️⚫️ PREVIEW IS NOW HIDDEN ⚫️⚫️⚫️
⚫️ ContentView: Preview is HIDDEN (isPreviewVisible = false)
```

## Architecture Overview

```
ContentView
    ↓ (onChange isRecording)
UIVisibilityManager.setRecordingState()
    ↓ (recalculates timing)
startTimers() → creates Timer with correct delay
    ↓ (after delay)
hideUI() / hidePreview()
    ↓ (changes @Published properties)
ContentView receives update
    ↓ (.animation modifier)
UI fades in/out smoothly
```

## Key Improvements

1. **Separation of Concerns**
   - UIVisibilityManager: Manages LOGIC (timers, state)
   - ContentView: Manages PRESENTATION (animations)

2. **Thread Safety**
   - All timers created on main thread
   - Prevents timer invalidation issues

3. **Dynamic Timing**
   - Preview hide time adapts to recording state
   - Prevents accidental screen-off during important recordings

4. **Smooth Animations**
   - Consistent animation durations
   - Works regardless of orientation
   - No layout glitches

## Known Behaviors

1. **Capture button NEVER hides**: Intentional design so user can always capture/stop recording
2. **Recording timer always visible when preview visible**: Ensures user knows recording is active
3. **Red dot visible when preview hidden during recording**: Visual feedback that recording continues
4. **Timers restart on interaction**: Every tap/button press resets both timers to prevent premature hiding

## Future Enhancements (Optional)

1. Add user preference for timing customization
2. Add visual countdown before preview hides (e.g., "Preview hiding in 10s...")
3. Add haptic feedback when UI hides
4. Add "keep screen on" option for long recordings
5. Show notification when preview is hidden during recording
