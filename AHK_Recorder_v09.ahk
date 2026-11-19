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
#Include click_actions.ahk
#Include screen_mapping.ahk
#Include playback_preview.ahk

CoordMode("Mouse", "Screen")

global ActionsList          := []
global RecordingListRefreshPending := false
global IsRecording          := false
global IsReplaying          := false
global StopRequested        := false
global PlaybackActions      := []
global PlaybackRun          := 0
global RepeatMode           := false
global LastDelay            := 0
global RecordingTimeBase    := 0
global CurrentAction        := 1

; Aktion-Tracking für Status-Box
global LastActionTime       := 0
global LastPlaybackAction   := ""
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
global MoveLastX              := ""
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
#HotIf IsMainRecorderActive()
^n::MenuFileNew()
^s::SaveActionsQuick()
^z::MenuUndo()
^y::MenuRedo()
#HotIf

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
Enter::EditSelectedAction()
#HotIf

#HotIf IsSeqLVFocused()
Delete::SeqRemove()
Enter::SeqPlaySelectedRow()
#HotIf

DetectScreenBounds()
ShowGui()
RefreshScreenProfileUI()
SetTimer(UpdateGui, 50)

; ─────────────────────────────────────────────
EditSelectedAction() {
    global MainCurrentLV
    if !IsObject(MainCurrentLV)
        return
    row := MainCurrentLV.GetNext(0)
    if row > 0
        EditAction(MainCurrentLV, row)
}

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
AppendRecordingDelay(now := A_TickCount, finished := unset) {
    global ActionsList, RecordingTimeBase
    elapsed := (now - RecordingTimeBase) & 0xFFFFFFFF
    endTime := finished ?? now
    if ((endTime - RecordingTimeBase) & 0xFFFFFFFF) <= 0x7FFFFFFF
        RecordingTimeBase := endTime
    if elapsed > 0 && elapsed <= 0x7FFFFFFF
        ActionsList.Push(Map("Type", "Delay", "Time", elapsed))
}

IsMainRecorderActive() {
    global GuiMain
    return IsSet(GuiMain) && IsObject(GuiMain) && DllCall("GetForegroundWindow", "Ptr") = GuiMain.Hwnd
}

IsRecorderWindow(hwnd) {
    if !hwnd
        return false
    static recorderPid := DllCall("GetCurrentProcessId", "UInt")
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &windowPid := 0, "UInt")
    return windowPid = recorderPid
}

CheckPlaybackKeyboardTarget(hwnd) {
    if IsRecorderWindow(hwnd)
        throw Error("Ein Recorder-Fenster hat den Tastaturfokus. Bitte die Zielanwendung fokussieren oder einen Countdown einstellen.")
}

CheckPlaybackMouseTarget(hwnd := unset) {
    if !IsSet(hwnd)
        MouseGetPos(, , &hwnd)
    if IsRecorderWindow(hwnd)
        throw Error("Ein Recorder-Fenster liegt unter der Maus. Bitte das Fenster aus dem Aktionsbereich verschieben.")
}

RecordScroll(direction) {
    global ActionsList, LastActionTime, IsRecording
    if !IsRecording
        return
    MouseGetPos(&x, &y, &hwnd)
    if IsRecorderWindow(hwnd)
        return
    AppendRecordingDelay()
    if ActionsList.Length > 0 {
        last := ActionsList[ActionsList.Length]
        if (last["Type"] = "Scroll" && last["Direction"] = direction
            && last.Get("X", "") = x && last.Get("Y", "") = y) {
            LastActionTime := A_TickCount
            last["Amount"] += 1
            ActionsList[ActionsList.Length] := last
            QueueRecordingListRefresh()
            return
        }
    }
    AppendRecordedAction(Map("Type", "Scroll", "Direction", direction, "Amount", 1, "X", x, "Y", y))
    LastActionTime := A_TickCount
    QueueRecordingListRefresh()
}

; ─────────────────────────────────────────────
TryParseIntegerSetting(value, minimum, &parsed) {
    value := Trim(value)
    if !RegExMatch(value, "^\+?[0-9]+$")
        return false
    normalized := LTrim(LTrim(value, "+"), "0")
    if normalized = ""
        normalized := "0"
    candidate := Integer(normalized)
    if !(String(candidate) == normalized) || candidate < minimum
        return false
    parsed := candidate
    return true
}

ReadIntegerSetting(field, previous, minimum) {
    if TryParseIntegerSetting(field.Value, minimum, &value)
        return value
    field.Value := previous
    return previous
}

BtnStartRecording(*) {
    global IsRecording, GuiMain, LastDelay, LongClickThreshold, MouseMoveThreshold
    global MouseWasDown, IsDragging, DownWasExcluded
    global MoveLastX, MoveLastY, IsReplaying, IsSeqPlaying, RecordingTimeBase
    if IsReplaying || IsSeqPlaying
        return
    if !IsRecording {
        InitializeRecordingScreen()
        MouseMoveThreshold := ReadIntegerSetting(GuiMain["MoveThreshEdit"], MouseMoveThreshold, 1)
        LongClickThreshold := ReadIntegerSetting(GuiMain["LongClickThresholdEdit"], LongClickThreshold, 50)
        LastDelay       := 0
        RecordingTimeBase := A_TickCount
        MouseWasDown    := false
        IsDragging      := false
        DownWasExcluded := false
        MoveLastX       := ""
        MoveLastY       := -1
        IsRecording     := true
        ; Aufnahmenummer = Anzahl bereits vorhandener "Aufnahme gestartet"-Kommentare + 1
        recNum := 1
        for a in ActionsList {
            if IsObject(a) && a is Map && a.Has("Type") && a["Type"] = "Comment"
                && InStr(a["Text"], "Aufnahme gestartet")
                recNum++
        }
        startComment := Map("Type", "Comment", "Text", recNum ". Aufnahme gestartet")
        if ActionsList.Length = 0
            ActionsList.InsertAt(1, startComment)   ; erste Aufnahme: ganz vorne
        else
            ActionsList.Push(startComment)          ; Folgeaufnahme: ans Ende (neuer Block)
        UpdateActionsList()
        SetTimer(RecordingTimer, 10)
        StartKeyHook()
        GuiMain["StatusText"].Value   := "Status: Aufnahme laeuft..."
    }
}

; ─────────────────────────────────────────────
BtnStopRecording(*) {
    global IsRecording, GuiMain, LastDelay, LastActionTime
    global MouseWasDown, IsDragging, DownWasExcluded, OptimizeClicks, MainCurrentLV
    if IsRecording {
        IsRecording     := false
        SetTimer(RecordingTimer, 0)
        CancelRecordingListRefresh()
        LastDelay       := 0
        LastActionTime  := 0
        MouseWasDown    := false
        IsDragging      := false
        DownWasExcluded := false
        StopKeyHook()
        GuiMain["StatusText"].Value    := "Status: Idle"
        GuiMain["DelayDisplay"].Value  := "Zeit seit letzter Aktion: --"
        ; Aufnahmenummer = Anzahl der Start-Kommentare in der Liste (wurde gerade gestartet)
        recNum := 0
        for a in ActionsList {
            if IsObject(a) && a is Map && a.Has("Type") && a["Type"] = "Comment"
                && InStr(a["Text"], "Aufnahme gestartet")
                recNum++
        }
        if recNum = 0
            recNum := 1
        ActionsList.Push(Map("Type", "Comment", "Text", recNum ". Aufnahme beendet"))
        if OptimizeClicks
            OptimizeConsecutiveClicks(true)
        else
            UpdateActionsList(ActionsList.Length)   ; ans Ende scrollen, nicht springen
        ; Selektion aufheben damit die Zeilenfarben sichtbar bleiben
        if IsObject(MainCurrentLV)
            MainCurrentLV.Modify(0, "-Select")
    }
}

; ─────────────────────────────────────────────
; Aufeinanderfolgende identische Klicks zusammenfassen.
; Muster: Klick[i], Delay[i+1], Klick[i+2], Delay[i+3], ...
; Auch unterschiedliche Abstände für die Wiedergabe und Wiederherstellung erhalten.
; ─────────────────────────────────────────────
OptimizeConsecutiveClicks(scrollToEnd := false) {
    global ActionsList, MainAllTabs, MainCurrentTab
    optimized := CombineClickRuns(ActionsList)
    if optimized.Length != ActionsList.Length {
        PushUndo()
        ActionsList := optimized
        MainAllTabs[MainCurrentTab] := ActionsList
    }
    UpdateActionsList(scrollToEnd ? ActionsList.Length : 0)
}







; ─────────────────────────────────────────────
; RestoreConsecutiveClicks
; Umkehrfunktion zu OptimizeConsecutiveClicks.
; Jeder Click-Eintrag mit Count > 1 wird in einzelne Click-Eintraege
; aufgefaltet. Falls ClickDelay gesetzt war, wird zwischen je zwei
; Klicks ein Delay-Eintrag eingefuegt.
; ─────────────────────────────────────────────
RestoreConsecutiveClicks(selected := unset) {
    global ActionsList, MainAllTabs, MainCurrentTab
    restored := ExpandClickRuns(ActionsList, selected?)
    if restored.Length = ActionsList.Length
        return

    PushUndo()
    ActionsList := restored
    MainAllTabs[MainCurrentTab] := ActionsList
    UpdateActionsList()
}



; ─────────────────────────────────────────────
; OptimizeSelectedClicks
; Wie OptimizeConsecutiveClicks, aber nur fuer den Bereich der
; markierten (Checked > Selektiert) Zeilen.
; ─────────────────────────────────────────────
OptimizeSelectedClicks(LV) {
    global ActionsList, MainAllTabs, MainCurrentTab

    ; Checked zuerst, dann selektiert
    indices := []
    row := 0
    loop {
        row := LV.GetNext(row, "Checked")
        if !row
            break
        indices.Push(row)
    }
    if indices.Length = 0 {
        row := 0
        loop {
            row := LV.GetNext(row)
            if !row
                break
            indices.Push(row)
        }
    }
    if indices.Length < 2
        return

    selected := Map()
    for index in indices
        selected[index] := true
    optimized := CombineClickRuns(ActionsList, selected)
    if optimized.Length = ActionsList.Length
        return

    PushUndo()
    ActionsList := optimized
    MainAllTabs[MainCurrentTab] := ActionsList
    UpdateActionsList()
}

; ─────────────────────────────────────────────
; RestoreSelectedClicks
; Wie RestoreConsecutiveClicks, aber nur fuer die markierten Zeilen.
; Jeder selektierte Mehrfachklick wird einzeln aufgefaltet.
; ─────────────────────────────────────────────
RestoreSelectedClicks(LV) {
    ; Checked zuerst, dann selektiert
    indices := []
    row := 0
    loop {
        row := LV.GetNext(row, "Checked")
        if !row
            break
        indices.Push(row)
    }
    if indices.Length = 0 {
        row := 0
        loop {
            row := LV.GetNext(row)
            if !row
                break
            indices.Push(row)
        }
    }
    if indices.Length = 0
        return

    selected := Map()
    for index in indices
        selected[index] := true
    RestoreConsecutiveClicks(selected)
}

; ─────────────────────────────────────────────
BtnPlayOnce(actions := unset) {
    global ActionsList, IsReplaying, RepeatMode, GuiMain, IsRecording, IsSeqPlaying
    if IsSeqPlaying {
        ShowInfo("Eine Sequenz läuft bereits.")
        return
    }
    if IsRecording {
        result := ShowYesNo("Aufnahme laeuft!`n`nAufnahme abbrechen?")
        if (result = "Yes")
            BtnAbortAll()
        return
    }
    source := actions ?? ActionsList
    if source.Length = 0 {
        ShowWarning("Keine Aktionen zum Abspielen vorhanden!")
        return
    }
    if IsReplaying {
        ShowInfo("Wiedergabe laeuft bereits!")
        return
    }
    RepeatMode := false
    GuiMain["StatusText"].Value := "Status: Wiedergabe laeuft..."
    StartPlayback(source)
}

; ─────────────────────────────────────────────
BtnPlayLoop(*) {
    global IsRecording, RepeatMode, GuiMain, StopRequested, IsReplaying, ActionsList, IsSeqPlaying
    if IsSeqPlaying {
        ShowInfo("Eine Sequenz läuft bereits.")
        return
    }
    if IsRecording {
        result := ShowYesNo("Aufnahme läuft!`n`nAufnahme abbrechen?")
        if (result = "Yes")
            BtnAbortAll()
        return
    }
    if !RepeatMode && ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen zum Abspielen vorhanden!")
        return
    }
    if !RepeatMode && IsReplaying {
        ShowInfo("Wiedergabe läuft bereits!")
        return
    }
    RepeatMode := !RepeatMode
    if RepeatMode {
        GuiMain["LoopStatus"].Value := "Loop: Aktiv"
        GuiMain["StatusText"].Value := "Status: Loop laeuft..."
        StartPlayback()
    } else {
        StopRequested := true
        IsReplaying := false
        SetTimer(PlaybackTimer, 0)
        GuiMain["LoopStatus"].Value := "Loop: Inaktiv"
        GuiMain["StatusText"].Value := "Status: Loop gestoppt"
    }
}

; ─────────────────────────────────────────────
BtnAbortAll(*) {
    global StopRequested, RepeatMode, IsRecording, IsReplaying, IsSeqPlaying, GuiMain, LastDelay, LastActionTime, ActionsList, MainCurrentLV
    global MouseWasDown, IsDragging, DownWasExcluded

    ; Nur wenn wirklich etwas lief
    wasRecording := IsRecording
    somethingWasRunning := wasRecording || IsReplaying || IsSeqPlaying

    StopRequested   := true
    RepeatMode      := false
    IsRecording     := false
    IsReplaying     := false
    MouseWasDown    := false
    IsDragging      := false
    DownWasExcluded := false
    SetTimer(RecordingTimer, 0)
    CancelRecordingListRefresh()
    SetTimer(PlaybackTimer, 0)
    LastDelay := 0
    LastActionTime := 0

    StopKeyHook()
    SeqAbort()

    GuiMain["StatusText"].Value   := "Status: Abgebrochen!"
    GuiMain["LoopStatus"].Value   := "Loop: Inaktiv"
    GuiMain["DelayDisplay"].Value := "Zeit seit letzter Aktion: --"

    if wasRecording {
        UpdateActionsList(ActionsList.Length)
        if IsObject(MainCurrentLV)
            MainCurrentLV.Modify(0, "-Select")
    }

    if somethingWasRunning {
        SoundBeep(1000, 150)
        ShowInfo("Aktionen abgebrochen!")
    }
}

; ─────────────────────────────────────────────
StartPlayback(actions := unset, readSettings := true, screenProfile := unset) {
    global CurrentAction, StopRequested, IsReplaying, ActionsList, PlaybackActions, PlaybackRun
    global PlayCountdown, PlayRepeatDone, GuiMain, LastPlaybackAction, LastActionTime

    source := actions ?? ActionsList
    if source.Length = 0 {
        ShowWarning("Keine Aktionen vorhanden!")
        return
    }

    profile := screenProfile ?? CurrentScreenProfile()
    try source := PrepareScreenPlayback(source, profile)
    catch Error as err {
        SeqAbort(err.Message)
        ShowWarning(err.Message)
        return
    }
    PlaybackActions := []
    for action in source
        PlaybackActions.Push(action.Clone())
    LastPlaybackAction := ""
    LastActionTime := 0
    run := ++PlaybackRun
    if readSettings
        ReadPlaybackSettings()

    StopRequested  := false
    IsReplaying    := true
    CurrentAction  := 1
    PlayRepeatDone := 0

    Loop PlayCountdown {
        GuiMain["StatusText"].Value := "Startet in " (PlayCountdown - A_Index + 1) " s..."
        if !PlaybackWait(1000, run)
            break
    }

    if run = PlaybackRun {
        if StopRequested
            IsReplaying := false
        else
            SetTimer(PlaybackTimer, -10)
    }
}

; Einstellungen aus GUI auslesen
ReadPlaybackSettings() {
    global GuiMain, PlayCountdown, PlaySpeedFactor, PlayRepeatCount, PlayMouseMultiplier

    PlayCountdown := ReadIntegerSetting(GuiMain["CountdownSec"], 0, 0)
    PlayRepeatCount := ReadIntegerSetting(GuiMain["RepeatCount"], 1, 0)
    PlaySpeedFactor := ReadSpeedFactor(GuiMain["SpeedFactor"])
    PlayMouseMultiplier := ReadSpeedFactor(GuiMain["MouseMultiplier"], 0.01)
}

IsPlaybackSpeedFactor(value, minimum := 0) {
    if !IsNumber(value)
        return false
    factor := Float(value)
    return factor > 0 && factor >= minimum && factor <= 1.7976931348623157e308
}

ReadSpeedFactor(field, minimum := 0) {
    value := Trim(field.Value)
    if IsPlaybackSpeedFactor(value, minimum)
        return Float(value)
    field.Value := 1
    return 1.0
}

; ─────────────────────────────────────────────
; PlaybackTimer - mit Speed, RepeatCount, Comment-Skip
; ─────────────────────────────────────────────
ScalePlaybackDelay(milliseconds, speed, mouseMultiplier := 1, &remainder := unset) {
    ; Zuerst durch den größeren Faktor teilen, um Zwischenüberläufe zu vermeiden.
    scaled := milliseconds / Max(speed, mouseMultiplier) / Min(speed, mouseMultiplier)
    if IsSet(remainder)
        scaled += remainder
    if !(scaled < 9223372036854775808.0)
        throw ValueError("Die berechnete Wartezeit ist zu groß. Bitte die Abspielgeschwindigkeit erhöhen.")
    rounded := Max(0, Round(scaled))
    if IsSet(remainder)
        remainder := scaled - rounded
    return rounded
}

PlaybackWait(milliseconds, run) {
    global StopRequested, PlaybackRun
    started := DllCall("Kernel32\GetTickCount64", "UInt64")
    while !StopRequested && run = PlaybackRun {
        remaining := milliseconds - (DllCall("Kernel32\GetTickCount64", "UInt64") - started)
        if remaining <= 0
            return true
        Sleep(Min(remaining, 20))
    }
    return false
}

PlaybackTimer(*) {
    global PlaybackRun, CurrentAction, StopRequested, IsReplaying, RepeatMode, GuiMain, PlaybackActions

    run := PlaybackRun
    actionIndex := CurrentAction
    try {
        Loop 32 {
            if StopRequested || run != PlaybackRun
                return
            actionIndex := CurrentAction
            if !PlaybackStep()
                return
            Sleep(-1)
        }
        if !StopRequested && run = PlaybackRun
            SetTimer(PlaybackTimer, -1)
    } catch as err {
        if run != PlaybackRun
            return

        StopRequested := true
        IsReplaying := false
        RepeatMode := false
        SetTimer(PlaybackTimer, 0)
        detail := "Wiedergabefehler bei Aktion " actionIndex ": " err.Message
        SeqAbort(detail)
        PlaybackActions := []
        CurrentAction := 1
        if IsSet(GuiMain) && IsObject(GuiMain) {
            GuiMain["LoopStatus"].Value := "Loop: Inaktiv"
            GuiMain["StatusText"].Value := "Status: " detail
        }
        ShowError(detail)
    }
}

NotePlaybackAction(action) {
    global LastPlaybackAction, LastActionTime, LastClickX, LastClickY
    LastPlaybackAction := action
    LastActionTime := A_TickCount
    switch action["Type"] {
        case "Click", "LongClick":
            LastClickX := action["X"]
            LastClickY := action["Y"]
        case "Drag":
            LastClickX := action["X2"]
            LastClickY := action["Y2"]
    }
}

PlaybackStep() {
    global PlaybackActions, PlaybackRun, CurrentAction, StopRequested, IsReplaying, RepeatMode, GuiMain
    global IsSeqPlaying, SeqSinglePlaying, PlaySpeedFactor, PlayRepeatCount, PlayRepeatDone, PlayMouseMultiplier

    actions := PlaybackActions
    run := PlaybackRun

    if !IsSet(GuiMain) || !IsObject(GuiMain) {
        IsReplaying := false
        return false
    }

    if StopRequested {
        IsReplaying := false
        return false
    }

    if !IsObject(actions) || actions.Length = 0 || CurrentAction > actions.Length {
        IsReplaying   := false
        StopRequested := false
        CurrentAction := 1

        ; Sequenz-Manager: naechste Sequenz?
        if IsSeqPlaying {
            SeqOnSequenceFinished()
            return false
        }

        if RepeatMode {
            PlayRepeatDone++
            ; RepeatCount=0 = endlos, sonst nach N Durchlaeufen stoppen
            if PlayRepeatCount > 0 && PlayRepeatDone >= PlayRepeatCount {
                RepeatMode := false
                GuiMain["LoopStatus"].Value  := "Loop: Aus"
                GuiMain["StatusText"].Value  := "Status: " PlayRepeatDone "x abgespielt"
                return false
            }
            IsReplaying   := true
            CurrentAction := 1
            SetTimer(PlaybackTimer, -10)
            return false
        }

        if SeqSinglePlaying {
            SeqSinglePlaying := false
            SeqUpdateStatus("Einzelwiedergabe beendet.")
        }
        GuiMain["StatusText"].Value := "Status: Wiedergabe beendet"
        return false
    }

    a   := actions[CurrentAction]
    typ := a["Type"]

    if typ = "Click" {
        button := a.Get("Button", "Left")
        count := a.Get("Count", 1)
        timing := a.Get("ClickTiming", [])
        segmentIndex := 1
        segmentRemaining := timing.Length ? timing[1]["Count"] : 0
        fixedDelay := a.Get("ClickDelay", 0)
        delayRemainder := 0.0
        MouseMove(a["X"], a["Y"], 0)
        Loop count {
            if StopRequested || run != PlaybackRun
                return false
            delayMs := 0
            if A_Index < count {
                interval := fixedDelay
                if timing.Length {
                    interval := timing[segmentIndex]["Delay"]
                    if --segmentRemaining = 0 && segmentIndex < timing.Length
                        segmentRemaining := timing[++segmentIndex]["Count"]
                }
                delayMs := ScalePlaybackDelay(interval, PlaySpeedFactor, 1, &delayRemainder)
            }
            CheckPlaybackMouseTarget()
            Click(button)
            if delayMs > 0 && !PlaybackWait(delayMs, run)
                return false
            if Mod(A_Index, 32) = 0
                Sleep(-1)
        }

    } else if typ = "LongClick" {
        btn    := a.Has("Button") ? a["Button"] : "Left"
        btnStr := (btn = "Right") ? "right" : "left"
        holdMs := Max(1, ScalePlaybackDelay(a["Duration"], PlaySpeedFactor))
        MouseMove(a["X"], a["Y"], 0)
        CheckPlaybackMouseTarget()
        MouseClick(btnStr, , , 1, 0, "D")
        try PlaybackWait(holdMs, run)
        finally MouseClick(btnStr, , , 1, 0, "U")

    } else if typ = "Drag" {
        btn    := a.Has("Button") ? a["Button"] : "Left"
        btnKey := (btn = "Right") ? "{RButton" : "{LButton"
        phaseDelay := Max(1, ScalePlaybackDelay(50, PlaySpeedFactor))
        MouseMove(a["X1"], a["Y1"], 0)
        if !PlaybackWait(phaseDelay, run)
            return false
        CheckPlaybackMouseTarget()
        SendEvent(btnKey " Down}")
        try {
            if !PlaybackWait(phaseDelay, run)
                return false
            MouseMove(a["X2"], a["Y2"], 3)
            PlaybackWait(phaseDelay, run)
        } finally {
            SendEvent(btnKey " Up}")
        }

    } else if typ = "Delay" {
        ; Geschwindigkeit anwenden
        PlaybackWait(ScalePlaybackDelay(a["Time"], PlaySpeedFactor), run)

    } else if typ = "Scroll" {
        if a.Has("X") && a.Has("Y")
            MouseMove(a["X"], a["Y"], 0)
        key := (a["Direction"] = "Up") ? "{WheelUp}" : "{WheelDown}"
        Loop a["Amount"] {
            if StopRequested || run != PlaybackRun
                return false
            CheckPlaybackMouseTarget()
            Send(key)
            if Mod(A_Index, 32) = 0
                Sleep(-1)
        }

    } else if typ = "KeyPress" {
        CheckPlaybackKeyboardTarget(DllCall("GetForegroundWindow", "Ptr"))
        SendEvent(a["Key"])

    } else if typ = "MouseMove" {
        ; Alle aufeinanderfolgenden MouseMove-Aktionen (inkl. Delays dazwischen)
        ; in einem einzigen Durchlauf abarbeiten.
        ; Delays werden durch PlayMouseMultiplier geteilt → Zeitkompression.
        i := CurrentAction
        delayRemainder := 0.0
        while i <= actions.Length {
            if StopRequested || run != PlaybackRun
                return false
            act := actions[i]
            if act["Type"] = "MouseMove" {
                MouseMove(act["X"], act["Y"], 0)
                NotePlaybackAction(act)
                i++
            } else if act["Type"] = "Delay" {
                ; Delay nur konsumieren wenn danach wieder ein MouseMove kommt
                if i + 1 <= actions.Length && actions[i + 1]["Type"] = "MouseMove" {
                    scaledDelay := ScalePlaybackDelay(act["Time"], PlaySpeedFactor, PlayMouseMultiplier, &delayRemainder)
                    if scaledDelay > 0 && !PlaybackWait(scaledDelay, run)
                        return false
                    i++
                } else {
                    break
                }
            } else {
                break
            }
            if Mod(i - CurrentAction, 32) = 0
                Sleep(-1)
        }
        CurrentAction := i
        return true

    } else if typ = "Comment" {
        ; Kommentare werden bei Wiedergabe uebersprungen

    } else if typ = "TextInput" {
        CheckPlaybackKeyboardTarget(DllCall("GetForegroundWindow", "Ptr"))
        SendText(a["Text"])
    }

    if StopRequested || run != PlaybackRun
        return false
    if typ != "Comment" && typ != "Delay"
        NotePlaybackAction(a)
    CurrentAction++
    return true
}

; ─────────────────────────────────────────────
; RecordingTimer - State Machine
; ─────────────────────────────────────────────
QueueRecordingListRefresh() {
    global RecordingListRefreshPending
    if RecordingListRefreshPending
        return
    RecordingListRefreshPending := true
    SetTimer(RefreshRecordingList, -100)
}

RefreshRecordingList() {
    global RecordingListRefreshPending, IsRecording
    CancelRecordingListRefresh()
    if IsRecording
        UpdateActionsList()
}

CancelRecordingListRefresh() {
    global RecordingListRefreshPending
    RecordingListRefreshPending := false
    SetTimer(RefreshRecordingList, 0)
}

RecordingTimer(*) {
    local mx, my, lDown, rDown, anyDown, currentButton, elapsed, dx, dy, dist
    global IsRecording, ActionsList, GuiMain, LastActionTime, LastClickX, LastClickY
    global MouseWasDown, MouseDownButton, MouseDownX, MouseDownY
    global MouseDownTime, IsDragging, DownWasExcluded
    global DragThreshold, LongClickThreshold
    global RecordMouseMoveEnabled, MoveLastX, MoveLastY, MouseMoveThreshold

    if !IsRecording || !IsSet(GuiMain) || !IsObject(GuiMain)
        return

    MouseGetPos(&mx, &my, &hwnd)
    overRecorder := IsRecorderWindow(hwnd)
    GuiMain["MousePos"].Value     := "Maus: X=" mx " Y=" my

    lDown         := GetKeyState("LButton", "P")
    rDown         := GetKeyState("RButton", "P")
    anyDown       := lDown || rDown
    currentButton := lDown ? "Left" : (rDown ? "Right" : "Left")

    ; Mausbewegung aufzeichnen (nur wenn kein Button gedrueckt)
    if RecordMouseMoveEnabled && !overRecorder && !anyDown && !MouseWasDown {
        if MoveLastX == "" {
            MoveLastX := mx
            MoveLastY := my
        } else {
            dx   := mx - MoveLastX
            dy   := my - MoveLastY
            dist := Sqrt(dx*dx + dy*dy)
            if dist >= MouseMoveThreshold {
                AppendRecordingDelay()
                AppendRecordedAction(Map("Type", "MouseMove", "X", mx, "Y", my))
                LastActionTime := RecordingTimeBase
                MoveLastX := mx
                MoveLastY := my
                QueueRecordingListRefresh()
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
            DownWasExcluded := overRecorder
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
                released := A_TickCount
                elapsed := (released - MouseDownTime) & 0xFFFFFFFF
                AppendRecordingDelay(MouseDownTime, released)
                if IsDragging {
                    AppendRecordedAction(Map("Type","Drag","Button",MouseDownButton,
                        "X1",MouseDownX,"Y1",MouseDownY,"X2",mx,"Y2",my))
                    LastClickX := mx
                    LastClickY := my
                } else if elapsed >= LongClickThreshold {
                    AppendRecordedAction(Map("Type","LongClick","Button",MouseDownButton,
                        "X",MouseDownX,"Y",MouseDownY,"Duration",elapsed))
                    LastClickX := MouseDownX
                    LastClickY := MouseDownY
                } else {
                    AppendRecordedAction(Map("Type","Click","Button",MouseDownButton,
                        "X",MouseDownX,"Y",MouseDownY))
                    LastClickX := MouseDownX
                    LastClickY := MouseDownY
                }
                LastActionTime := A_TickCount
                QueueRecordingListRefresh()
            }
            MouseWasDown    := false
            IsDragging      := false
            DownWasExcluded := false
        }
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
    global ActionsList, LastActionTime, IsRecording, KeyHook
    if !IsRecording || !IsObject(KeyHook) || ih != KeyHook
        return
    if IsRecorderWindow(DllCall("GetForegroundWindow", "Ptr"))
        return

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
    AppendRecordingDelay()

    ActionsList.Push(Map("Type", "KeyPress", "Key", mods "{" keyName "}"))
    LastActionTime := A_TickCount
    QueueRecordingListRefresh()
}

; ─────────────────────────────────────────────
ExitScript(*) {
    global GuiSeqManager
    if IsObject(GuiSeqManager) && DllCall("IsWindowVisible", "Ptr", GuiSeqManager.Hwnd, "Int") {
        if SeqManagerClose()
            return true
    }

    ; Alle Timer stoppen bevor das Fenster abgebaut wird
    SetTimer(UpdateGui,            0)
    SetTimer(RecordingTimer,       0)
    CancelRecordingListRefresh()
    SetTimer(PlaybackTimer,        0)
    SetTimer(LVDragTimer,          0)
    SetTimer(UpdateInsertMousePos, 0)
    ; OnMessage-Handler abmelden damit sie nicht mehr feuern während ExitApp läuft
    OnMessage(0x004E, LV_CustomDraw,        0)
    OnMessage(0x004E, LV_OnNotify_Drag,     0)
    OnMessage(0x004E, SeqLV_CustomDraw,     0)
    OnMessage(0x004E, SeqLV_OnNotify_Drag,  0)
    StopKeyHook()
    try RecorderNumericSettings(true)
    ExitApp()
}
