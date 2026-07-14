--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Fixed cyberpunk palette. Black/yellow/cyan HUD look, always
  rendered the same regardless of the system light/dark theme.
]] --

return {
    bgcolor = lcd.RGB(5, 5, 6),
    bgcolortop = lcd.RGB(10, 10, 12),
    textcolor = lcd.RGB(252, 238, 10),
    titlecolor = lcd.RGB(0, 224, 255),
    fillcolor = lcd.RGB(252, 238, 10),
    fillbgcolor = lcd.RGB(26, 26, 28),
    fillwarncolor = lcd.RGB(255, 138, 0),
    fillcritcolor = lcd.RGB(255, 0, 60),
    accentcolor = lcd.RGB(0, 224, 255),
    framecolor = lcd.RGB(0, 224, 255),
    rssifillcolor = lcd.RGB(0, 224, 255),
    rssifillbgcolor = lcd.RGB(26, 26, 28),
    txaccentcolor = lcd.RGB(0, 224, 255),
    txfillcolor = lcd.RGB(252, 238, 10),
    txbgfillcolor = lcd.RGB(26, 26, 28)
}
