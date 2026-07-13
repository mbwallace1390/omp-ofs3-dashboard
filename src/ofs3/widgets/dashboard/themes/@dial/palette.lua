--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Fixed palette for the analog-dial theme. Graphite instrument
  cluster look with an orange needle/accent, always rendered the
  same regardless of the system light/dark theme.
]] --

return {
    bgcolor = lcd.RGB(18, 18, 21),
    bgcolortop = lcd.RGB(24, 24, 27),
    textcolor = lcd.RGB(235, 235, 235),
    titlecolor = lcd.RGB(160, 160, 168),
    fillcolor = lcd.RGB(0, 200, 90),
    fillbgcolor = lcd.RGB(30, 30, 34),
    fillwarncolor = lcd.RGB(255, 170, 0),
    fillcritcolor = lcd.RGB(230, 40, 40),
    accentcolor = lcd.RGB(255, 120, 0),
    framecolor = lcd.RGB(255, 120, 0),
    rssifillcolor = lcd.RGB(255, 120, 0),
    rssifillbgcolor = lcd.RGB(30, 30, 34),
    txaccentcolor = lcd.RGB(255, 120, 0),
    txfillcolor = lcd.RGB(0, 200, 90),
    txbgfillcolor = lcd.RGB(30, 30, 34)
}
