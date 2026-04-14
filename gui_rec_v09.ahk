;=========================
; Datei: gui_rec_v09.ahk
; Version 0.9
; - Menüleiste, kompakte Toolbar, Status-GroupBox
; - Rechtsklick-Kontextmenü mit Drag & Drop Sortierung
; - Status-Box mit Aktion-Tracking und Letzter-Klick-Anzeige
; - Blaue GroupBox-Titel, Button-Symbole
;=========================

#Requires AutoHotkey v2.0

CoordMode("ToolTip", "Screen")

global GuiMain          := ""
global GuiActionInsert  := ""
global GuiActionEdit    := ""
global dropdown
global StopRecordingBtn

global actionTypes := ["Mausklick", "Zeitverzögerung", "Drag & Drop", "Scrollen", "Langer Klick", "Kommentar", "Text eingeben"]

global BtnsDisableOnRecord  := []
global BtnsAllowedOnRecord  := []
global OriginalBtnText      := Map()
global _LastRecordingState  := -1

; Menü-Referenzen
global MenuFileRef    := ""
global MenuEditRef    := ""
global MenuRecordRef  := ""
global MenuPlayRef    := ""

; ListView Zeilenfarben (NM_CUSTOMDRAW)
global LVRowColors    := Map()

global CurrentFilePath := ""

; ─────────────────────────────────────────────
ShowGui() {
    global GuiMain, ActionsList
    global StartRecordingBtn, StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn
    global AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn
    global OriginalBtnText, BtnsDisableOnRecord, BtnsAllowedOnRecord
    global MenuFileRef, MenuEditRef, MenuRecordRef, MenuPlayRef

    if !IsObject(ActionsList)
        ActionsList := []

    if IsObject(GuiMain) {
        GuiMain.Show()
        return
    }

    ; ══════════════════════════════════════════
    ; MENÜLEISTE
    ; ══════════════════════════════════════════
    MenuFileRef := Menu()
    MenuFileRef.Add("Neu`tStrg+N",             (*) => MenuFileNew())
    MenuFileRef.Add("Laden...`tStrg+O",        (*) => LoadActions())
    MenuFileRef.Add("Speichern`tStrg+S",       (*) => SaveActionsQuick())
    MenuFileRef.Add("Speichern unter...",       (*) => SaveActions())
    MenuFileRef.Add()
    MenuFileRef.Add("Beenden",                 (*) => ExitScript())

    MenuEditRef := Menu()
    MenuEditRef.Add("Rückgängig`tStrg+Z",       (*) => MenuUndo())
    MenuEditRef.Add("Wiederholen`tStrg+Y",      (*) => MenuRedo())
    MenuEditRef.Add()
    MenuEditRef.Add("Einfügen...",              (*) => AddAction())
    MenuEditRef.Add("Löschen`tEntf",            (*) => DelAction())
    MenuEditRef.Add("Alle auswählen`tStrg+A",   (*) => SelectAllInListView())
    MenuEditRef.Add()
    MenuEditRef.Add("Alle Delays setzen...",    (*) => SetAllDelays())

    MenuRecordRef := Menu()
    MenuRecordRef.Add("Aufnahme starten`tF9",  (*) => BtnStartRecording())
    MenuRecordRef.Add("Aufnahme stoppen`tF10", (*) => BtnStopRecording())
    MenuRecordRef.Add()
    MenuRecordRef.Add("Tastatur aufnehmen",    (*) => ToggleRecordKeysMenu())
    MenuRecordRef.Add("Mausbewegung aufnehmen", (*) => ToggleRecordMoveMenu())

    MenuPlayRef := Menu()
    MenuPlayRef.Add("Einmal abspielen`tF11",   (*) => BtnPlayOnce())
    MenuPlayRef.Add("Loop umschalten`tF12",    (*) => BtnPlayLoop())
    MenuPlayRef.Add()
    MenuPlayRef.Add("Abbrechen`tESC",          (*) => BtnAbortAll())

    menuExtras := Menu()
    menuExtras.Add("Sequenz-Manager",          (*) => ShowSeqManager())
    menuExtras.Add("Zeit-Manager",             (*) => SetAllDelays())

    menuHelp := Menu()
    menuHelp.Add("Schnellhilfe",               (*) => ShowHelpDialog())
    menuHelp.Add("Über AHK Recorder",         (*) => ShowAboutDialog())

    mBar := MenuBar()
    mBar.Add("Datei",      MenuFileRef)
    mBar.Add("Bearbeiten", MenuEditRef)
    mBar.Add("Aufnahme",   MenuRecordRef)
    mBar.Add("Wiedergabe", MenuPlayRef)
    mBar.Add("Extras",     menuExtras)
    mBar.Add("?",          menuHelp)

    ; ══════════════════════════════════════════
    ; FENSTER
    ; ══════════════════════════════════════════
    GuiMain := Gui("+Resize +AlwaysOnTop", "AHK Recorder by EmJay  v0.9")
    GuiMain.MenuBar := mBar
    GuiMain.SetFont("s10")
    GuiMain.OnEvent("Close", (*) => ExitScript())

    ; ── Kompakte Toolbar ──
    ; Zeile 1: Datei-Aktionen + Nav Anfang
    InsertBtn := GuiMain.AddButton("x8 y6 w96 h26 Background0x00CC00 cWhite",  "✚ Einfügen")
    DeleteBtn := GuiMain.AddButton("x+3 yp w84 h26 Background0xCC0000 cWhite", "✖ Löschen")
    SaveBtn   := GuiMain.AddButton("x+3 yp w102 h26 Background0x0070CC cWhite", "💾 Speichern")
    LoadBtn   := GuiMain.AddButton("x+3 yp w84 h26 Background0x0070CC cWhite",  "📂 Laden")
    InsertBtn.OnEvent("Click", (*) => AddAction())
    DeleteBtn.OnEvent("Click", (*) => DelAction())
    SaveBtn.OnEvent("Click",   (*) => SaveActionsQuick())
    LoadBtn.OnEvent("Click",   (*) => LoadActions())
    GuiMain.AddButton("x+3 yp w104 h26 Background0x555555 cWhite", "⬆ Zum Anfang")
        .OnEvent("Click", (*) => LVScrollToTop())

    ; Zeile 2: Manager-Tools + Nav Ende
    GuiMain.AddButton("x8 y+4 w186 h26 Background0x404040 cWhite", "Sequenz-Manager")
        .OnEvent("Click", (*) => ShowSeqManager())
    GuiMain.AddButton("x+3 yp w186 h26 Background0x404040 cWhite", "Zeit-Manager")
        .OnEvent("Click", (*) => SetAllDelays())
    GuiMain.AddButton("x+3 yp w104 h26 Background0x555555 cWhite", "⬇ Zum Ende")
        .OnEvent("Click", (*) => LVScrollToBottom())

    ; ── Aufnahmeeinstellungen GroupBox ──
    GuiMain.AddGroupBox("x8 y+6 w492 h48 Section cBlue", "Aufnahmeeinstellungen")
    GuiMain.SetFont("s9")

    chkKeys := GuiMain.AddCheckBox("xs+12 ys+18 vChkRecordKeys", "Tastatur aufnehmen")
    chkKeys.OnEvent("Click", (*) => OnChkRecordKeys())
    GuiMain.AddButton("xs+126 ys+17 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Tastatureingaben aufnehmen:`n`n"
            "Alle Tastendrücke während der Aufnahme werden gespeichert`n"
            "und bei Wiedergabe an die aktive Anwendung gesendet.`n`n"
            "Modifier-Tasten (Strg, Alt, Shift, Win) werden automatisch`n"
            "als Kombination erkannt, z.B. ^c für Strg+C.", "Hilfe"))

    chkMove := GuiMain.AddCheckBox("xs+150 ys+18 vChkRecordMove", "Mausbewegung aufnehmen")
    chkMove.OnEvent("Click", (*) => OnChkRecordMove())
    GuiMain.AddButton("xs+300 ys+17 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Mausbewegungen aufnehmen:`n`n"
            "Bewegungen der Maus (ohne Klick) werden aufgezeichnet`n"
            "und bei Wiedergabe langsam nachgefahren.", "Hilfe"))

    GuiMain.AddText("xs+324 ys+20", "Maus-Schwellenwert:")
    GuiMain.AddEdit("xs+426 ys+18 vMoveThreshEdit w36", "8")
    GuiMain.AddText("xs+464 ys+20", "px")
    GuiMain.AddButton("xs+476 ys+17 w14 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Maus-Schwellenwert:`n`n"
            "Minimale Bewegung in Pixeln bevor ein neuer Punkt`n"
            "in der Liste gespeichert wird.`n`n"
            "3 px  = sehr genau, viele Einträge`n"
            "8 px  = Standard, ausgewogen`n"
            "15 px = grob, wenige Einträge", "Hilfe"))

    ; ── Abspieleinstellungen GroupBox ──
    GuiMain.SetFont("s10")
    GuiMain.AddGroupBox("x8 y+8 w492 h76 Section cBlue", "Abspieleinstellungen")
    GuiMain.SetFont("s9")

    ; Zeile 1: Countdown | Wiederholungen
    GuiMain.AddText("xs+12 ys+20", "Countdown (s):")
    GuiMain.AddEdit("xs+88 ys+18 vCountdownSec w36", "0")
    GuiMain.AddButton("xs+126 ys+17 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Countdown vor Wiedergabe:`n`n"
            "Wartezeit in Sekunden bevor die Wiedergabe startet.`n"
            "Gibt dir Zeit das Zielfenster zu fokussieren.`n`n"
            "0 = sofort starten.", "Hilfe"))

    GuiMain.AddText("xs+164 ys+20", "Wiederholungen:")
    GuiMain.AddEdit("xs+252 ys+18 vRepeatCount w36", "0")
    GuiMain.AddButton("xs+290 ys+17 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Wiederholungsanzahl für Loop:`n`n"
            "0 = endlos (bis ESC/Pause gedrückt wird)`n"
            "5 = genau 5 Durchläufe, dann automatisch Stop.", "Hilfe"))

    ; Zeile 2: Abspielgeschwindigkeit | Mausgeschwindigkeit
    GuiMain.AddText("xs+12 ys+48", "Abspielgeschwindigkeit:")
    GuiMain.AddEdit("xs+152 ys+46 vSpeedFactor w40", "1.0")
    GuiMain.AddButton("xs+194 ys+45 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Abspielgeschwindigkeit:`n`n"
            "2.0 = doppelt so schnell (Delays halbiert)`n"
            "1.0 = normale Geschwindigkeit`n"
            "0.5 = halb so schnell (Delays verdoppelt)`n`n"
            "Betrifft: Zeitverzögerungen und Langer Klick.", "Hilfe"))

    GuiMain.AddText("xs+240 ys+48", "Mausgeschwindigkeit (×):")
    GuiMain.AddEdit("xs+390 ys+46 vMouseMultiplier w44", "1")
    GuiMain.AddButton("xs+436 ys+45 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Mausgeschwindigkeit – Zeitkompressionsfaktor:`n`n"
            "1   = genauso schnell wie aufgenommen`n"
            "2   = doppelt so schnell (Pausen halbiert)`n"
            "10  = zehnmal schneller`n"
            "100 = hundertmal schneller (nahezu sofort)`n`n"
            "Der Faktor teilt alle Wartezeiten zwischen`n"
            "Mausbewegungspunkten durch den eingegebenen Wert.`n"
            "Betrifft nur aufgenommene Mausbewegungen.", "Hilfe"))

    GuiMain.SetFont("s10")

    ; ── ListView ──
    LV := GuiMain.AddListView("vActionList x8 y+6 w492 h300 Grid", ["Nr", "Aktion", "Wert"])
    LV.ModifyCol(1, "50")
    LV.ModifyCol(2, "155")
    LV.ModifyCol(3, "262")
    LV.OnEvent("DoubleClick", (lv, r) => EditAction(lv, r))
    LV.OnEvent("ContextMenu", (lv,r,rc,x,y) => ShowLVContextMenu(lv,r,rc,x,y))
    SetupLVColors()     ; NM_CUSTOMDRAW für Zeilenfarben aktivieren
    SetupLVDragDrop()   ; Drag & Drop zum Umsortieren aktivieren

    ; ── Steuerung GroupBox ──
    GuiMain.AddGroupBox("x8 y+6 w492 h170 Section cBlue", "Steuerung")

    BtnW  := 238
    BtnH  := 42
    BtnH2 := 34

    ; Reihe 1: Aufnahme
    StartRecordingBtn := GuiMain.AddButton("xs+4 ys+18 w" BtnW " h" BtnH " Background0x009900 cWhite", "AUFNAHME STARTEN  (F9)")
    StopRecordingBtn  := GuiMain.AddButton("xs+" (BtnW+8) " ys+18 w" BtnW " h" BtnH " Background0xCC0000 cWhite", "AUFNAHME STOPPEN  (F10)")
    StartRecordingBtn.OnEvent("Click", (*) => BtnStartRecording())
    StopRecordingBtn.OnEvent("Click",  (*) => BtnStopRecording())

    ; Reihe 2: Wiedergabe
    PlayOnceBtn     := GuiMain.AddButton("xs+4 ys+66 w" BtnW " h" BtnH " Background0x0070CC cWhite", "EINMAL ABSPIELEN  (F11)")
    ToggleRepeatBtn := GuiMain.AddButton("xs+" (BtnW+8) " ys+66 w" BtnW " h" BtnH " Background0xCC7700 cWhite", "LOOP AN/AUS  (F12)")
    PlayOnceBtn.OnEvent("Click",     (*) => BtnPlayOnce())
    ToggleRepeatBtn.OnEvent("Click", (*) => BtnPlayLoop())

    ; Reihe 3: Abbrechen / Beenden
    AbortBtn := GuiMain.AddButton("xs+4 ys+114 w" BtnW " h" BtnH2 " Background0x660088 cWhite", "ABBRECHEN  (ESC / Pause)")
    ExitBtn  := GuiMain.AddButton("xs+" (BtnW+8) " ys+114 w" BtnW " h" BtnH2 " Background0x444444 cWhite", "BEENDEN")
    AbortBtn.OnEvent("Click", (*) => BtnAbortAll())
    ExitBtn.OnEvent("Click",  (*) => ExitScript())

    ; ── Status GroupBox ──
    GuiMain.SetFont("s10")
    GuiMain.AddGroupBox("x8 y+6 w492 h126 Section cBlue", "Status")
    GuiMain.SetFont("s9")
    ; Zeile 1: Status | Loop
    GuiMain.AddText("vStatusText  xs+8  ys+20 w230",       "Status: Idle")
    GuiMain.AddText("vLoopStatus  x+6   yp    w230",       "Loop: Aus")
    ; Zeile 2: Geladene Aktionen (volle Breite)
    GuiMain.AddText("vCurrentFile xs+8  y+5   w460 cBlue", "Geladene Aktionen: (keine)")
    ; Zeile 3: Mausposition | Letzter Klick
    GuiMain.AddText("vMousePos    xs+8  y+5   w228",       "Maus: X=0 Y=0")
    GuiMain.AddText("vLastClick   x+6   yp    w228",       "Letzter Klick: X=0 Y=0")
    ; Zeile 4: Zeit seit letzter Aktion | Letzte Aktion
    GuiMain.AddText("vDelayDisplay xs+8 y+5   w228 cGray", "Zeit seit letzter Aktion: --")
    GuiMain.AddText("vLastAction   x+6  yp    w228 cGray", "Letzte Aktion: --")
    ; Zeile 5: Bildschirmgrenzen
    GuiMain.AddText("vScreenBounds xs+8 y+5   w460 cGray", "Auflosung: ermittle...")
    GuiMain.SetFont("s10")

    ; ── Button-Gruppen für UpdateGui ──
    BtnsDisableOnRecord := [StartRecordingBtn, InsertBtn, SaveBtn, LoadBtn, PlayOnceBtn, ToggleRepeatBtn]
    BtnsAllowedOnRecord := [StopRecordingBtn, AbortBtn, ExitBtn, DeleteBtn]

    for btn in [StartRecordingBtn, StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn,
                AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn]
        OriginalBtnText[btn.Hwnd] := btn.Text

    GuiMain.Show()

    ; Zuletzt geöffnet laden und Menü aufbauen
    LoadRecentFiles()
    RebuildRecentMenu()
    ; Undo/Redo initial deaktivieren
    UpdateUndoMenuState()
}

; ─────────────────────────────────────────────
; Menü-Toggles für Aufnahme-Optionen
; ─────────────────────────────────────────────
ToggleRecordKeysMenu(*) {
    global RecordKeyboardEnabled, MenuRecordRef, GuiMain
    RecordKeyboardEnabled := !RecordKeyboardEnabled
    if RecordKeyboardEnabled {
        MenuRecordRef.Check("Tastatur aufnehmen")
    } else {
        MenuRecordRef.Uncheck("Tastatur aufnehmen")
    }
    GuiMain["ChkRecordKeys"].Value := RecordKeyboardEnabled
}

ToggleRecordMoveMenu(*) {
    global RecordMouseMoveEnabled, MenuRecordRef, GuiMain, MouseMoveThreshold
    RecordMouseMoveEnabled := !RecordMouseMoveEnabled
    if RecordMouseMoveEnabled {
        MenuRecordRef.Check("Mausbewegung aufnehmen")
    } else {
        MenuRecordRef.Uncheck("Mausbewegung aufnehmen")
    }
    GuiMain["ChkRecordMove"].Value := RecordMouseMoveEnabled
    val := GuiMain["MoveThreshEdit"].Value
    if IsNumber(val) && Integer(val) >= 1 {
        MouseMoveThreshold := Integer(val)
    }
}

; ─────────────────────────────────────────────
; Datei-Menü: Neu
; ─────────────────────────────────────────────
MenuFileNew(*) {
    global ActionsList, GuiMain, CurrentFilePath
    if ActionsList.Length > 0 {
        result := ShowYesNo("Aktuelle Liste verwerfen und neu beginnen?")
        if result != "Yes"
            return
    }
    ActionsList    := []
    CurrentFilePath := ""
    UpdateActionsList()
    SetCurrentFile("")
    GuiMain["StatusText"].Value := "Status: Neue Liste"
}

; ─────────────────────────────────────────────
; Schnell-Speichern (Strg+S)
; ─────────────────────────────────────────────
SaveActionsQuick(*) {
    global CurrentFilePath
    if CurrentFilePath != "" {
        SaveActionsToFile(CurrentFilePath)
    } else {
        SaveActions()
    }
}

SaveActionsToFile(filePath) {
    global ActionsList
    try {
        serial := ToJsonCompatible(ActionsList)
        json   := Jxon_Dump(serial, 0)
        f      := FileOpen(filePath, "w", "UTF-8")
        if !f {
            ShowError("Datei konnte nicht gespeichert werden.")
            return
        }
        f.Write(json)
        f.Close()
        SetCurrentFile(filePath)
    } catch as err {
        ShowError("Fehler beim Speichern:`n" err.Message)
    }
}

; ─────────────────────────────────────────────
; Rechtsklick-Kontextmenü in der ListView
; ─────────────────────────────────────────────
ShowLVContextMenu(LV, rowIndex, isRightClick, x, y) {
    global ActionsList

    ctx := Menu()

    if rowIndex > 0 && rowIndex <= ActionsList.Length {
        ctx.Add("Bearbeiten`tEnter",    (*) => EditAction(LV, rowIndex))
        ctx.Add("Löschen`tEntf",        (*) => DelSingleRow(rowIndex))
        ctx.Add()
        ctx.Add("Nach oben",            (*) => MoveActionRow(rowIndex, -1))
        ctx.Add("Nach unten",           (*) => MoveActionRow(rowIndex, +1))
        if rowIndex <= 1
            ctx.Disable("Nach oben")
        if rowIndex >= ActionsList.Length
            ctx.Disable("Nach unten")
    } else {
        ctx.Add("Einfügen...",          (*) => AddAction())
    }

    ctx.Add()
    ctx.Add("Alle auswählen`tStrg+A",  (*) => SelectAllInListView())
    ctx.Add()
    ctx.Add("Alle löschen",            (*) => DelAllActions())
    ctx.Show(x, y)
}

; Einzelne Zeile per Kontextmenü löschen
DelSingleRow(rowIndex) {
    global ActionsList
    if rowIndex >= 1 && rowIndex <= ActionsList.Length {
        PushUndo()
        ActionsList.RemoveAt(rowIndex)
        UpdateActionsList()
    }
}

; Alle Einträge löschen
DelAllActions() {
    global ActionsList, GuiMain
    if ActionsList.Length = 0
        return
    result := ShowYesNo("Alle " ActionsList.Length " Aktionen löschen?")
    if result != "Yes"
        return
    PushUndo()
    ActionsList := []
    GuiMain["ActionList"].Delete()
}

; Zeile per Kontextmenü verschieben
MoveActionRow(rowIndex, direction) {
    global ActionsList, GuiMain
    newIndex := rowIndex + direction
    if newIndex < 1 || newIndex > ActionsList.Length
        return
    tmp                    := ActionsList[newIndex]
    ActionsList[newIndex]  := ActionsList[rowIndex]
    ActionsList[rowIndex]  := tmp
    UpdateActionsList()
    LV := GuiMain["ActionList"]
    LV.Modify(newIndex, "Select Focus Vis")
}

; ─────────────────────────────────────────────
; Hilfe-Dialoge
; ─────────────────────────────────────────────
ShowHelpDialog(*) {
    MsgBox(
        "HOTKEYS`n"
        "  F9   Aufnahme starten`n"
        "  F10  Aufnahme stoppen`n"
        "  F11  Einmal abspielen`n"
        "  F12  Loop an/aus`n"
        "  ESC  Abbruch (nur wenn aktiv)`n"
        "  Pause  Notfall-Abbruch`n"
        "  Strg+N  Neue Liste`n"
        "  Strg+S  Speichern`n`n"
        "AUFNAHME ERKENNT AUTOMATISCH`n"
        "  Linksklick / Rechtsklick`n"
        "  Langer Klick (> 500 ms)`n"
        "  Drag & Drop`n"
        "  Scrollen (Mausrad)`n"
        "  Tastatur (Checkbox aktivieren)`n"
        "  Mausbewegung (Checkbox + Schwellenwert)`n`n"
        "LISTE BEARBEITEN`n"
        "  Doppelklick / Enter = Eintrag bearbeiten`n"
        "  Entf = Ausgewählte Einträge löschen`n"
        "  Rechtsklick = Kontextmenü`n"
        "  Strg+A = Alle auswählen`n`n"
        "MANAGER`n"
        "  Zeit-Manager: Alle Zeitverzögerungen auf einen Wert setzen`n"
        "  Sequenz-Manager: JSON-Dateien laden, sortieren, verketten",
        "Schnellhilfe", 0x40 | 0x40000)
}

ShowAboutDialog(*) {
    MsgBox(
        "AHK Recorder by EmJay`n"
        "Version 0.9`n`n"
        "Ein Makro-Recorder für AutoHotkey v2.`n"
        "Aufnehmen, bearbeiten und abspielen von`n"
        "Maus- und Tastaturaktionen.`n`n"
        "Neu in v0.9:`n"
        "  • Drag & Drop Sortierung in der Liste`n"
        "  • Status-Box mit Aktion-Tracking`n"
        "  • Blaue GroupBox-Titel, Button-Symbole`n"
        "  • Alle deutschen Umlaute korrigiert",
        "Über AHK Recorder", 0x40 | 0x40000)
}

; ─────────────────────────────────────────────
; Checkbox-Handler (synchronisiert mit Menü)
; ─────────────────────────────────────────────
OnChkRecordKeys(*) {
    global RecordKeyboardEnabled, GuiMain, MenuRecordRef
    RecordKeyboardEnabled := GuiMain["ChkRecordKeys"].Value
    if IsObject(MenuRecordRef) {
        if RecordKeyboardEnabled {
            MenuRecordRef.Check("Tastatur aufnehmen")
        } else {
            MenuRecordRef.Uncheck("Tastatur aufnehmen")
        }
    }
}

OnChkRecordMove(*) {
    global RecordMouseMoveEnabled, GuiMain, MouseMoveThreshold, MenuRecordRef
    RecordMouseMoveEnabled := GuiMain["ChkRecordMove"].Value
    if IsObject(MenuRecordRef) {
        if RecordMouseMoveEnabled {
            MenuRecordRef.Check("Mausbewegung aufnehmen")
        } else {
            MenuRecordRef.Uncheck("Mausbewegung aufnehmen")
        }
    }
    val := GuiMain["MoveThreshEdit"].Value
    if IsNumber(val) && Integer(val) >= 1 {
        MouseMoveThreshold := Integer(val)
    }
}

; ─────────────────────────────────────────────
UpdateGui() {
    global GuiMain, LastDelay, RepeatMode, IsRecording, ActionsList
    global BtnsDisableOnRecord, BtnsAllowedOnRecord, OriginalBtnText
    global _LastRecordingState
    global StartRecordingBtn, InsertBtn, SaveBtn, LoadBtn, PlayOnceBtn, ToggleRepeatBtn
    global MenuFileRef, MenuEditRef, MenuRecordRef, MenuPlayRef
    global LastActionTime, LastClickX, LastClickY
    global ScreenXMin, ScreenYMin, ScreenXMax, ScreenYMax

    if !IsObject(GuiMain)
        return
    try {
        if !WinExist("ahk_id " GuiMain.Hwnd)
            return
    } catch {
        return
    }

    try MouseGetPos(&x, &y)
    try GuiMain["MousePos"].Value  := "Maus: X=" x " Y=" y
    try GuiMain["LoopStatus"].Value := "Loop: " (RepeatMode ? "AN" : "Aus")
    try GuiMain["LastClick"].Value  := "Letzter Klick: X=" LastClickX " Y=" LastClickY

    ; Zeit seit letzter Aktion
    if LastActionTime > 0 {
        elapsed := A_TickCount - LastActionTime
        try GuiMain["DelayDisplay"].Value := "Zeit seit letzter Aktion: " elapsed " ms"
    } else {
        try GuiMain["DelayDisplay"].Value := "Zeit seit letzter Aktion: --"
    }

    ; Letzte Aktion aus ActionsList
    if IsObject(ActionsList) && ActionsList.Length > 0 {
        try GuiMain["LastAction"].Value := "Letzte Aktion: " FormatActionShort(ActionsList[ActionsList.Length])
    } else {
        try GuiMain["LastAction"].Value := "Letzte Aktion: --"
    }

    ; Bildschirmgrenzen (statisch, einmalig gesetzt)
    try GuiMain["ScreenBounds"].Value := "Auflosung: x_min=".ScreenXMin.", y_min=".ScreenYMin." ; x_max=".ScreenXMax.", y_max=".ScreenYMax

    currentState := IsRecording ? 1 : 0
    if currentState = _LastRecordingState
        return
    _LastRecordingState := currentState

    ; Menü-Items während Aufnahme deaktivieren
    if IsObject(MenuFileRef) {
        if IsRecording {
            MenuFileRef.Disable("Laden...`tStrg+O")
            MenuFileRef.Disable("Speichern`tStrg+S")
            MenuFileRef.Disable("Speichern unter...")
            MenuEditRef.Disable("Einfügen...")
            MenuPlayRef.Disable("Einmal abspielen`tF11")
            MenuPlayRef.Disable("Loop umschalten`tF12")
        } else {
            MenuFileRef.Enable("Laden...`tStrg+O")
            MenuFileRef.Enable("Speichern`tStrg+S")
            MenuFileRef.Enable("Speichern unter...")
            MenuEditRef.Enable("Einfügen...")
            MenuPlayRef.Enable("Einmal abspielen`tF11")
            MenuPlayRef.Enable("Loop umschalten`tF12")
        }
    }

    ; Toolbar-Buttons
    for btn in BtnsDisableOnRecord {
        try {
            if IsRecording {
                btn.Disable()
                btn.Opt("Background0xA0A0A0 cBlack")
            } else {
                btn.Enable()
                if (btn = StartRecordingBtn) {
                    btn.Opt("Background0x009900 cWhite")
                } else if (btn = InsertBtn) {
                    btn.Opt("Background0x00CC00 cWhite")
                } else if (btn = SaveBtn) {
                    btn.Opt("Background0x0070CC cWhite")
                } else if (btn = LoadBtn) {
                    btn.Opt("Background0x0070CC cWhite")
                } else if (btn = PlayOnceBtn) {
                    btn.Opt("Background0x0070CC cWhite")
                } else if (btn = ToggleRepeatBtn) {
                    btn.Opt("Background0xCC7700 cWhite")
                }
                if OriginalBtnText.Has(btn.Hwnd) {
                    btn.Text := OriginalBtnText[btn.Hwnd]
                }
            }
        } catch {
        }
    }

    for btn in BtnsAllowedOnRecord {
        try {
            if IsRecording {
                btn.Enable()
                if OriginalBtnText.Has(btn.Hwnd)
                    btn.Text := ">> " OriginalBtnText[btn.Hwnd] " <<"
                btn.Opt("cWhite")
            } else {
                if OriginalBtnText.Has(btn.Hwnd)
                    btn.Text := OriginalBtnText[btn.Hwnd]
            }
        } catch {
        }
    }
}

; ─────────────────────────────────────────────
; ─────────────────────────────────────────────
; Koordinaten auf Bildschirmgrenzen klemmen
; ─────────────────────────────────────────────
ClampX(v) {
    global ScreenXMin, ScreenXMax
    return Max(ScreenXMin, Min(ScreenXMax, Integer(v)))
}
ClampY(v) {
    global ScreenYMin, ScreenYMax
    return Max(ScreenYMin, Min(ScreenYMax, Integer(v)))
}

; Kurzdarstellung einer Aktion für die Status-Box
; ─────────────────────────────────────────────
FormatActionShort(a) {
    if !(IsObject(a) && a is Map && a.Has("Type"))
        return "--"
    type := a["Type"]
    if type = "Click" {
        btn := (a.Has("Button") && a["Button"] = "Right") ? "R" : "L"
        return btn "klick  X=" a["X"] " Y=" a["Y"]
    }
    if type = "LongClick" {
        btn := (a.Has("Button") && a["Button"] = "Right") ? "R" : "L"
        return "Langer " btn "klick  " a["Duration"] " ms"
    }
    if type = "Drag"
        return "Drag → X=" a["X2"] " Y=" a["Y2"]
    if type = "Delay"
        return "Verzögerung  " a["Time"] " ms"
    if type = "Scroll"
        return "Scroll " (a["Direction"] = "Up" ? "↑" : "↓") " ×" a["Amount"]
    if type = "KeyPress"
        return "Taste: " a["Key"]
    if type = "MouseMove"
        return "Maus → X=" a["X"] " Y=" a["Y"]
    if type = "Comment"
        return "Kommentar: " SubStr(a["Text"], 1, 24)
    if type = "TextInput"
        return "Text: " SubStr(a["Text"], 1, 24)
    return type
}

; ─────────────────────────────────────────────
UpdateActionsList(scrollTo := 0) {
    global GuiMain, ActionsList, LVRowColors, IsRecording
    LV := GuiMain["ActionList"]

    ; Aktuelle Scroll-Position merken (LVM_GETTOPINDEX = 0x1027)
    topIndex := SendMessage(0x1027, 0, 0, LV.Hwnd) + 1

    LV.Delete()
    LVRowColors := Map()

    if !(IsObject(ActionsList) && ActionsList.Length > 0)
        return

    maxIndex := ActionsList.Length
    digits   := StrLen(maxIndex)

    ; BGR-Farben für Windows COLORREF (0xBBGGRR)
    static clr := Map(
        "Click",     0xFFF0F0,
        "LongClick", 0xCCEEFF,
        "Drag",      0xFFEECC,
        "Delay",     0xCCCCFF,
        "Scroll",    0xCCFFCC,
        "KeyPress",  0xFFCCF5,
        "MouseMove", 0xFAFFCC,
        "Comment",   0xEEEEEE,
        "TextInput", 0xEECCFF
    )

    static sym := Map(
        "Click",     "●",
        "LongClick", "◆",
        "Drag",      "↔",
        "Delay",     "⏱",
        "Scroll",    "↕",
        "KeyPress",  "⌨",
        "MouseMove", "→",
        "Comment",   "✎",
        "TextInput", "T"
    )

    rowNum := 0
    for i, a in ActionsList {
        if !(IsObject(a) && a is Map && a.Has("Type"))
            continue

        rowNum++
        displayIndex := Format("{:0" digits "}", i)
        type := a["Type"]
        btn  := a.Has("Button") ? a["Button"] : "Left"
        bLbl := (btn = "Right") ? "Rechts" : "Links"
        s    := sym.Has(type) ? sym[type] " " : ""

        if type = "Click"
            LV.Add("", displayIndex, s bLbl "klick", "X=" a["X"] " Y=" a["Y"])
        else if type = "LongClick"
            LV.Add("", displayIndex, s "Langer Klick (" bLbl ")", "X=" a["X"] " Y=" a["Y"] "  " a["Duration"] " ms")
        else if type = "Delay"
            LV.Add("", displayIndex, s "Zeitverzögerung", a["Time"] " ms")
        else if type = "Drag"
            LV.Add("", displayIndex, s "Drag (" bLbl ")", "X1=" a["X1"] " Y1=" a["Y1"] " -> X2=" a["X2"] " Y2=" a["Y2"])
        else if type = "Scroll"
            LV.Add("", displayIndex, s "Scrollen", (a["Direction"]="Up" ? "Hoch" : "Runter") " x " a["Amount"])
        else if type = "KeyPress"
            LV.Add("", displayIndex, s "Taste", a["Key"])
        else if type = "MouseMove"
            LV.Add("", displayIndex, s "Mausbewegung", "X=" a["X"] " Y=" a["Y"])
        else if type = "Comment"
            LV.Add("", displayIndex, s "Kommentar", a["Text"])
        else if type = "TextInput"
            LV.Add("", displayIndex, s "Text eingeben", a["Text"])
        else
            LV.Add("", displayIndex, type, "")

        if clr.Has(type)
            LVRowColors[rowNum] := clr[type]
    }

    ; ListView neu zeichnen damit Farben sofort sichtbar sind
    DllCall("InvalidateRect", "Ptr", LV.Hwnd, "Ptr", 0, "Int", 1)

    rowCount := LV.GetCount()
    if rowCount = 0
        return

    if scrollTo >= 1 && scrollTo <= rowCount {
        ; Explizites Ziel (z.B. nach Einfügen): dorthin scrollen und selektieren
        LV.Modify(scrollTo, "Vis Select Focus")
    } else if IsRecording {
        ; Während Aufnahme: ans Ende scrollen
        LV.Modify(rowCount, "Vis Select Focus")
    } else {
        ; Scroll-Position beibehalten (LVM_ENSUREVISIBLE = 0x1013)
        restoreTo := Max(1, Min(topIndex, rowCount))
        SendMessage(0x1013, restoreTo - 1, 0, LV.Hwnd)
    }
}

; ─────────────────────────────────────────────
; NM_CUSTOMDRAW Handler für ListView Zeilenfarben
; Offsets für 64-Bit Windows:
;   NMHDR: hwndFrom(8)+idFrom(8)+code(4)+pad(4) = 24
;   dwDrawStage: offset 24
;   dwItemSpec:  offset 56
;   clrText:     offset 80
;   clrTextBk:   offset 84
; ─────────────────────────────────────────────
LVScrollToTop() {
    global GuiMain
    LV := GuiMain["ActionList"]
    if LV.GetCount() > 0
        LV.Modify(1, "Vis Select Focus")
}

LVScrollToBottom() {
    global GuiMain
    LV := GuiMain["ActionList"]
    n := LV.GetCount()
    if n > 0
        LV.Modify(n, "Vis Select Focus")
}

; ─────────────────────────────────────────────
SetupLVColors() {
    OnMessage(0x004E, LV_CustomDraw)
}

LV_CustomDraw(wParam, lParam, msg, hwnd) {
    global GuiMain, LVRowColors, LVDragging, LVDragRow, LVDragTargetRow

    static NM_CUSTOMDRAW        := -12
    static CDDS_PREPAINT        := 0x1
    static CDDS_ITEMPREPAINT    := 0x10001
    static CDRF_DODEFAULT       := 0x0
    static CDRF_NOTIFYITEMDRAW  := 0x20
    static CDRF_NEWFONT         := 0x2

    if !IsObject(GuiMain)
        return
    try LV := GuiMain["ActionList"]
    catch
        return
    if !IsObject(LV)
        return

    hwndFrom := NumGet(lParam, 0, "Ptr")
    if hwndFrom != LV.Hwnd
        return

    code := NumGet(lParam, 16, "Int")
    if code != NM_CUSTOMDRAW
        return

    dwDrawStage := NumGet(lParam, 24, "UInt")

    if dwDrawStage = CDDS_PREPAINT
        return CDRF_NOTIFYITEMDRAW

    if dwDrawStage = CDDS_ITEMPREPAINT {
        dwItemSpec := NumGet(lParam, 56, "Ptr")
        row := Integer(dwItemSpec) + 1

        ; Gezogene Zeile: orange mit weißem Text
        if LVDragging && row = LVDragRow {
            NumPut("UInt", 0xFFFFFF,   lParam, 80)  ; clrText  = weiß
            NumPut("UInt", 0x000082FF, lParam, 84)  ; clrTextBk = orange (RGB 255,130,0)
            return CDRF_NEWFONT
        }
        ; Zielzeile: hellgrün
        if LVDragging && LVDragTargetRow > 0 && row = LVDragTargetRow && LVDragTargetRow != LVDragRow {
            NumPut("UInt", 0x000000,   lParam, 80)  ; clrText  = schwarz
            NumPut("UInt", 0x00B4E6B4, lParam, 84)  ; clrTextBk = hellgrün (RGB 180,230,180)
            return CDRF_NEWFONT
        }

        if LVRowColors.Has(row) {
            NumPut("UInt", 0x000000,          lParam, 80)  ; clrText  = schwarz
            NumPut("UInt", LVRowColors[row],  lParam, 84)  ; clrTextBk = Hintergrund
            return CDRF_NEWFONT
        }
    }

    return CDRF_DODEFAULT
}

; ─────────────────────────────────────────────
; ListView Drag & Drop (Zeilen umsortieren)
; ─────────────────────────────────────────────
global LVDragRow       := 0
global LVDragTargetRow := 0
global LVDragging      := false

SetupLVDragDrop() {
    OnMessage(0x004E, LV_OnNotify_Drag)
}

LV_OnNotify_Drag(wParam, lParam, msg, hwnd) {
    global GuiMain, LVDragRow, LVDragging
    static LVN_BEGINDRAG := -109

    if !IsObject(GuiMain)
        return
    try LV := GuiMain["ActionList"]
    catch
        return
    if !IsObject(LV)
        return

    hwndFrom := NumGet(lParam, 0, "Ptr")
    if hwndFrom != LV.Hwnd
        return

    code := NumGet(lParam, 16, "Int")
    if code != LVN_BEGINDRAG
        return

    ; iItem aus NMLISTVIEW (Offset 24 auf 64-Bit)
    LVDragRow  := NumGet(lParam, 24, "Int") + 1  ; 0-basiert → 1-basiert
    LVDragging := true
    SetTimer(LVDragTimer, 16)
    return 0
}

LVDragTimer(*) {
    global GuiMain, ActionsList, LVDragRow, LVDragTargetRow, LVDragging

    if !LVDragging
        return

    LV := GuiMain["ActionList"]
    MouseGetPos(&mx, &my)

    ; Bildschirmkoordinaten in ListView-Clientkoordinaten umrechnen
    pt := Buffer(8)
    NumPut("Int", mx, pt, 0)
    NumPut("Int", my, pt, 4)
    DllCall("ScreenToClient", "Ptr", LV.Hwnd, "Ptr", pt)
    cx := NumGet(pt, 0, "Int")
    cy := NumGet(pt, 4, "Int")

    ; Zielzeile per HitTest ermitteln (LVM_HITTEST = 0x1012)
    LVHTI := Buffer(24, 0)
    NumPut("Int", cx, LVHTI, 0)
    NumPut("Int", cy, LVHTI, 4)
    result := SendMessage(0x1012, 0, LVHTI.Ptr, LV.Hwnd)

    if !GetKeyState("LButton", "P") {
        ; Maustaste losgelassen → Drop ausführen, Highlights zurücksetzen
        LVDragging      := false
        LVDragTargetRow := 0
        SetTimer(LVDragTimer, 0)
        ToolTip()
        DllCall("InvalidateRect", "Ptr", LV.Hwnd, "Ptr", 0, "Int", 1)

        if result < 0
            return
        targetRow := result + 1
        if targetRow = LVDragRow || targetRow < 1 || targetRow > ActionsList.Length
            return

        PushUndo()
        item := ActionsList.RemoveAt(LVDragRow)
        adj  := targetRow
        ActionsList.InsertAt(adj, item)
        UpdateActionsList()
        LV.Modify(adj, "Select Focus")
        return
    }

    ; Zielzeile aktualisieren und ListView neu zeichnen wenn sie sich geändert hat
    newTarget := (result >= 0) ? result + 1 : 0
    if newTarget != LVDragTargetRow {
        LVDragTargetRow := newTarget
        DllCall("InvalidateRect", "Ptr", LV.Hwnd, "Ptr", 0, "Int", 1)
    }

    ; Tooltip während des Ziehens anzeigen
    if result >= 0 {
        targetRow := result + 1
        ToolTip("Verschiebe Zeile " LVDragRow " → Position " targetRow, mx + 12, my + 12)
    }
}

; ─────────────────────────────────────────────
AddAction(*) {
    global ActionsList, GuiActionInsert

    GuiActionInsert := Gui("+ToolWindow +AlwaysOnTop", "+ Aktion hinzufügen")
    GuiActionInsert.SetFont("s9")

    ; Einfügeposition oben
    GuiActionInsert.AddText("x8 y8", "Einfügen an Position:")
    GuiActionInsert.AddEdit("x+6 yp-2 vInsertIndex w50", ActionsList.Length + 1)
    GuiActionInsert.AddText("x+4 yp+2 cGray", "(1 = ganz oben)")

    ; Tab-Control
    tabs := GuiActionInsert.AddTab3("x8 y+8 w360 h220 vActionTab",
        ["Mausklick", "Delay", "Drag", "Scrollen", "Langer Klick", "Kommentar", "Text"])
    GuiActionInsert.SetFont("s9")

    ; ── Tab 1: Mausklick ──
    tabs.UseTab(1)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Klickt einmal an einer Bildschirmposition.")
    GuiActionInsert.AddCheckBox("x20 y+8 vUseCurrentPos", "Aktuelle Mausposition verwenden")
        .OnEvent("Click", (*) => OnUseCurrentPosClick())
    GuiActionInsert.AddText("x20 y+8", "X-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vPosX w70")
    GuiActionInsert.AddText("x20 y+8", "Y-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vPosY w70")
    GuiActionInsert.AddText("x20 y+8", "Maustaste:")
    dd1 := GuiActionInsert.AddDropDownList("x+6 yp-2 vClickBtn w100", ["Links", "Rechts"])
    dd1.Value := 1

    ; ── Tab 2: Zeitverzögerung ──
    tabs.UseTab(2)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Das Skript wartet diese Zeit bevor die nächste Aktion ausgeführt wird.")
    GuiActionInsert.AddText("x20 y+20", "Wartezeit (ms):")
    GuiActionInsert.AddEdit("x+6 yp-2 vDelayValue w100", "500")
    GuiActionInsert.AddText("x+4 yp+2 cGray", "1000 ms = 1 Sek.")

    ; ── Tab 3: Drag & Drop ──
    tabs.UseTab(3)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Maustaste halten, Maus bewegen, loslassen.")
    GuiActionInsert.AddText("x20 y+18", "Maustaste:")
    dd3 := GuiActionInsert.AddDropDownList("x+6 yp-2 vDragBtn w100", ["Links", "Rechts"])
    dd3.Value := 1
    GuiActionInsert.AddText("x20 y+8", "Start X1:")
    GuiActionInsert.AddEdit("x+6 yp-2 vDragX1 w70")
    GuiActionInsert.AddText("x+8 yp+2", "Y1:")
    GuiActionInsert.AddEdit("x+4 yp-2 vDragY1 w70")
    GuiActionInsert.AddText("x20 y+8", "Ziel  X2:")
    GuiActionInsert.AddEdit("x+6 yp-2 vDragX2 w70")
    GuiActionInsert.AddText("x+8 yp+2", "Y2:")
    GuiActionInsert.AddEdit("x+4 yp-2 vDragY2 w70")

    ; ── Tab 4: Scrollen ──
    tabs.UseTab(4)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Dreht das Mausrad an der aktuellen Position.")
    GuiActionInsert.AddText("x20 y+20", "Richtung:")
    dd4 := GuiActionInsert.AddDropDownList("x+6 yp-2 vScrollDir w100", ["Hoch", "Runter"])
    dd4.Value := 1
    GuiActionInsert.AddText("x20 y+8", "Anzahl Schritte:")
    GuiActionInsert.AddEdit("x+6 yp-2 vScrollAmount w60", "3")

    ; ── Tab 5: Langer Klick ──
    tabs.UseTab(5)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Maustaste halten ohne Bewegung.")
    GuiActionInsert.AddText("x20 y+18", "X-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vLongX w70")
    GuiActionInsert.AddText("x20 y+8", "Y-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vLongY w70")
    GuiActionInsert.AddText("x20 y+8", "Haltedauer (ms):")
    GuiActionInsert.AddEdit("x+6 yp-2 vLongDur w80", "1000")
    GuiActionInsert.AddText("x20 y+8", "Maustaste:")
    dd5 := GuiActionInsert.AddDropDownList("x+6 yp-2 vLongBtn w100", ["Links", "Rechts"])
    dd5.Value := 1

    ; ── Tab 6: Kommentar ──
    tabs.UseTab(6)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Nur zur Beschriftung — wird bei Wiedergabe übersprungen.")
    GuiActionInsert.AddText("x20 y+20", "Kommentartext:")
    GuiActionInsert.AddEdit("x+6 yp-2 vCommentText w210")

    ; ── Tab 7: Text eingeben ──
    tabs.UseTab(7)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Sendet Text an das aktive Fenster (z.B. für Textfelder).")
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Sonderzeichen werden korrekt übertragen.")
    GuiActionInsert.AddText("x20 y+16", "Einzugebender Text:")
    GuiActionInsert.AddEdit("x20 y+4 vTextInput w320 h60 Multi")

    tabs.UseTab()  ; zurück zu keinem Tab

    ; Explizite Y-Position nach dem Tab-Control berechnen
    tabs.GetPos(, &tabY, , &tabH)
    btnY := tabY + tabH + 8

    ; OK / Abbrechen
    GuiActionInsert.AddButton("x8 y" btnY " w80 Default", "OK")
        .OnEvent("Click", (*) => InsertConfirm(GuiActionInsert))
    GuiActionInsert.AddButton("x+6 yp w80", "Abbrechen")
        .OnEvent("Click", (*) => GuiActionInsert.Destroy())

    GuiActionInsert.Show()
}

; ─────────────────────────────────────────────
; Timer: Mausposition im Insert-Dialog live aktualisieren
; ─────────────────────────────────────────────
OnUseCurrentPosClick(*) {
    global GuiActionInsert
    if !IsObject(GuiActionInsert)
        return
    if GuiActionInsert["UseCurrentPos"].Value {
        SetTimer(UpdateInsertMousePos, 50)
    } else {
        SetTimer(UpdateInsertMousePos, 0)
        ToolTip("")
    }
}
UpdateInsertMousePos(*) {
    global GuiActionInsert
    if !IsObject(GuiActionInsert)
        return
    if !GuiActionInsert["UseCurrentPos"].Value {
        SetTimer(UpdateInsertMousePos, 0)
        ToolTip()
        return
    }
    MouseGetPos &x, &y
    GuiActionInsert["PosX"].Value := x
    GuiActionInsert["PosY"].Value := y
    ToolTip("X=" x "  Y=" y "  — Klick zum Uebernehmen", x + 20, y + 20)

    ; Klick ausserhalb der Checkbox friert Position ein
    ctrl := GuiActionInsert["UseCurrentPos"]
    ctrl.GetPos(&cx, &cy, &cw, &ch)
    if GetKeyState("LButton", "P") || GetKeyState("RButton", "P") {
        if !(x >= cx && x <= cx + cw && y >= cy && y <= cy + ch) {
            GuiActionInsert["UseCurrentPos"].Value := false
            SetTimer(UpdateInsertMousePos, 0)
            ToolTip()
        }
    }
}

; ─────────────────────────────────────────────
DelAction(*) {
    global GuiMain, ActionsList
    LV := GuiMain["ActionList"]

    indices := []
    row := 0
    Loop {
        row := LV.GetNext(row)
        if !row
            break
        indices.Push(row)
    }

    if indices.Length = 0 {
        count := ActionsList.Length
        if count > 0 {
            result := ShowYesNo("Es sind " count " Aktionen vorhanden.`n`nAlle löschen?")
            if result != "Yes"
                return
        }
        ActionsList := []
        LV.Delete()
        return
    }

    i := indices.Length
    while i >= 1 {
        ActionsList.RemoveAt(indices[i])
        i--
    }
    PushUndo()
    UpdateActionsList()
}

; ─────────────────────────────────────────────
EditAction(LV, rowIndex) {
    global ActionsList, GuiActionEdit

    if rowIndex = 0 || rowIndex > ActionsList.Length
        return

    a    := ActionsList[rowIndex]
    if !(IsObject(a) && a is Map && a.Has("Type"))
        return

    type := a["Type"]
    btn  := a.Has("Button") ? a["Button"] : "Left"

    GuiActionEdit := Gui("+ToolWindow +AlwaysOnTop", "Aktion bearbeiten")
    GuiActionEdit.SetFont("s9")

    ; Titel und Beschreibung je Typ
    if type = "Click" {
        GuiActionEdit.AddText("w260 cBlue", "Mausklick")
        GuiActionEdit.AddText("w260 y+2 cGray", "Ein einzelner Klick an einer bestimmten Bildschirmposition.")
        GuiActionEdit.AddText("y+8", "Maustaste:")
        dd := GuiActionEdit.AddDropDownList("vEditBtn w120", ["Links", "Rechts"])
        dd.Value := (btn = "Right") ? 2 : 1
        GuiActionEdit.AddText("y+2 w260 cGray", "Welche Maustaste gedrückt wird.")
        GuiActionEdit.AddText("y+8", "X-Koordinate:")
        GuiActionEdit.AddEdit("vEditX w80", a["X"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Horizontale Position in Pixeln (0 = linker Bildschirmrand).")
        GuiActionEdit.AddText("y+8", "Y-Koordinate:")
        GuiActionEdit.AddEdit("vEditY w80", a["Y"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Vertikale Position in Pixeln (0 = oberer Bildschirmrand).")

    } else if type = "LongClick" {
        GuiActionEdit.AddText("w260 cBlue", "Langer Klick")
        GuiActionEdit.AddText("w260 y+2 cGray", "Maustaste wird gedrückt gehalten und dann losgelassen.")
        GuiActionEdit.AddText("y+8", "Maustaste:")
        dd := GuiActionEdit.AddDropDownList("vEditBtn w120", ["Links", "Rechts"])
        dd.Value := (btn = "Right") ? 2 : 1
        GuiActionEdit.AddText("y+2 w260 cGray", "Welche Maustaste gehalten wird.")
        GuiActionEdit.AddText("y+8", "X-Koordinate:")
        GuiActionEdit.AddEdit("vEditX w80", a["X"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Horizontale Position in Pixeln.")
        GuiActionEdit.AddText("y+8", "Y-Koordinate:")
        GuiActionEdit.AddEdit("vEditY w80", a["Y"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Vertikale Position in Pixeln.")
        GuiActionEdit.AddText("y+8", "Haltedauer (ms):")
        GuiActionEdit.AddEdit("vEditDuration w80", a["Duration"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Wie lange die Taste gehalten wird. 1000 ms = 1 Sekunde.")

    } else if type = "Delay" {
        GuiActionEdit.AddText("w260 cBlue", "Zeitverzögerung")
        GuiActionEdit.AddText("w260 y+2 cGray", "Das Skript wartet diese Zeit bevor die nächste Aktion ausgeführt wird.")
        GuiActionEdit.AddText("y+8", "Wartezeit (ms):")
        GuiActionEdit.AddEdit("vEditTime w80", a["Time"])
        GuiActionEdit.AddText("y+2 w260 cGray", "1000 ms = 1 Sekunde.  Typische Werte: 200-500 ms.")

    } else if type = "Drag" {
        GuiActionEdit.AddText("w260 cBlue", "Drag & Drop")
        GuiActionEdit.AddText("w260 y+2 cGray", "Maustaste an Startposition halten, zur Zielposition ziehen, loslassen.")
        GuiActionEdit.AddText("y+8", "Maustaste:")
        dd := GuiActionEdit.AddDropDownList("vEditBtn w120", ["Links", "Rechts"])
        dd.Value := (btn = "Right") ? 2 : 1
        GuiActionEdit.AddText("y+2 w260 cGray", "Welche Maustaste für den Drag verwendet wird.")
        GuiActionEdit.AddText("y+8", "Startposition X1:")
        GuiActionEdit.AddEdit("vEditX1 w80", a["X1"])
        GuiActionEdit.AddText("y+8", "Startposition Y1:")
        GuiActionEdit.AddEdit("vEditY1 w80", a["Y1"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Wo der Drag beginnt (Maustaste wird hier gedrückt).")
        GuiActionEdit.AddText("y+8", "Zielposition X2:")
        GuiActionEdit.AddEdit("vEditX2 w80", a["X2"])
        GuiActionEdit.AddText("y+8", "Zielposition Y2:")
        GuiActionEdit.AddEdit("vEditY2 w80", a["Y2"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Wo der Drag endet (Maustaste wird hier losgelassen).")

    } else if type = "Scroll" {
        GuiActionEdit.AddText("w260 cBlue", "Scrollen")
        GuiActionEdit.AddText("w260 y+2 cGray", "Dreht das Mausrad an der aktuellen Mausposition.")
        GuiActionEdit.AddText("y+8", "Richtung:")
        dd := GuiActionEdit.AddDropDownList("vEditScrollDir w120", ["Hoch", "Runter"])
        dd.Value := (a["Direction"] = "Up") ? 1 : 2
        GuiActionEdit.AddText("y+2 w260 cGray", "Hoch = Seite nach oben scrollen, Runter = nach unten.")
        GuiActionEdit.AddText("y+8", "Anzahl Schritte:")
        GuiActionEdit.AddEdit("vEditScrollAmount w80", a["Amount"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Wie viele Mausrad-Klicks ausgeführt werden (1-20 typisch).")

    } else if type = "KeyPress" {
        GuiActionEdit.AddText("w260 cBlue", "Tastendruck")
        GuiActionEdit.AddText("w260 y+2 cGray", "Sendet einen Tastendruck an die aktive Anwendung.")
        GuiActionEdit.AddText("y+8", "Taste (AHK-Format):")
        GuiActionEdit.AddEdit("vEditKey w160", a["Key"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Beispiele:  {Enter}  {Tab}  {F5}  ^c (Strg+C)  !{F4} (Alt+F4)")

    } else if type = "MouseMove" {
        GuiActionEdit.AddText("w260 cBlue", "Mausbewegung")
        GuiActionEdit.AddText("w260 y+2 cGray", "Bewegt den Mauszeiger ohne zu klicken.")
        GuiActionEdit.AddText("y+8", "X-Koordinate:")
        GuiActionEdit.AddEdit("vEditX w80", a["X"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Horizontale Zielposition in Pixeln.")
        GuiActionEdit.AddText("y+8", "Y-Koordinate:")
        GuiActionEdit.AddEdit("vEditY w80", a["Y"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Vertikale Zielposition in Pixeln.")

    } else if type = "Comment" {
        GuiActionEdit.AddText("w260 cBlue", "Kommentar")
        GuiActionEdit.AddText("w260 y+2 cGray", "Nur zur Beschriftung - wird bei Wiedergabe übersprungen.")
        GuiActionEdit.AddText("y+8", "Kommentartext:")
        GuiActionEdit.AddEdit("vEditCommentText w220", a["Text"])

    } else if type = "TextInput" {
        GuiActionEdit.AddText("w260 cBlue", "Text eingeben")
        GuiActionEdit.AddText("w260 y+2 cGray", "Sendet Text an das aktive Fenster (Textfelder ausfüllen).")
        GuiActionEdit.AddText("y+8", "Einzugebender Text:")
        GuiActionEdit.AddEdit("vEditTextInput w260 h80 Multi", a["Text"])

    } else {
        GuiActionEdit.AddText(, "Dieser Typ ist nicht editierbar.")
        GuiActionEdit.AddButton("w80", "Schliessen").OnEvent("Click", (*) => GuiActionEdit.Destroy())
        GuiActionEdit.Show()
        return
    }

    GuiActionEdit.AddText("y+10", "")
    GuiActionEdit.AddButton("w80 Default", "OK").OnEvent("Click",
        (*) => EditConfirm(GuiActionEdit, rowIndex, type))
    GuiActionEdit.AddButton("w80", "Abbrechen").OnEvent("Click",
        (*) => GuiActionEdit.Destroy())
    GuiActionEdit.Show()
}

EditConfirm(GuiObj, rowIndex, type) {
    global ActionsList, GuiActionEdit

    a := ActionsList[rowIndex]

    if type = "Click" {
        x := GuiObj["EditX"].Value
        y := GuiObj["EditY"].Value
        if !(IsNumber(x) && IsNumber(y)) {
            ShowWarning("Ungültige Koordinaten!")
            return
        }
        a["X"] := ClampX(x), a["Y"] := ClampY(y)
        a["Button"] := (GuiObj["EditBtn"].Text = "Rechts") ? "Right" : "Left"

    } else if type = "LongClick" {
        x   := GuiObj["EditX"].Value
        y   := GuiObj["EditY"].Value
        dur := GuiObj["EditDuration"].Value
        if !(IsNumber(x) && IsNumber(y) && IsNumber(dur) && dur > 0) {
            ShowWarning("Ungültige Werte!")
            return
        }
        a["X"] := ClampX(x), a["Y"] := ClampY(y), a["Duration"] := Integer(dur)
        a["Button"] := (GuiObj["EditBtn"].Text = "Rechts") ? "Right" : "Left"

    } else if type = "Delay" {
        t := GuiObj["EditTime"].Value
        if !(IsNumber(t) && t > 0) {
            ShowWarning("Ungültige Zeit!")
            return
        }
        a["Time"] := Integer(t)

    } else if type = "Drag" {
        x1 := GuiObj["EditX1"].Value, y1 := GuiObj["EditY1"].Value
        x2 := GuiObj["EditX2"].Value, y2 := GuiObj["EditY2"].Value
        if !(IsNumber(x1) && IsNumber(y1) && IsNumber(x2) && IsNumber(y2)) {
            ShowWarning("Ungültige Koordinaten!")
            return
        }
        a["X1"] := ClampX(x1), a["Y1"] := ClampY(y1)
        a["X2"] := ClampX(x2), a["Y2"] := ClampY(y2)
        a["Button"] := (GuiObj["EditBtn"].Text = "Rechts") ? "Right" : "Left"

    } else if type = "Scroll" {
        dir    := GuiObj["EditScrollDir"].Text
        amount := GuiObj["EditScrollAmount"].Value
        if !(IsNumber(amount) && amount >= 1) {
            ShowWarning("Ungültige Schrittanzahl!")
            return
        }
        a["Direction"] := (dir = "Hoch") ? "Up" : "Down"
        a["Amount"]    := Integer(amount)

    } else if type = "KeyPress" {
        key := Trim(GuiObj["EditKey"].Value)
        if key = "" {
            ShowWarning("Bitte eine Taste eingeben!")
            return
        }
        a["Key"] := key

    } else if type = "MouseMove" {
        x := GuiObj["EditX"].Value
        y := GuiObj["EditY"].Value
        if !(IsNumber(x) && IsNumber(y)) {
            ShowWarning("Ungültige Koordinaten!")
            return
        }
        a["X"] := ClampX(x)
        a["Y"] := ClampY(y)

    } else if type = "Comment" {
        txt := Trim(GuiObj["EditCommentText"].Value)
        if txt = "" {
            ShowWarning("Bitte einen Kommentartext eingeben!")
            return
        }
        a["Text"] := txt

    } else if type = "TextInput" {
        txt := GuiObj["EditTextInput"].Value
        if txt = "" {
            ShowWarning("Bitte einen Text eingeben!")
            return
        }
        a["Text"] := txt
    }

    ActionsList[rowIndex] := a
    GuiActionEdit.Destroy()
    PushUndo()
    UpdateActionsList()
}

; ─────────────────────────────────────────────
InsertConfirm(GuiActionInsert) {
    global ActionsList, LastActionTime

    tabIndex    := GuiActionInsert["ActionTab"].Value
    insertIndex := Integer(GuiActionInsert["InsertIndex"].Value)
    if (insertIndex < 1 || insertIndex > ActionsList.Length + 1)
        insertIndex := ActionsList.Length + 1

    if tabIndex = 1 {   ; Mausklick
        if GuiActionInsert["UseCurrentPos"].Value {
            MouseGetPos &x, &y
        } else {
            x := GuiActionInsert["PosX"].Value
            y := GuiActionInsert["PosY"].Value
            if !(IsNumber(x) && IsNumber(y)) {
                ShowWarning("Ungültige Koordinaten!")
                return
            }
        }
        btn := (GuiActionInsert["ClickBtn"].Text = "Rechts") ? "Right" : "Left"
        ActionsList.InsertAt(insertIndex, Map("Type","Click","Button",btn,"X",ClampX(x),"Y",ClampY(y)))

    } else if tabIndex = 2 {   ; Delay
        delay := GuiActionInsert["DelayValue"].Value
        if !(IsNumber(delay) && delay > 0) {
            ShowWarning("Ungültige Zeit!")
            return
        }
        ActionsList.InsertAt(insertIndex, Map("Type","Delay","Time",Integer(delay)))

    } else if tabIndex = 3 {   ; Drag
        x1 := GuiActionInsert["DragX1"].Value
        y1 := GuiActionInsert["DragY1"].Value
        x2 := GuiActionInsert["DragX2"].Value
        y2 := GuiActionInsert["DragY2"].Value
        if !(IsNumber(x1) && IsNumber(y1) && IsNumber(x2) && IsNumber(y2)) {
            ShowWarning("Ungültige Koordinaten!")
            return
        }
        btn := (GuiActionInsert["DragBtn"].Text = "Rechts") ? "Right" : "Left"
        ActionsList.InsertAt(insertIndex, Map("Type","Drag","Button",btn,
            "X1",ClampX(x1),"Y1",ClampY(y1),"X2",ClampX(x2),"Y2",ClampY(y2)))

    } else if tabIndex = 4 {   ; Scroll
        dir    := GuiActionInsert["ScrollDir"].Text
        amount := GuiActionInsert["ScrollAmount"].Value
        if !(IsNumber(amount) && amount >= 1) {
            ShowWarning("Ungültige Schritte!")
            return
        }
        ActionsList.InsertAt(insertIndex, Map("Type","Scroll",
            "Direction",(dir="Hoch")?"Up":"Down","Amount",Integer(amount)))

    } else if tabIndex = 5 {   ; Langer Klick
        x   := GuiActionInsert["LongX"].Value
        y   := GuiActionInsert["LongY"].Value
        dur := GuiActionInsert["LongDur"].Value
        if !(IsNumber(x) && IsNumber(y) && IsNumber(dur) && dur > 0) {
            ShowWarning("Ungültige Werte!")
            return
        }
        btn := (GuiActionInsert["LongBtn"].Text = "Rechts") ? "Right" : "Left"
        ActionsList.InsertAt(insertIndex, Map("Type","LongClick","Button",btn,
            "X",ClampX(x),"Y",ClampY(y),"Duration",Integer(dur)))

    } else if tabIndex = 6 {   ; Kommentar
        txt := Trim(GuiActionInsert["CommentText"].Value)
        if txt = "" {
            ShowWarning("Bitte Kommentartext eingeben!")
            return
        }
        ActionsList.InsertAt(insertIndex, Map("Type","Comment","Text",txt))

    } else if tabIndex = 7 {   ; Text eingeben
        txt := GuiActionInsert["TextInput"].Value
        if txt = "" {
            ShowWarning("Bitte Text eingeben!")
            return
        }
        ActionsList.InsertAt(insertIndex, Map("Type","TextInput","Text",txt))
    }

    GuiActionInsert.Destroy()
    PushUndo()
    LastActionTime := A_TickCount
    UpdateActionsList(insertIndex)
}

; ─────────────────────────────────────────────
; ─────────────────────────────────────────────
SelectAllInListView() {
    global GuiMain
    LV := GuiMain["ActionList"]
    if !IsObject(LV)
        return
    count := LV.GetCount()
    if count <= 0
        return
    Loop count
        LV.Modify(A_Index, "Select")
    LV.Modify(count, "Vis")
}

IsListViewFocused() {
    global GuiMain
    if !IsObject(GuiMain)
        return false
    if !WinActive("ahk_id " GuiMain.Hwnd)
        return false
    focusedHwnd := DllCall("GetFocus", "Ptr")
    lv := GuiMain["ActionList"]
    if !IsObject(lv)
        return false
    return (focusedHwnd = lv.Hwnd)
}

RemoveAction(array, index) {
    if (index > 0 && index <= array.Length)
        array.RemoveAt(index)
    return array
}

; ─────────────────────────────────────────────
ShowInfo(Text, Title := "Info") {
    MsgBox(Text, Title, 0x40 | 0x40000)
}
ShowWarning(Text, Title := "Warnung") {
    MsgBox(Text, Title, 0x30 | 0x40000)
}
ShowError(Text, Title := "Fehler") {
    MsgBox(Text, Title, 0x10 | 0x40000)
}
ShowYesNo(Text, Title := "Frage") {
    result := MsgBox(Text, Title, 0x34 | 0x40000)
    return (result = "Yes") ? "Yes" : "No"
}
ShowDebug(Text, Title := "Debug") {
    MsgBox(Text, Title, 0x40 | 0x40000)
}

; ─────────────────────────────────────────────
; Aktuell geladene Datei im Hauptfenster anzeigen
; ─────────────────────────────────────────────
SetCurrentFile(filePath) {
    global GuiMain
    if !IsObject(GuiMain)
        return
    if filePath = "" {
        GuiMain["CurrentFile"].Value := "Geladene Aktionen: (keine)"
    } else {
        name := RegExReplace(filePath, ".*\\", "")
        GuiMain["CurrentFile"].Value := "Geladene Aktionen: " name
    }
}

; ─────────────────────────────────────────────
; ─────────────────────────────────────────────
; Zeit-Manager: Verzögerungen setzen, randomisieren, löschen
; ─────────────────────────────────────────────
SetAllDelays(*) {
    global ActionsList

    if ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen in der Liste.")
        return
    }

    delayCount := 0
    for a in ActionsList
        if a["Type"] = "Delay"
            delayCount++

    if delayCount = 0 {
        ShowWarning("Keine Zeitverzögerungen in der Liste vorhanden.")
        return
    }

    GuiDelay := Gui("+ToolWindow +AlwaysOnTop", "Zeit-Manager")
    GuiDelay.SetFont("s10")
    GuiDelay.AddText("w280 cBlue", "Gefundene Verzögerungen: " delayCount)

    ; ── Neuer Wert ──
    GuiDelay.AddGroupBox("x8 y+8 w280 h54 Section", "Neuer Wert")
    GuiDelay.SetFont("s9")
    GuiDelay.AddText("xs+8 ys+20", "Wert (ms):")
    GuiDelay.AddEdit("xs+72 ys+18 vDelayMs w80", "200")
    GuiDelay.AddText("x+4 yp+2", "ms")
    GuiDelay.AddText("x+12 yp", "(0 = Delays löschen)")

    ; ── Randomizer ──
    GuiDelay.SetFont("s10")
    GuiDelay.AddGroupBox("x8 y+8 w280 h72 Section", "Zufalls-Variation")
    GuiDelay.SetFont("s9")
    GuiDelay.AddText("xs+8 ys+20 w264 cGray",
        "Addiert oder subtrahiert einen zufälligen Betrag`n"
        "bis zum angegebenen Maximum auf jeden Delay-Wert.")
    GuiDelay.AddText("xs+8 ys+50", "Max. Variation (± ms):")
    GuiDelay.AddEdit("xs+148 ys+48 vDelayRandom w60", "0")
    GuiDelay.AddText("x+4 yp+2", "ms")

    ; ── Buttons ──
    GuiDelay.SetFont("s9")
    GuiDelay.AddButton("x8 y+12 w88 h26 Default", "✔ Anwenden")
        .OnEvent("Click", (*) => ApplyAllDelays(GuiDelay, delayCount))
    GuiDelay.AddButton("x+6 yp w110 h26 Background0xCC0000 cWhite", "✖ Alle löschen")
        .OnEvent("Click", (*) => DeleteAllDelays(GuiDelay, delayCount))
    GuiDelay.AddButton("x+6 yp w60 h26", "Abbrechen")
        .OnEvent("Click", (*) => GuiDelay.Destroy())

    GuiDelay.Show()
}

ApplyAllDelays(GuiDelay, delayCount) {
    global ActionsList

    valMs  := GuiDelay["DelayMs"].Value
    valRnd := GuiDelay["DelayRandom"].Value

    if !IsNumber(valMs) || Float(valMs) < 0 {
        ShowWarning("Bitte einen gültigen Wert (≥ 0) eingeben.")
        return
    }

    newTime   := Integer(valMs)
    variation := (IsNumber(valRnd) && Integer(valRnd) > 0) ? Integer(valRnd) : 0

    ; Sonderfall: 0 ms → Delays löschen?
    if newTime = 0 {
        result := ShowYesNo(
            "Neuer Wert ist 0 ms.`n`n"
            "Sollen alle " delayCount " Verzögerungen aus der Liste entfernt werden?",
            "Delays löschen?")
        if result != "Yes"
            return
        _RemoveAllDelays()
        GuiDelay.Destroy()
        return
    }

    PushUndo()
    changed := 0
    i := 1
    while i <= ActionsList.Length {
        if ActionsList[i]["Type"] = "Delay" {
            if variation > 0 {
                ; Negativen Anteil auf newTime-1 begrenzen → Minimum immer 1ms, kein Pileup
                maxSub := Min(variation, newTime - 1)
                ActionsList[i]["Time"] := newTime + Random(-maxSub, variation)
            } else
                ActionsList[i]["Time"] := newTime
            changed++
        }
        i++
    }

    GuiDelay.Destroy()
    UpdateActionsList()
    rndInfo := variation > 0 ? " (± " variation " ms Zufall)" : ""
    ShowInfo(changed " Verzögerung(en) auf " newTime " ms gesetzt" rndInfo ".")
}

DeleteAllDelays(GuiDelay, delayCount) {
    result := ShowYesNo(
        "Alle " delayCount " Verzögerungen aus der Liste entfernen?`n`n"
        "Dieser Schritt kann rückgängig gemacht werden.",
        "Delays löschen?")
    if result != "Yes"
        return
    GuiDelay.Destroy()
    _RemoveAllDelays()
}

_RemoveAllDelays() {
    global ActionsList
    PushUndo()
    i := ActionsList.Length
    while i >= 1 {
        if ActionsList[i]["Type"] = "Delay"
            ActionsList.RemoveAt(i)
        i--
    }
    UpdateActionsList()
    ShowInfo("Alle Verzögerungen wurden entfernt.")
}

; ─────────────────────────────────────────────
; UNDO / REDO
; ─────────────────────────────────────────────
global UndoStack := []
global RedoStack := []
global _UndoMaxDepth := 30

; Aktuellen Stand auf Undo-Stack sichern (vor jeder Listenänderung aufrufen)
PushUndo() {
    global ActionsList, UndoStack, RedoStack, _UndoMaxDepth
    ; Tiefe Kopie der Liste
    snapshot := []
    for a in ActionsList {
        copy := Map()
        for k, v in a
            copy[k] := v
        snapshot.Push(copy)
    }
    UndoStack.Push(snapshot)
    if UndoStack.Length > _UndoMaxDepth
        UndoStack.RemoveAt(1)
    ; Redo-Stack leeren wenn neue Aktion kommt
    RedoStack := []
    UpdateUndoMenuState()
}

MenuUndo(*) {
    global ActionsList, UndoStack, RedoStack
    if UndoStack.Length = 0
        return
    ; Aktuellen Stand auf Redo sichern
    snapshot := []
    for a in ActionsList {
        copy := Map()
        for k, v in a
            copy[k] := v
        snapshot.Push(copy)
    }
    RedoStack.Push(snapshot)
    ActionsList := UndoStack.Pop()
    UpdateActionsList()
    UpdateUndoMenuState()
}

MenuRedo(*) {
    global ActionsList, UndoStack, RedoStack
    if RedoStack.Length = 0
        return
    snapshot := []
    for a in ActionsList {
        copy := Map()
        for k, v in a
            copy[k] := v
        snapshot.Push(copy)
    }
    UndoStack.Push(snapshot)
    ActionsList := RedoStack.Pop()
    UpdateActionsList()
    UpdateUndoMenuState()
}

UpdateUndoMenuState() {
    global MenuEditRef, UndoStack, RedoStack
    if !IsObject(MenuEditRef)
        return
    if UndoStack.Length > 0 {
        MenuEditRef.Enable("Rückgängig`tStrg+Z")
    } else {
        MenuEditRef.Disable("Rückgängig`tStrg+Z")
    }
    if RedoStack.Length > 0 {
        MenuEditRef.Enable("Wiederholen`tStrg+Y")
    } else {
        MenuEditRef.Disable("Wiederholen`tStrg+Y")
    }
}

; ─────────────────────────────────────────────
; ZULETZT GEÖFFNET
; ─────────────────────────────────────────────
global _RecentFiles := []
global _RecentMax   := 5
global _RecentIni   := A_ScriptDir "\AHK_Recorder_settings.ini"
global MenuRecentRef := ""

LoadRecentFiles() {
    global _RecentFiles, _RecentIni, _RecentMax
    _RecentFiles := []
    i := 1
    while i <= _RecentMax {
        try {
            f := IniRead(_RecentIni, "RecentFiles", "File" i, "")
            if f != "" && FileExist(f)
                _RecentFiles.Push(f)
        } catch {
        }
        i++
    }
}

SaveRecentFiles() {
    global _RecentFiles, _RecentIni
    try {
        IniDelete(_RecentIni, "RecentFiles")
        i := 1
        for f in _RecentFiles {
            IniWrite(f, _RecentIni, "RecentFiles", "File" i)
            i++
        }
    } catch {
    }
}

AddToRecentFiles(filePath) {
    global _RecentFiles, _RecentMax, MenuFileRef, MenuRecentRef
    ; Duplikat entfernen
    i := _RecentFiles.Length
    while i >= 1 {
        if _RecentFiles[i] = filePath
            _RecentFiles.RemoveAt(i)
        i--
    }
    _RecentFiles.InsertAt(1, filePath)
    if _RecentFiles.Length > _RecentMax
        _RecentFiles.RemoveAt(_RecentFiles.Length)
    SaveRecentFiles()
    RebuildRecentMenu()
}

RebuildRecentMenu() {
    global MenuFileRef, MenuRecentRef, _RecentFiles
    if !IsObject(MenuFileRef)
        return

    ; Altes Submenu neu aufbauen
    MenuRecentRef := Menu()
    if _RecentFiles.Length = 0 {
        MenuRecentRef.Add("(keine)", (*) => 0)
        MenuRecentRef.Disable("(keine)")
    } else {
        for f in _RecentFiles {
            name := RegExReplace(f, ".*\\", "")
            capturedF := f   ; Closure-Variable
            MenuRecentRef.Add(name, ((path, *) => OpenRecentFile(path)).Bind(capturedF))
        }
    }

    try MenuFileRef.Delete("Zuletzt geöffnet")
    MenuFileRef.Insert("2&", "Zuletzt geöffnet", MenuRecentRef)
}

OpenRecentFile(filePath, *) {
    global ActionsList
    if !FileExist(filePath) {
        ShowWarning("Datei nicht mehr vorhanden:`n" filePath)
        return
    }
    try {
        json        := FileRead(filePath, "UTF-8")
        ActionsList := Jxon_Load(&json)
        if !(ActionsList is Array) {
            ShowWarning("Keine gültige Aktionsliste!")
            return
        }
        UpdateActionsList()
        SetCurrentFile(filePath)
        AddToRecentFiles(filePath)
    } catch as err {
        ShowError("Fehler beim Laden:`n" err.Message)
    }
}
