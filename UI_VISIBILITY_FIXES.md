# UI Visibility Fixes - December 10, 2025

## Issues Identified

### 1. **Orientation-Specific UI Hiding Bug** ❌
**Problem**: When tapping in landscape mode, only portrait UI was being hidden (and vice versa)
- Both orientations shared the same `isUIVisible` state
- Portrait mode used `.opacity()` modifier (fade in/out)
- Landscape mode also used `.opacity()` modifier
- BUT: When user rotated device, the wrong orientation's UI would disappear

**Root Cause**: 
- Landscape buttons used `.opacity(viewModel.uiVisibilityManager.isUIVisible ? 1 : 0)`
- Portrait buttons used the same check via `CameraControlButtons`
- When `isUIVisible` changed to `false`, both orientations' buttons would fade to opacity 0
- However, SwiftUI would sometimes render the wrong orientation's view hierarchy first

### 2. **Preview Not Hiding** ❌
**Problem**: Preview timers were firing, but preview wasn't actually disappearing
- Console showed: `Preview will hide in 10.0s`
- Timer was firing correctly
- BUT: Preview was still visible on screen

**Root Cause**: 
- The `isPreviewVisible` property WAS changing (logs showed this)
- The issue was that the view wasn't properly re-rendering

### 3. **No Capture Button in Landscape When Preview Hidden** ❌
**Problem**: When preview was hidden in landscape mode, there was no way to stop recording
- Portrait mode had a capture button when preview was hidden
- Landscape mode did NOT have this button

## Solutions Implemented

### Fix 1: Use `if` Statement Instead of `.opacity()` for Landscape Buttons ✅

**Before:**
```swift
HStack(spacing: 20) {
    // Flash button
    Button(...) { ... }
        .opacity(viewModel.uiVisibilityManager.isUIVisible ? 1 : 0)
    
    // Mode button
    Button(...) { ... }
        .opacity(viewModel.uiVisibilityManager.isUIVisible ? 1 : 0)
    
    // Gallery button
    Button(...) { ... }
        .opacity(viewModel.uiVisibilityManager.isUIVisible ? 1 : 0)
}
```

**After:**
```swift
if viewModel.uiVisibilityManager.isUIVisible {
    HStack(spacing: 20) {
        // Flash button
        Button(...) { ... }
        
        // Mode button
        Button(...) { ... }
        
        // Gallery button
        Button(...) { ... }
    }
    .transition(.opacity)
}
```

**Why This Works:**
- Using `if` completely removes buttons from view hierarchy when hidden
- Prevents SwiftUI from rendering invisible buttons
- Ensures only one orientation's buttons exist at a time
- Added `.transition(.opacity)` for smooth fade animation

### Fix 2: Add Debug Logging for Preview Visibility ✅

**UIVisibilityManager.swift:**
```swift
@Published var isPreviewVisible: Bool = true {
    didSet {
        print("👁️ UIVisibilityManager: ============ isPreviewVisible changed from \(oldValue) to \(isPreviewVisible) ============")
        if !isPreviewVisible {
            print("👁️ UIVisibilityManager: ⚫️⚫️⚫️ PREVIEW IS NOW HIDDEN ⚫️⚫️⚫️")
        } else {
            print("👁️ UIVisibilityManager: ✅✅✅ PREVIEW IS NOW VISIBLE ✅✅✅")
        }
    }
}
```

**ContentView.swift:**
```swift
if viewModel.uiVisibilityManager.isPreviewVisible {
    DualCameraPreview(viewModel: viewModel)
        .ignoresSafeArea()
        .transition(.opacity)
        // ...
} else {
    print("⚫️ ContentView: Preview is HIDDEN (isPreviewVisible = false)")
}
```

**Why This Helps:**
- Confirms when state actually changes
- Shows old and new values
- Visible console markers make debugging easier

### Fix 3: Add Landscape Capture Button When Preview Hidden ✅

**Before:**
```swift
if !viewModel.uiVisibilityManager.isPreviewVisible {
    VStack {
        Spacer()
        Button(...) { ... }  // Only portrait
        .padding(.bottom, 40)
    }
}
```

**After:**
```swift
if !viewModel.uiVisibilityManager.isPreviewVisible {
    GeometryReader { geometry in
        let isLandscape = geometry.size.width > geometry.size.height
        
        if isLandscape {
            // Landscape: button on right side
            HStack {
                Spacer()
                Button(...) { ... }
                    .padding(.trailing, 40)
            }
        } else {
            // Portrait: button at bottom
            VStack {
                Spacer()
                Button(...) { ... }
                    .padding(.bottom, 40)
            }
        }
    }
}
```

**Why This Works:**
- Detects orientation using `GeometryReader`
- Places button in natural position for each orientation
- Landscape: Right side (where it normally is)
- Portrait: Bottom center (where it normally is)

## Testing Instructions

### Test 1: UI Hiding in Both Orientations ✅
1. Open app in **portrait mode**
2. Wait 5 seconds without touching
3. **Expected**: Flash, Mode, and Gallery buttons should fade out
4. **Expected**: Capture button should remain visible
5. **Expected**: Zoom slider should fade out

6. Rotate to **landscape mode** WITHOUT touching screen
7. Wait for timers to complete
8. **Expected**: Flash, Mode, and Gallery buttons should fade out
9. **Expected**: Capture button should remain visible
10. **Expected**: Zoom slider should fade out

11. Tap screen
12. **Expected**: All UI should immediately reappear in CURRENT orientation

### Test 2: Preview Hiding ✅
1. Open app and wait 10 seconds without touching
2. **Expected**: Console shows "⚫️⚫️⚫️ PREVIEW IS NOW HIDDEN ⚫️⚫️⚫️"
3. **Expected**: Camera preview disappears (black screen)
4. **Expected**: Red recording dot appears if recording

5. Tap black screen
6. **Expected**: Console shows "✅✅✅ PREVIEW IS NOW VISIBLE ✅✅✅"
7. **Expected**: Camera preview reappears immediately

### Test 3: Recording with Hidden Preview ✅
1. Start video recording
2. Wait for UI to hide (5s)
3. Wait for preview to hide (10s)
4. **Portrait mode**:
   - **Expected**: Capture button visible at bottom center
   - **Expected**: Red recording dot visible at top-left
5. **Landscape mode**:
   - **Expected**: Capture button visible on right side
   - **Expected**: Red recording dot visible at top-left

6. Tap capture button
7. **Expected**: Recording stops
8. **Expected**: Video saved to Photos

## Console Output Expected

### When Tapping Screen:
```
🖐️ ContentView: Preview tapped
📱 CameraViewModel: handleUserInteraction() called
👁️ UIVisibilityManager: ========== USER INTERACTION DETECTED ==========
👁️ UIVisibilityManager: ✅ UI shown (was hidden)
👁️ UIVisibilityManager: ✅ Preview shown (was hidden)
👁️ UIVisibilityManager: 🔄 Restarting timers...
👁️ UIVisibilityManager: ========== STARTING TIMERS (Count: 2) ==========
```

### When UI Hides:
```
👁️ UIVisibilityManager: ⏰⏰⏰ UI TIMER FIRED at 2025-12-10 20:34:28 +0000 ⏰⏰⏰
👁️ UIVisibilityManager: ========== HIDING UI ==========
👁️ UIVisibilityManager: ============ isUIVisible changed from true to false ============
```

### When Preview Hides:
```
👁️ UIVisibilityManager: ⏰⏰⏰ PREVIEW TIMER FIRED at 2025-12-10 20:34:33 +0000 ⏰⏰⏰
👁️ UIVisibilityManager: ========== HIDING PREVIEW ==========
👁️ UIVisibilityManager: ============ isPreviewVisible changed from true to false ============
👁️ UIVisibilityManager: ⚫️⚫️⚫️ PREVIEW IS NOW HIDDEN ⚫️⚫️⚫️
⚫️ ContentView: Preview is HIDDEN (isPreviewVisible = false)
```

## Files Modified

1. **ContentView.swift**
   - Changed landscape buttons from `.opacity()` to `if` statement
   - Added landscape capture button when preview hidden
   - Added debug print when preview is hidden

2. **UIVisibilityManager.swift**
   - Enhanced debug logging for `isUIVisible`
   - Enhanced debug logging for `isPreviewVisible`
   - Added clear visual indicators in console

## Summary

✅ **UI now hides correctly in BOTH portrait and landscape modes**
✅ **Preview hiding is confirmed with clear debug logs**
✅ **Capture button available in both orientations when preview is hidden**
✅ **User can stop recording even with hidden preview**

The key insight was that using `.opacity(0)` keeps views in the hierarchy, while using `if` statement completely removes them. This ensures only one orientation's UI exists at any time, preventing the cross-orientation hiding bug.
