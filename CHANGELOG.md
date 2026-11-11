# Changelog

## 0.1.4
- Works with OpenMap: right-click on its map opens "Route here" again (OpenMap was taking every right-click to zoom out), the pin goes on the zone under the cursor, and the route line is drawn over OpenMap's map and follows it as you pan and zoom. "Zoom out" in the menu uses OpenMap's zoom.

## 0.1.3
- The window can be resized: drag the bottom-right corner to make it wider or taller.

## 0.1.2
- Much lower CPU use: route searches no longer create garbage, impossible walking routes are skipped instantly, and the position check only runs while you have a destination.
- Fixed constant recalculating when standing away from the paths.
