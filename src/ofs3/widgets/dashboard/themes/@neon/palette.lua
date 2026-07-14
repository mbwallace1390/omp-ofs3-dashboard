--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Fixed neon palette. Unlike @rt-rc, this theme does not follow the
  system light/dark theme colors - it always renders the same
  high-contrast neon look.
]] --

return {
    bgcolor = lcd.RGB(4, 6, 16),
    bgcolortop = lcd.RGB(9, 11, 26),
    textcolor = lcd.RGB(0, 240, 255),
    titlecolor = lcd.RGB(255, 0, 190),
    fillcolor = lcd.RGB(57, 255, 20),
    fillbgcolor = lcd.RGB(22, 24, 40),
    fillwarncolor = lcd.RGB(255, 214, 0),
    fillcritcolor = lcd.RGB(255, 45, 85),
    accentcolor = lcd.RGB(157, 0, 255),
    framecolor = lcd.RGB(157, 0, 255),
    rssifillcolor = lcd.RGB(0, 240, 255),
    rssifillbgcolor = lcd.RGB(22, 24, 40),
    txaccentcolor = lcd.RGB(157, 0, 255),
    txfillcolor = lcd.RGB(57, 255, 20),
    txbgfillcolor = lcd.RGB(22, 24, 40)
}
