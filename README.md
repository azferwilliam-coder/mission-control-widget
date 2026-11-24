# Mission Control Widget

A slim drawer that lives on the top-left edge of your Mac's screen (design: "Amber Dusk").

- **Hidden:** a small tab showing Brunei (BWN) and London (LDN) time either side of a status dot.
  The dot is amber when all is well and turns coral when something needs you
  (low battery on the Mac or a Bluetooth device, nearly full disk, running hot, memory full, working hard, focus session done).
- **Revealed:** move the pointer onto the tab and the drawer slides out: the date and Bandar Seri
  Begawan weather, CPU, memory, free disk, network speed, temperature and fan, a month calendar
  (today ringed in amber, a dot under days with events, arrows to see other months; click the
  month name to come back), your next calendar event, a 25-minute focus timer, and battery rings
  for this Mac and connected Bluetooth devices (Magic Mouse, Keyboard, Trackpad, AirPods, Beats).
  A ring turns coral at 20% or less, and so does the dot. Hover an AirPods ring for left, right
  and case. iPhone and Apple Watch aren't shown: a Mac app can't read them reliably.
  Move away and it tucks back in. To keep it open, right-click it and choose Pin Drawer Open (choose Unpin Drawer to let it tuck away again). It sits on the desktop behind your windows; right-click and choose Always on Top to keep it in front of everything.
- **Right-click** for: start, pause or reset the focus timer, Pin Drawer Open, Always on Top
  (also above full-screen apps), Clear Glass (macOS 26: see-through like the Dock instead of
  frosted), Refresh, Open at Login, Quit.

## Build and install

Needs Xcode 26 (for the macOS 26 Liquid Glass look). In Terminal, from this folder:

```
bash scripts/make-app.sh --install
```

Other commands:

```
swift test                                   # run the tests
bash scripts/make-app.sh --snapshots shots   # review pictures with sample data
```

## Privacy

- Calendar: only reads your events (the next one, and which days have events for the month view),
  never changes anything. macOS asks first.
- Weather: asks Open-Meteo (free, no account) for Bandar Seri Begawan's current weather.
  Only that place's coordinates are sent.
- Nothing else leaves your Mac.

## Notes

- Temperature and fan speed come from the Mac's System Management Controller using read-only calls
  that Apple doesn't document. Fine for a personal app; it means it couldn't go on the App Store.
  If a Mac doesn't expose them, the drawer shows "Cool / Warm / Hot" instead.
- The app is signed just for this Mac, so after each rebuild macOS may ask for calendar access again.
