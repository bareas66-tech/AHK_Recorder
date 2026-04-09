;=========================
; Datei: main.ahk (angepasst)
;=========================
#Requires AutoHotkey v2.0
#SingleInstance Force
;=========================
; Datei: main.ahk
;=========================

#Include gui_rec_v02.ahk
#Include json_utils_v02.ahk

CoordMode("Mouse", "Screen")

global ActionsList := []
global IsRecording := false
global IsReplaying := false
global StopRequested := false
global RepeatMode := false
global LastDelay := 0
global MouseWasDown := false
global CurrentAction := 1

; --- Hotkeys ---
F9::BtnStartRecording()
F10::BtnStopRecording()
F11::BtnPlayOnce()
F12::BtnPlayLoop()
~*Pause::BtnAbortAll()
~Esc::BtnAbortAll()
#HotIf IsListViewFocused()   ; Hotkey nur aktiv, wenn Lambda true zurückgibt
^a::SelectAllInListView()
#HotIf                      ; Reset


ShowGui()
SetTimer(UpdateGui, 50)


; --- Aufnahme ---
BtnStartRecording(*) {
    global IsRecording, GuiMain, LastDelay
    if !IsRecording {
        LastDelay := 0                      ; sicher initialisieren
        IsRecording := true
        SetTimer(RecordingTimer, 10)
        GuiMain["StatusText"].Value := "Status: 🔴 Aufnahme läuft..."
        GuiMain["DelayDisplay"].Value := "⏱️ Verzögerung: " LastDelay " ms"
    }
}

; --- Aufnahme stoppen ---
BtnStopRecording(*) {
    global IsRecording, GuiMain, LastDelay
    if IsRecording {
        IsRecording := false
        SetTimer(RecordingTimer, 0)  ; Timer stoppen
        LastDelay := 0               ; Verzögerung zurücksetzen
        GuiMain["StatusText"].Value := "Status: 🟢 Idle...On :P"
        GuiMain["DelayDisplay"].Value := "⏱️ Verzögerung: " LastDelay " ms"
    }
}

BtnPlayOnce(*) {
    global ActionsList, IsReplaying, StopRequested, GuiMain, IsRecording
	if !IsRecording {
		if ActionsList.Length = 0 {
			ShowWarning("Achtung:`n`nKeine Aktionen zum abspielen vorhanden!")
			return
		}

		if IsReplaying {
			ShowInfo("Wiedergabe läuft bereits!")
			return
		}
		GuiMain["StatusText"].Value := "Status: ▶ Wiedergabe läuft..."
		StopRequested := false
		IsReplaying := true
		
		; Durch alle Aktionen iterieren
		for a in ActionsList {
			if StopRequested
				break

			; Zugriff auf Map-Einträge
			switch a["Type"] {
				case "Click":
					MouseMove(a["X"], a["Y"], 0)
					Click()
				case "Delay":
					Sleep(a["Time"])
				case "Drag":
					MouseClickDrag("Left", a["X1"], a["Y1"], a["X2"], a["Y2"])
			}
		}
		IsReplaying := false
		GuiMain["StatusText"].Value := "Status: ✅ Wiedergabe beendet"
	}
	else {
		; Aufnahme läuft -> keine Aktion hinzufügen, stattdessen warnen/optional anbieten abbrechen
		result := ShowYesNo("Achtung:`n`nAufnahme läuft aktuell!`n`nAufnahme abbrechen? (Kein Eintrag wird hinzugefügt)")
		if (result = "Yes")
			BtnAbortAll()
	}
}

; --- Wiederholen ---
BtnPlayLoop(*) {
    global IsRecording, RepeatMode, GuiMain, StopRequested
	if !IsRecording {
		RepeatMode := !RepeatMode
		if RepeatMode {
			GuiMain["LoopStatus"].Value := "🔁 Loop: 🟢 Aktiv"
			GuiMain["StatusText"].Value := "Status: 🟢 Loop läuft..."
			StopRequested := false
			StartPlayback()
		} else {
			StopRequested := true
			GuiMain["LoopStatus"].Value := "🔁 Loop: 🔴 Inaktiv"
			GuiMain["StatusText"].Value := "Status: ⏸️ Loop gestoppt"
		}
	}
	else {
		; Aufnahme läuft -> keine Aktion hinzufügen
		result := ShowYesNo("Achtung:`n`nAufnahme läuft aktuell!`n`nAufnahme abbrechen? (Kein Loop-Status wird geändert)")
		if (result = "Yes")
			BtnAbortAll()
	}
}

; --- Notfall-Abbruch ---
BtnAbortAll(*) {
    global StopRequested, RepeatMode, IsRecording, IsReplaying, GuiMain, LastDelay
    StopRequested := true
    RepeatMode := false
    IsRecording := false
    IsReplaying := false
    SetTimer(RecordingTimer, 0)
    SetTimer(PlaybackTimer, 0)
    LastDelay := 0
    GuiMain["StatusText"].Value := "Status: ⛔ Abgebrochen!"
    GuiMain["LoopStatus"].Value := "🔁 Loop: 🔴 Inaktiv"
    GuiMain["DelayDisplay"].Value := "⏱️ Verzögerung: " LastDelay " ms"
    SoundBeep(1000, 150)
    ShowInfo("Aktuelle Skriptaktionen wurden abgebrochen!")
}

; --- Start Wiedergabe (einmal oder Loop) ---
StartPlayback() {
    global CurrentAction, StopRequested, IsReplaying

    if ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen vorhanden!")
        return
    }

    StopRequested := false
    IsReplaying := true
    CurrentAction := 1
    SetTimer(PlaybackTimer, -10) ; einmaliger Timer
}

PlaybackTimer(*) {
    global ActionsList, CurrentAction, StopRequested, IsReplaying, RepeatMode, GuiMain

    if StopRequested {
        IsReplaying := false
        return
    }

    if CurrentAction > ActionsList.Length {
        ; Ende der Wiedergabe
        if RepeatMode && !StopRequested {
            CurrentAction := 1
            SetTimer(PlaybackTimer, -10)
            return
        }

        IsReplaying := false
        StopRequested := false
        CurrentAction := 1
        GuiMain["StatusText"].Value := RepeatMode ? "Status: 🔁 Loop pausiert" : "Status: ✅ Wiedergabe beendet"
        return
    }

    a := ActionsList[CurrentAction]

    ; Zugriff auf Map-Einträge
    if a["Type"] = "Click" {
        MouseMove(a["X"], a["Y"], 0)
        Click()
    } else if a["Type"] = "Delay" {
        Sleep(a["Time"])
    } else if a["Type"] = "Drag" {
        MouseClickDrag("Left", a["X1"], a["Y1"], a["X2"], a["Y2"])
    }

    CurrentAction++
    SetTimer(PlaybackTimer, -10)
}

; RecordingTimer using GetControlRect (no VarSetCapacity)
RecordingTimer(*) {
    local rect, bx, by, bw, bh, mx, my
    global LastDelay, MouseWasDown, ActionsList, GuiMain, StopRecordingBtn
    global PlayOnceBtn, ToggleRepeatBtn, AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn

    if !IsObject(GuiMain)
        return

    ; Verzögerung hochzählen
    LastDelay += 10

    ; Mausposition live holen
    MouseGetPos &mx, &my
    GuiMain["MousePos"].Value := "🖱️ Maus: X=" mx " Y=" my
    GuiMain["DelayDisplay"].Value := "⏱️ Verzögerung: " LastDelay " ms"

    ; Wenn Linksklick gedrückt ist, prüfen ob Klick auf bestimmte Buttons erfolgt
    if GetKeyState("LButton", "P") {
        ; Prüfe, ob Maus innerhalb eines Buttons liegt, die nicht aufgenommen werden sollen
        excludedBtns := [ StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn, AbortBtn, ExitBtn
                        , InsertBtn, DeleteBtn, SaveBtn, LoadBtn ]
        inExcluded := false

        for ctrl in excludedBtns {
            try {
                r := GetControlRect(ctrl)
                if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h) {
                    inExcluded := true
                    break
                }
            } catch {
                ; falls Fehler, ignoriere diesen Button
            }
        }

        ; Prüfe, ob das Fenster unter dem Cursor ein Dialog (z.B. MsgBox) ist → Klasse "#32770"
        if !inExcluded {
            try {
                hwndUnder := GetHwndFromPoint(mx, my)
                if hwndUnder && (hwndUnder != GuiMain.Hwnd) {
                    className := GetClassNameByHwnd(hwndUnder)
                    if (className = "#32770") { ; Standard Windows Dialog (MessageBox)
                        inExcluded := true
                    }
                }
            } catch {
                ; ignore
            }
        }

        if inExcluded {
            ; Klick auf einen der Steuer-Buttons oder Dialog → NICHT in Aktionen aufnehmen
            MouseWasDown := true
            return
        }

        if !MouseWasDown {
            rect := GetControlRect(StopRecordingBtn)
            bx := rect.x, by := rect.y, bw := rect.w, bh := rect.h

            if !(mx >= bx && mx <= bx + bw && my >= by && my <= by + bh) {
                if LastDelay > 0 {
                    ActionsList.Push(Map("Type", "Delay", "Time", LastDelay))
                    LastDelay := 0
                }
                ActionsList.Push(Map("Type", "Click", "X", mx, "Y", my))
                UpdateActionsList()
            }
        }
        MouseWasDown := true
    } else {
        MouseWasDown := false
    }
}

; Hilfsfunktion: HWND unter Punkt ermitteln
GetHwndFromPoint(x, y) {
    ; DllCall WindowFromPoint expects POINT in screen coords (x,y)
    return DllCall("WindowFromPoint", "Int", x, "Int", y, "Ptr")
}

; Hilfsfunktion: Klassenname aus HWND lesen
GetClassNameByHwnd(hwnd) {
    local buf := Buffer(256, 1) ; 256 wchar buffer
    if !DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", buf, "Int", 256)
        return ""
    return StrGet(buf, "UTF-16")
}

; GetControlRect using AHK v2 Buffer (no VarSetCapacity)
GetControlRect(ctrl) {
    local buf, hCtrl, left, top, right, bottom
    try {
        buf := Buffer(16)             ; allocate 16 bytes for RECT (left, top, right, bottom)
        hCtrl := ctrl.Hwnd
        if DllCall("GetWindowRect", "Ptr", hCtrl, "Ptr", buf) {
            left := NumGet(buf, 0, "Int")
            top := NumGet(buf, 4, "Int")
            right := NumGet(buf, 8, "Int")
            bottom := NumGet(buf, 12, "Int")
            return {x: left, y: top, w: right-left, h: bottom-top}
        }
    } catch {
        ; fallthrough to fallback
    }

    ; Fallback: compute from parent window position + control GetPos
    try {
        local wx, wy, ww, wh, cx, cy, cw, ch
        parent := ctrl.Gui
        WinGetPos(&wx, &wy, &ww, &wh, parent.Hwnd)
        ctrl.GetPos(&cx, &cy, &cw, &ch)
        return {x: wx + cx, y: wy + cy, w: cw, h: ch}
    } catch {
        return {x:0, y:0, w:0, h:0}
    }
}

ExitScript(*) {
    ExitApp()
}