# Quick Reference: UI Controls

## Gesture Controls

### Double Tap (anywhere on screen)
- **Action**: Toggle UI buttons on/off
- **Toggles**: Flash button, Mode switch, Gallery button, Zoom slider
- **Does NOT affect**: Capture button, Preview visibility
- **Use case**: Hide UI for clean, unobstructed camera view

### Single Tap (anywhere on screen)
- **Action**: Show preview if hidden
- **Effect**: Resets preview auto-hide timer
- **Does NOT affect**: UI button visibility
- **Use case**: Bring back preview when it auto-hides

## Auto-Hide Behavior

### UI Buttons (Flash, Mode, Gallery, Zoom)
- ❌ **NO auto-hide** - Stay visible until you double-tap
- ✅ Manual control only

### Camera Preview
- ✅ Auto-hides after **1 minute** of inactivity (normal)
- ✅ Auto-hides after **5 minutes** during recording
- Single tap to restore

### Capture Button
- Always visible (never hides)
- Available even when preview is hidden

## Example Workflows

### Clean Shot Composition
1. Frame your shot
2. Double-tap to hide UI
3. Take photo/video with clean view
4. Double-tap to show UI again

### Long Recording
1. Start recording
2. Preview auto-hides after 5 minutes
3. Single tap to check preview anytime
4. Capture button always available to stop

### Quick Shooting
1. Leave UI visible (default)
2. Use buttons normally
3. No timer to worry about
