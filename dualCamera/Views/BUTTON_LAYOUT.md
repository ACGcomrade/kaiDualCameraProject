# 🎨 Camera Controls Layout

## Button Arrangement

```
┌──────────────────────────────────────────┐
│                                          │
│         Camera Preview Area              │
│                                          │
│     (Back camera full screen)            │
│                    ┌─────────┐           │
│                    │ Front   │           │
│                    │ Camera  │           │
│                    │  (PIP)  │           │
│                    └─────────┘           │
│                                          │
│                                          │
│       ┌─────────┐   ┌─────────┐         │
│       │  Back   │   │  Front  │         │
│       │  Photo  │   │  Photo  │         │
│       └─────────┘   └─────────┘         │
│                                          │
│  ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐│
│  │ ⚡ │  │ 📷 │  │ ⭕ │  │    │  │ 🔄 ││
│  └────┘  └────┘  └────┘  └────┘  └────┘│
│   Flash  Gallery Capture Spacer Switch  │
└──────────────────────────────────────────┘
```

## Button Details

### 1. Flash Toggle (⚡)
- **Position**: Far left
- **Size**: 60x60 circle
- **Icon**: Bolt (filled when on, slashed when off)
- **Action**: Toggle flash on/off for back camera

### 2. Gallery Button (📷) ⭐ NEW!
- **Position**: Left of capture button
- **Size**: 50x50 rounded rectangle
- **Shows**: 
  - Before capture: Generic photo icon
  - After capture: Thumbnail of last photo
- **Action**: Opens photo gallery in a sheet
- **Border**: White 2px border

### 3. Capture Button (⭕)
- **Position**: Center
- **Size**: 80x80 (outer ring), 70x70 (inner circle)
- **Style**: White circle with ring outline
- **Action**: Captures from both cameras simultaneously

### 4. Empty Spacer
- **Position**: Right of capture button
- **Size**: 50x50 transparent
- **Purpose**: Balance the layout visually

### 5. Switch Camera Button (🔄)
- **Position**: Far right
- **Size**: 60x60 circle
- **Icon**: Circular arrow camera icon
- **Action**: Switch camera functionality

## Spacing

- **Between buttons**: 30pt
- **Bottom padding**: 40pt from screen bottom
- **All buttons**: Semi-transparent black background (0.6 opacity)
- **Gallery button**: Shows actual photo thumbnail when available

## Visual Hierarchy

1. **Primary**: Capture button (largest, center, white)
2. **Secondary**: Gallery button (shows photo, draws attention)
3. **Tertiary**: Flash and Switch (utility functions)

## Interaction States

### Gallery Button States:

**State 1: No Photos Captured**
```
┌─────────┐
│    📷   │  Generic photo icon
│         │  (photo.on.rectangle)
└─────────┘
```

**State 2: Photo Captured**
```
┌─────────┐
│  ┌───┐  │  Actual photo thumbnail
│  │img│  │  with white border
│  └───┘  │
└─────────┘
```

**State 3: Pressed**
```
┌─────────┐
│  ┌───┐  │  Opens gallery sheet
│  │img│  │  with animation
│  └───┘  │
└─────────┘
```

## Color Scheme

- **Background**: Black with transparency
- **Icons**: White
- **Borders**: White (2px)
- **Gallery thumbnail**: Full color photo
- **Capture button**: Pure white

## Responsive Behavior

- Buttons maintain fixed sizes
- Spacing adjusts for different screen sizes
- Gallery sheet covers entire screen when opened
- Bottom padding respects safe area

## Accessibility

- All buttons have clear tap targets (minimum 44x44)
- Visual feedback on press
- Clear iconography
- High contrast (white on dark)
- Gallery button updates to show success

