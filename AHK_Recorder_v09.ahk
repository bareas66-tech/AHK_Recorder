;=========================
; Datei: AHK_Recorder_v09.ahk
; Version 0.9
; - Sequenz-Manager integriert
; - ESC nur aktiv wenn Aufnahme/Wiedergabe läuft
; - Tastaturaufnahme via InputHook (keys pass-through)
; - Mausbewegungsaufnahme mit Mindestabstand-Filter
; - Drag & Drop Sortierung in ListView
; - Status-Box mit Aktion-Tracking
;=========================

#Requires AutoHotkey v2.0
#SingleInstance Force

#Include gui_rec_v09.ahk
#Include seq_manager_v05.ahk
#Include json_utils_v03.ahk

CoordMode("Mouse", "Screen")

global ActionsList          := []
global IsRecording          := false
global IsReplaying          := false
global StopRequested        := false
global RepeatMode           := false
global LastDelay            := 0
global CurrentAction        := 1

; Aktion-Tracking für Status-Box
global LastActionTime       := 0
global LastClickX           := 0
global LastClickY           := 0

; State Machine Aufnahme
global MouseWasDown         := false
global MouseDownButton      := ""
global MouseDownX           := 0
global MouseDownY           := 0
global MouseDownTime        := 0
global IsDragging           := false
global DownWasExcluded      := false

; Schwellenwerte
global DragThreshold        := 10
global LongClickThreshold   := 500

; Optionale Aufnahme-Features
global RecordKeyboardEnabled  := false
global RecordMouseMoveEnabled := false
global MouseMoveThreshold     := 8
global MoveLastX              := -1
global MoveLastY              := -1
global KeyHook                := ""

; Wiedergabe-Einstellungen
global PlayCountdown          := 0      ; Sekunden Countdown vor Wiedergabe
global PlaySpeedFactor        := 1.0    ; Geschwindigkeit: 2.0 = 2x schneller, 0.5 = halb so schnell
global PlayRepeatCount        := 0      ; 0 = endlos bei Loop
global PlayRepeatDone         := 0      ; laufender Wiederholungszaehler
global PlayMouseMultiplier    := 1      ; Maus-Multiplikator: 1=normal, 2=2x schneller usw.

; Bildschirmgrenzen (werden beim Start ermittelt)
global ScreenXMin := 0
global ScreenYMin := 0
global ScreenXMax := 1920
global ScreenYMax := 1080

; --- Hotkeys ---
F9::BtnStartRecording()
F10::BtnStopRecording()
F11::BtnPlayOnce()
F12::BtnPlayLoop()
^n::MenuFileNew()
^s::SaveActionsQuick()
^z::MenuUndo()
^y::MenuRedo()

; Pause immer aktiv
~*Pause::BtnAbortAll()

; ESC nur wenn wirklich etwas laeuft
~Esc:: {
    global IsRecording, IsReplaying, IsSeqPlaying
    if IsRecording || IsReplaying || IsSeqPlaying
        BtnAbortAll()
}

#HotIf (IsRecording = true)
~WheelUp::RecordScroll("Up")
~WheelDown::RecordScroll("Down")
#HotIf

#HotIf IsListViewFocused()
^a::SelectAllInListView()
Delete::DelAction()
Enter:: {
    global GuiMain
    LV  := GuiMain["ActionList"]
    row := LV.GetNext(0)
    if row > 0
        EditAction(LV, row)
}
#HotIf

#HotIf IsSeqLVFocused()
Delete::SeqDelSelected()
Enter:: {
    global GuiSeqManager
    LV  := GuiSeqManager["SeqListView"]
    row := LV.GetNext(0)
    if row > 0
        SeqPlaySingle(row)
}
#HotIf

DetectScreenBounds()
ShowGui()
SetTimer(UpdateGui, 50)

; ─────────────────────────────────────────────
DetectScreenBounds() {
    global ScreenXMin, ScreenYMin, ScreenXMax, ScreenYMax
    count := MonitorGetCount()
    Loop count {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if A_Index = 1 {
            ScreenXMin := left
            ScreenYMin := top
            ScreenXMax := right
            ScreenYMax := bottom
        } else {
            ScreenXMin := Min(ScreenXMin, left)
            ScreenYMin := Min(ScreenYMin, top)
            ScreenXMax := Max(ScreenXMax, right)
            ScreenYMax := Max(ScreenYMax, bottom)
        }
    }
}

; ─────────────────────────────────────────────
RecordScroll(direction) {
    global ActionsList, LastDelay, LastActionTime
    if LastDelay > 0 {
        ActionsList.Push(Map("Type", "Delay", "Time", LastDelay))
        LastDelay := 0
    }
    if ActionsList.Length > 0 {
        last := ActionsList[ActionsList.Length]
        if (last["Type"] = "Scroll" && last["Direction"] = direction) {
            last["Amount"] += 1
            ActionsList[ActionsList.Length] := last
            UpdateActionsList()
            return
        }
    }
    ActionsList.Push(Map("Type", "Scroll", "Direction", direction, "Amount", 1))
    LastActionTime := A_TickCount
    UpdateActionsList()
}

; ─────────────────────────────────────────────
BtnStartRecording(*) {
    global IsRecording, GuiMain, LastDelay
    global MouseWasDown, IsDragging, DownWasExcluded
    global MoveLastX, MoveLastY
    if !IsRecording {
        LastDelay       := 0
        MouseWasDown    := false
        IsDragging      := false
        DownWasExcluded := false
        MoveLastX       := -1
        MoveLastY       := -1
        IsRecording     := true
        SetTimer(RecordingTimer, 10)
        StartKeyHook()
        GuiMain["StatusText"].Value   := "Status: Aufnahme laeuft..."
        GuiMain["DelayDisplay"].Value := "Verzoegerung: " LastDelay " ms"
    }
}

; ─────────────────────────────────────────────
BtnStopRecording(*) {
    global IsRecording, GuiMain, LastDelay, LastActionTime
    global MouseWasDown, IsDragging, DownWasExcluded
    if IsRecording {
        IsRecording     := false
        SetTimer(RecordingTimer, 0)
        LastDelay       := 0
        LastActionTime  := 0
        MouseWasDown    := false
        IsDragging      := false
        DownWasExcluded := false
        StopKeyHook()
        GuiMain["StatusText"].Value    := "Status: Idle"
        GuiMain["DelayDisplay"].Value  := "Zeit seit letzter Aktion: --"
    }
}

; ─────────────────────────────────────────────
BtnPlayOnce(*) {
    global ActionsList, IsReplaying, RepeatMode, GuiMain, IsRecording
    if IsRecording {
        result := ShowYesNo("Aufnahme laeuft!`n`nAufnahme abbrechen?")
        if (result = "Yes")
            BtnAbortAll()
        return
    }
    if ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen zum Abspielen vorhanden!")
        return
    }
    if IsReplaying {
        ShowInfo("Wiedergabe laeuft bereits!")
        return
    }
    RepeatMode := false
    GuiMain["StatusText"].Value := "Status: Wiedergabe laeuft..."
    StartPlayback()
}

; ─────────────────────────────────────────────
BtnPlayLoop(*) {
    global IsRecording, RepeatMode, GuiMain, StopRequested, IsReplaying, ActionsList
    if IsRecording {
        result := ShowYesNo("Aufnahme läuft!`n`nAufnahme abbrechen?")
        if (result = "Yes")
            BtnAbortAll()
        return
    }
    if ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen zum Abspielen vorhanden!")
        return
    }
    RepeatMode := !RepeatMode
    if RepeatMode {
        if IsReplaying {
            ShowInfo("Wiedergabe laeuft bereits!")
            RepeatMode := true
            return
        }
        GuiMain["LoopStatus"].Value := "Loop: Aktiv"
        GuiMain["StatusText"].Value := "Status: Loop laeuft..."
        StartPlayback()
    } else {
        StopRequested := true
        GuiMain["LoopStatus"].Value := "Loop: Inaktiv"
        GuiMain["StatusText"].Value := "Status: Loop gestoppt"
    }
}

; ─────────────────────────────────────────────
BtnAbortAll(*) {
    global StopRequested, RepeatMode, IsRecording, IsReplaying, IsSeqPlaying, GuiMain, LastDelay
    global MouseWasDown, IsDragging, DownWasExcluded

    ; Nur wenn wirklich etwas lief
    somethingWasRunning := IsRecording || IsReplaying || IsSeqPlaying

    StopRequested   := true
    RepeatMode      := false
    IsRecording     := false
    IsReplaying     := false
    MouseWasDown    := false
    IsDragging      := false
    DownWasExcluded := false
    SetTimer(RecordingTimer, 0)
    SetTimer(PlaybackTimer, 0)
    LastDelay := 0

    StopKeyHook()
    SeqAbort()

    GuiMain["StatusText"].Value   := "Status: Abgebrochen!"
    GuiMain["LoopStatus"].Value   := "Loop: Inaktiv"
    GuiMain["DelayDisplay"].Value := "Verzoegerung: " LastDelay " ms"

    if somethingWasRunning {
        SoundBeep(1000, 150)
        ShowInfo("Aktionen abgebrochen!")
    }
}

; ─────────────────────────────────────────────
StartPlayback() {
    global CurrentAction, StopRequested, IsReplaying, ActionsList
    global PlayCountdown, PlayRepeatDone, GuiMain

    if ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen vorhanden!")
        return
    }

    ReadPlaybackSettings()

    StopRequested  := false
    IsReplaying    := true
    CurrentAction  := 1
    PlayRepeatDone := 0

    ; Countdown (blockiert absichtlich - gibt Zeit das Fenster zu wechseln)
    if PlayCountdown > 0 {
        i := PlayCountdown
        while i > 0 {
            if StopRequested {
                IsReplaying := false
                return
            }
            GuiMain["StatusText"].Value := "Startet in " i " s..."
            Sleep(1000)
            i--
        }
    }

    SetTimer(PlaybackTimer, -10)
}

; Einstellungen aus GUI auslesen
ReadPlaybackSettings() {
    global GuiMain, PlayCountdown, PlaySpeedFactor, PlayRepeatCount, PlayMouseMultiplier

    try {
        v := GuiMain["CountdownSec"].Value
        PlayCountdown := (IsNumber(v) && v >= 0) ? Integer(v) : 0
    } catch {
        PlayCountdown := 0
    }
    try {
        v := GuiMain["SpeedFactor"].Value
        PlaySpeedFactor := (IsNumber(v) && v > 0) ? Float(v) : 1.0
    } catch {
        PlaySpeedFactor := 1.0
    }
    try {
        v := GuiMain["RepeatCount"].Value
        PlayRepeatCount := (IsNumber(v) && v >= 0) ? Integer(v) : 0
    } catch {
        PlayRepeatCount := 0
    }
    try {
        v := GuiMain["MouseMultiplier"].Value
        PlayMouseMultiplier := (IsNumber(v) && Float(v) >= 1) ? Float(v) : 1.0
    } catch {
        PlayMouseMultiplier := 1.0
    }
}

; ─────────────────────────────────────────────
; PlaybackTimer - mit Speed, RepeatCount, Comment-Skip
; ─────────────────────────────────────────────
PlaybackTimer(*) {
    global ActionsList, CurrentAction, StopRequested, IsReplaying, RepeatMode, GuiMain
    global IsSeqPlaying, PlaySpeedFactor, PlayRepeatCount, PlayRepeatDone, PlayMouseMultiplier

    if StopRequested {
        IsReplaying := false
        return
    }

    if CurrentAction > ActionsList.Length {
        IsReplaying   := false
        StopRequested := false
        CurrentAction := 1

        ; Sequenz-Manager: naechste Sequenz?
        if IsSeqPlaying {
            SeqOnSequenceFinished()
            return
        }

        if RepeatMode {
            PlayRepeatDone++
            ; RepeatCount=0 = endlos, sonst nach N Durchlaeufen stoppen
            if PlayRepeatCount > 0 && PlayRepeatDone >= PlayRepeatCount {
                RepeatMode := false
                GuiMain["LoopStatus"].Value  := "Loop: Aus"
                GuiMain["StatusText"].Value  := "Status: " PlayRepeatDone "x abgespielt"
                return
            }
            IsReplaying   := true
            CurrentAction := 1
            SetTimer(PlaybackTimer, -10)
            return
        }

        GuiMain["StatusText"].Value := "Status: Wiedergabe beendet"
        return
    }

    a   := ActionsList[CurrentAction]
    typ := a["Type"]

    if typ = "Click" {
        btn := a.Has("Button") ? a["Button"] : "Left"
        MouseMove(a["X"], a["Y"], 0)
        Click(btn = "Right" ? "Right" : "Left")

    } else if typ = "LongClick" {
        btn    := a.Has("Button") ? a["Button"] : "Left"
        btnStr := (btn = "Right") ? "right" : "left"
        MouseMove(a["X"], a["Y"], 0)
        MouseClick(btnStr, , , 1, 0, "D")
        Sleep(Max(1, Round(a["Duration"] / PlaySpeedFactor)))
        MouseClick(btnStr, , , 1, 0, "U")

    } else if typ = "Drag" {
        btn    := a.Has("Button") ? a["Button"] : "Left"
        btnKey := (btn = "Right") ? "{RButton" : "{LButton"
        MouseMove(a["X1"], a["Y1"], 0)
        Sleep(50)
        SendEvent(btnKey " Down}")
        Sleep(50)
        MouseMove(a["X2"], a["Y2"], 3)
        Sleep(50)
        SendEvent(btnKey " Up}")

    } else if typ = "Delay" {
        ; Geschwindigkeit anwenden
        Sleep(Max(1, Round(a["Time"] / PlaySpeedFactor)))

    } else if typ = "Scroll" {
        key := (a["Direction"] = "Up") ? "{WheelUp}" : "{WheelDown}"
        Loop a["Amount"]
            Send(key)

    } else if typ = "KeyPress" {
        SendEvent(a["Key"])

    } else if typ = "MouseMove" {
        ; Alle aufeinanderfolgenden MouseMove-Aktionen (inkl. Delays dazwischen)
        ; in einem einzigen Durchlauf abarbeiten.
        ; Delays werden durch PlayMouseMultiplier geteilt → Zeitkompression.
        i := CurrentAction
        while i <= ActionsList.Length {
            act := ActionsList[i]
            if act["Type"] = "MouseMove" {
                MouseMove(act["X"], act["Y"], 0)
                i++
            } else if act["Type"] = "Delay" {
                ; Delay nur konsumieren wenn danach wieder ein MouseMove kommt
                if i + 1 <= ActionsList.Length && ActionsList[i + 1]["Type"] = "MouseMove" {
                    scaledDelay := Round(act["Time"] / PlayMouseMultiplier)
                    if scaledDelay > 0
                        Sleep(scaledDelay)
                    i++
                } else {
                    break
                }
            } else {
                break
            }
        }
        CurrentAction := i
        SetTimer(PlaybackTimer, -1)
        return

    } else if typ = "Comment" {
        ; Kommentare werden bei Wiedergabe uebersprungen

    } else if typ = "TextInput" {
        SendText(a["Text"])
    }

    CurrentAction++
    SetTimer(PlaybackTimer, -10)
}

; ─────────────────────────────────────────────
; RecordingTimer - State Machine
; ─────────────────────────────────────────────
RecordingTimer(*) {
    local mx, my, lDown, rDown, anyDown, currentButton, elapsed, dx, dy, dist
    global LastDelay, ActionsList, GuiMain, LastActionTime, LastClickX, LastClickY
    global MouseWasDown, MouseDownButton, MouseDownX, MouseDownY
    global MouseDownTime, IsDragging, DownWasExcluded
    global DragThreshold, LongClickThreshold
    global RecordMouseMoveEnabled, MoveLastX, MoveLastY, MouseMoveThreshold
    global StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn, AbortBtn
    global ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn

    if !IsObject(GuiMain)
        return

    LastDelay += 10
    MouseGetPos &mx, &my
    GuiMain["MousePos"].Value     := "Maus: X=" mx " Y=" my
    GuiMain["DelayDisplay"].Value := "Verzoegerung: " LastDelay " ms"

    lDown         := GetKeyState("LButton", "P")
    rDown         := GetKeyState("RButton", "P")
    anyDown       := lDown || rDown
    currentButton := lDown ? "Left" : (rDown ? "Right" : "")

    ; Mausbewegung aufzeichnen (nur wenn kein Button gedrueckt)
    if RecordMouseMoveEnabled && !anyDown && !MouseWasDown {
        if MoveLastX = -1 {
            MoveLastX := mx
            MoveLastY := my
        } else {
            dx   := mx - MoveLastX
            dy   := my - MoveLastY
            dist := Sqrt(dx*dx + dy*dy)
            if dist >= MouseMoveThreshold {
                if LastDelay > 0 {
                    ActionsList.Push(Map("Type", "Delay", "Time", LastDelay))
                    LastDelay := 0
                }
                ActionsList.Push(Map("Type", "MouseMove", "X", mx, "Y", my))
                MoveLastX := mx
                MoveLastY := my
                UpdateActionsList()
            }
        }
    }

    if anyDown {
        if !MouseWasDown {
            MouseDownButton := currentButton
            MouseDownX      := mx
            MouseDownY      := my
            MouseDownTime   := A_TickCount
            IsDragging      := false
            DownWasExcluded := false

            excludedBtns := [StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn,
                             AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn]
            for ctrl in excludedBtns {
                try {
                    r := GetControlRect(ctrl)
                    if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h) {
                        DownWasExcluded := true
                        break
                    }
                } catch {
        }
            }
            if !DownWasExcluded {
                try {
                    hwndUnder := DllCall("WindowFromPoint", "Int", mx, "Int", my, "Ptr")
                    if hwndUnder && hwndUnder != GuiMain.Hwnd {
                        buf := Buffer(256, 0)
                        DllCall("GetClassNameW", "Ptr", hwndUnder, "Ptr", buf, "Int", 256)
                        if StrGet(buf, "UTF-16") = "#32770"
                            DownWasExcluded := true
                    }
                } catch {
        }
            }
            MouseWasDown := true
        } else {
            if !DownWasExcluded && !IsDragging {
                dx   := mx - MouseDownX
                dy   := my - MouseDownY
                dist := Sqrt(dx*dx + dy*dy)
                if dist > DragThreshold
                    IsDragging := true
            }
        }
    } else {
        if MouseWasDown {
            if !DownWasExcluded {
                elapsed := A_TickCount - MouseDownTime
                if LastDelay > 0 {
                    ActionsList.Push(Map("Type", "Delay", "Time", LastDelay))
                    LastDelay := 0
                }
                if IsDragging {
                    ActionsList.Push(Map("Type","Drag","Button",MouseDownButton,
                        "X1",MouseDownX,"Y1",MouseDownY,"X2",mx,"Y2",my))
                    LastClickX := mx
                    LastClickY := my
                } else if elapsed >= LongClickThreshold {
                    ActionsList.Push(Map("Type","LongClick","Button",MouseDownButton,
                        "X",MouseDownX,"Y",MouseDownY,"Duration",elapsed))
                    LastClickX := MouseDownX
                    LastClickY := MouseDownY
                } else {
                    ActionsList.Push(Map("Type","Click","Button",MouseDownButton,
                        "X",MouseDownX,"Y",MouseDownY))
                    LastClickX := MouseDownX
                    LastClickY := MouseDownY
                }
                LastActionTime := A_TickCount
                UpdateActionsList()
            }
            MouseWasDown    := false
            IsDragging      := false
            DownWasExcluded := false
        }
    }
}

; ─────────────────────────────────────────────
GetControlRect(ctrl) {
    try {
        buf   := Buffer(16, 0)
        hCtrl := ctrl.Hwnd
        if DllCall("GetWindowRect", "Ptr", hCtrl, "Ptr", buf) {
            left   := NumGet(buf,  0, "Int")
            top    := NumGet(buf,  4, "Int")
            right  := NumGet(buf,  8, "Int")
            bottom := NumGet(buf, 12, "Int")
            return {x: left, y: top, w: right - left, h: bottom - top}
        }
    } catch {
        }
    try {
        local pt := Buffer(8, 0)
        NumPut("Int", 0, pt, 0)
        NumPut("Int", 0, pt, 4)
        DllCall("ClientToScreen", "Ptr", ctrl.Gui.Hwnd, "Ptr", pt)
        local clientX := NumGet(pt, 0, "Int")
        local clientY := NumGet(pt, 4, "Int")
        local cx, cy, cw, ch
        ctrl.GetPos(&cx, &cy, &cw, &ch)
        return {x: clientX + cx, y: clientY + cy, w: cw, h: ch}
    } catch {
        return {x: 0, y: 0, w: 0, h: 0}
    }
}

; ─────────────────────────────────────────────
; Tastatur-InputHook starten / stoppen
; ─────────────────────────────────────────────
StartKeyHook() {
    global KeyHook, RecordKeyboardEnabled
    if !RecordKeyboardEnabled
        return
    StopKeyHook()
    KeyHook := InputHook("V B")       ; V = pass-through, B = backspace ignorieren
    KeyHook.KeyOpt("{All}", "N")      ; N = OnKeyDown fuer ALLE Tasten aufrufen
    KeyHook.NotifyNonText := true     ; auch Sondertasten melden
    KeyHook.OnKeyDown     := RecordKeyDown
    KeyHook.Start()
}

StopKeyHook() {
    global KeyHook
    if IsObject(KeyHook) {
        try KeyHook.Stop()
        KeyHook := ""
    }
}

RecordKeyDown(ih, vk, sc) {
    global ActionsList, LastDelay, LastActionTime

    ; Modifier-Tasten selbst nicht aufzeichnen
    modKeys := [160,161,162,163,164,165,91,92]  ; Shift,Ctrl,Alt,Win VK-Codes
    for m in modKeys {
        if vk = m
            return
    }

    ; Tastenname ermitteln
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if keyName = ""
        return

    ; Aktive Modifier
    mods := ""
    if GetKeyState("Ctrl")
        mods .= "^"
    if GetKeyState("Alt")
        mods .= "!"
    if GetKeyState("Shift")
        mods .= "+"
    if GetKeyState("LWin") || GetKeyState("RWin")
        mods .= "#"

    ; Delay davor sichern
    if LastDelay > 0 {
        ActionsList.Push(Map("Type", "Delay", "Time", LastDelay))
        LastDelay := 0
    }

    ActionsList.Push(Map("Type", "KeyPress", "Key", mods "{" keyName "}"))
    LastActionTime := A_TickCount
    UpdateActionsList()
}

; ─────────────────────────────────────────────
ExitScript(*) {
    ; Alle Timer stoppen bevor das Fenster abgebaut wird
    SetTimer(UpdateGui,            0)
    SetTimer(RecordingTimer,       0)
    SetTimer(PlaybackTimer,        0)
    SetTimer(LVDragTimer,          0)
    SetTimer(UpdateInsertMousePos, 0)
    ; OnMessage-Handler abmelden damit sie nicht mehr feuern während ExitApp läuft
    OnMessage(0x004E, LV_CustomDraw,        0)
    OnMessage(0x004E, LV_OnNotify_Drag,     0)
    OnMessage(0x004E, SeqLV_CustomDraw,     0)
    OnMessage(0x004E, SeqLV_OnNotify_Drag,  0)
    StopKeyHook()
    ExitApp()
}
