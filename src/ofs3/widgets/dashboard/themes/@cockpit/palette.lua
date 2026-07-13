--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Fixed palette for the cockpit HUD theme. Green phosphor
  symbology on black, aviation-style amber caution / red warning,
  always rendered the same regardless of the system light/dark theme.
]] --

return {
    bgcolor = lcd.RGB(2, 4, 2),
    bgcolortop = lcd.RGB(4, 8, 4),
    textcolor = lcd.RGB(60, 255, 120),
    titlecolor = lcd.RGB(0, 190, 90),
    fillcolor = lcd.RGB(60, 255, 120),
    fillbgcolor = lcd.RGB(18, 22, 18),
    fillwarncolor = lcd.RGB(255, 176, 0),
    fillcritcolor = lcd.RGB(255, 60, 60),
    accentcolor = lcd.RGB(60, 255, 120),
    framecolor = lcd.RGB(60, 255, 120),
    rssifillcolor = lcd.RGB(60, 255, 120),
    rssifillbgcolor = lcd.RGB(18, 22, 18),
    txaccentcolor = lcd.RGB(60, 255, 120),
    txfillcolor = lcd.RGB(60, 255, 120),
    txbgfillcolor = lcd.RGB(18, 22, 18)
}
