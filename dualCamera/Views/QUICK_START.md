# 🚀 Quick Start - Dual Camera Auto-Save

## ⚠️ MUST DO FIRST!

Add this to your **Info.plist** or the app will crash:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save photos to your library</string>
```

### How to add it:
1. Open Xcode
2. Click project name → Your target → **Info** tab
3. Click **+** button
4. Type: `Privacy - Photo Library Additions Usage Description`
5. Value: `We need permission to save photos to your library`

---

## ✅ How to Use Your App

1. **Run the app** - See both cameras
   - Back camera = full screen
   - Front camera = small box top-right

2. **Tap the white circle button** - Capture!
   - 2 photos captured simultaneously
   - First time: iOS asks for permission → Tap "Allow"

3. **Check the result**
   - Thumbnails appear above buttons
   - Success message: "2 photo(s) saved successfully!"

4. **Open Photos app**
   - Go to "Recents"
   - See 2 new separate photos

---

## 📸 What Gets Saved

**Every capture saves 2 separate photos:**
- Photo 1: Back camera (main view)
- Photo 2: Front camera (selfie view)

They are **NOT** combined - each is a separate image file in your Photos library!

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| App crashes on capture | Add Info.plist permission (see above) |
| No permission dialog | Delete app, reset privacy settings, reinstall |
| Only 1 photo saves | Device may not support dual capture - try iPhone XS+ |
| Photos not in Photos app | Wait a few seconds, pull down to refresh |

---

## 📱 Tested On

- ✅ iPhone XS and newer (best experience)
- ⚠️ Older devices (back camera only)

---

That's it! You're ready to go! 🎉
