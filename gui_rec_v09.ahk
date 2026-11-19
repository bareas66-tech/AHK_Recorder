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
global ActionKeyHook := ""
global ActionKeyDialog := ""
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

; Kopier-Zwischenablage für Aktionen (Rechtsklick Kopieren/Einfügen)
global LVCopiedItems    := []


; Fadenkreuz-Marker für "Position anzeigen"
global _MarkerGuis    := []
global _MarkerBlinks  := 0

; Farben pro Aktionstyp (COLORREF 0x00BBGGRR), geladen aus settings.ini
global ActionTypeColors   := Map()

; Zwischenspeicher für per-Kommentar-Farben im Insert- und Edit-Dialog
global _InsertCommentBg   := -1   ; -1 = Standard (globale Farbe)
global _InsertCommentFg   := -1
global _EditCommentBg     := -1
global _EditCommentFg     := -1

global CurrentFilePath := ""
global OptimizeClicks  := false

global CompactMode          := false
global CompactBtn           := ""
global GuiCompact           := ""
global CmpStartRecordingBtn := ""
global CmpStopRecordingBtn  := ""
global CmpPlayOnceBtn       := ""
global CmpToggleRepeatBtn   := ""
global CmpAbortBtn          := ""
global CmpExitBtn           := ""
global _OrigBtnRefs         := Map()   ; Sicherungskopie der GuiMain-Button-Referenzen

; ── Aktionslisten-Tabs (Hauptfenster) ──
global MainAllTabs     := [[], [], []]          ; Array von ActionsLists, eine pro Tab
global MainTabNames    := ["Tab 1", "Tab 2", "Tab 3"]  ; Tab-Namen
global MainCurrentTab  := 1                     ; Aktiver Tab (1-basiert)
global MainTabLVNames  := []                    ; Tab-Index → ListView-vName
global MainLVCounter   := 0                     ; Eindeutiger LV-Name-Zähler
global MainTabCtrl     := ""                    ; Tab3-Control im Hauptfenster
global MainTabChanging := false                 ; Guard gegen Endlosschleife
global MainCurrentLV   := ""                    ; Aktuell sichtbare ListView
global MainLVHwnds     := []                    ; Hwnds aller Haupt-LVs (für OnMessage-Filter)
global MainAllTabPaths := ["", "", ""]          ; CurrentFilePath pro Tab
global MainTabTooltips := ["", "", ""]          ; Voller Tab-Name für Hover-Tooltip
global _MainLastTooltipTab := 0                 ; Zuletzt angezeigter Tooltip-Tab (Throttle)

; ─────────────────────────────────────────────
RecorderNumericSettings(save := false, path := A_ScriptDir "\settings.ini") {
    global GuiMain
    if !IsObject(GuiMain)
        return
    settings := Map("MoveThreshEdit", [8, 1], "LongClickThresholdEdit", [500, 50],
        "CountdownSec", [0, 0], "RepeatCount", [0, 0],
        "SpeedFactor", [1, 0, "factor"], "MouseMultiplier", [1, 0.01, "factor"])
    pairs := ""
    for name, options in settings {
        field := GuiMain[name]
        if !save
            field.Value := IniRead(path, "RecorderSettings", name, options[1])
        fallback := name = "RepeatCount" ? 1 : options[1]
        value := options.Length = 3 ? ReadSpeedFactor(field, options[2])
            : ReadIntegerSetting(field, fallback, options[2])
        pairs .= name "=" value "`n"
    }
    if save
        IniWrite(RTrim(pairs, "`n"), path, "RecorderSettings")
}

ShowGui() {
    LoadColorSettings()
    global GuiMain, ActionsList
    global StartRecordingBtn, StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn
    global AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn
    global OriginalBtnText, BtnsDisableOnRecord, BtnsAllowedOnRecord
    global MenuFileRef, MenuEditRef, MenuRecordRef, MenuPlayRef
    global CompactBtn, CompactMode, GuiCompact
    global MainTabCtrl, MainCurrentTab, MainAllTabs, MainTabNames, MainTabLVNames
    global MainLVCounter, MainCurrentLV, MainTabChanging, MainLVHwnds, MainAllTabPaths

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
    MenuEditRef.Add()
    MenuEditRef.Add("Neuer Tab",                (*) => MainNewTab())
    MenuEditRef.Add("Tab löschen",              (*) => MainDeleteCurrentTabMenu())

    MenuRecordRef := Menu()
    MenuRecordRef.Add("Aufnahme starten`tF9",  (*) => BtnStartRecording())
    MenuRecordRef.Add("Aufnahme stoppen`tF10", (*) => BtnStopRecording())
    MenuRecordRef.Add()
    MenuRecordRef.Add("Tastatur aufnehmen",             (*) => ToggleRecordKeysMenu())
    MenuRecordRef.Add("Mausbewegung aufnehmen",         (*) => ToggleRecordMoveMenu())
    MenuRecordRef.Add()
    MenuRecordRef.Add("Klicks zusammenfassen",          (*) => ToggleOptimizeClicksMenu())
    MenuRecordRef.Add("Maus-Schwellenwert setzen...",   (*) => SetMoveThreshMenu())
    MenuRecordRef.Add("Langer-Klick-Schwelle setzen...", (*) => SetLongClickThreshMenu())

    MenuPlayRef := Menu()
    MenuPlayRef.Add("Einmal abspielen`tF11",        (*) => BtnPlayOnce())
    MenuPlayRef.Add("Loop umschalten`tF12",         (*) => BtnPlayLoop())
    MenuPlayRef.Add("Screenshot-Vorschau...",       ShowPlaybackPreview)
    MenuPlayRef.Add()
    MenuPlayRef.Add("Abbrechen`tESC",               (*) => BtnAbortAll())
    MenuPlayRef.Add()
    MenuPlayRef.Add("Countdown setzen...",          (*) => SetCountdownMenu())
    MenuPlayRef.Add("Wiederholungen setzen...",     (*) => SetRepeatCountMenu())
    MenuPlayRef.Add("Abspielgeschwindigkeit setzen...", (*) => SetSpeedFactorMenu())
    MenuPlayRef.Add("Mausgeschwindigkeit setzen...", (*) => SetMouseMultiplierMenu())

    menuExtras := Menu()
    menuExtras.Add("🎨 Aktionsfarben anpassen...",  (*) => ShowActionColorsDialog())
    menuExtras.Add()
    menuExtras.Add("Sequenz-Manager",          (*) => ShowSeqManager())
    menuExtras.Add("Zeit-Manager",             (*) => SetAllDelays())

    menuHelp := Menu()
    menuHelp.Add("Schnellhilfe",               (*) => ShowHelpDialog())
    menuHelp.Add("Über AHK Recorder",         (*) => ShowAboutDialog())

    mBar := MenuBar()
    mBar.Add("Datei",      MenuFileRef)
    mBar.Add("Bearbeiten", MenuEditRef)
    mBar.Add("Aufnahme",   MenuRecordRef)
    mBar.Add("Abspielen",  MenuPlayRef)
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
    ; Kompakt-Button rechts, überspannt beide Zeilen (h=56).
    ; Zeile 1+2 enden je bei x383 → Button x386 bis x500 = w114 h56
    CompactBtn := GuiMain.AddButton("x386 y6 w114 h56 Background0x555555 cWhite", "Kompakte`nAnsicht")
    CompactBtn.OnEvent("Click", (*) => ToggleCompactMode())

    ; Zeile 1: Datei-Aktionen  96+3+84+3+102+3+84 = 375px → x8..x383
    InsertBtn := GuiMain.AddButton("x8 y6 w96 h26 Background0x00CC00 cWhite",  "✚ Einfügen")
    DeleteBtn := GuiMain.AddButton("x+3 yp w84 h26 Background0xCC0000 cWhite", "✖ Löschen")
    SaveBtn   := GuiMain.AddButton("x+3 yp w102 h26 Background0x0070CC cWhite", "💾 Speichern")
    LoadBtn   := GuiMain.AddButton("x+3 yp w84 h26 Background0x0070CC cWhite",  "📂 Laden")
    InsertBtn.OnEvent("Click", (*) => AddAction())
    DeleteBtn.OnEvent("Click", (*) => DelAction())
    SaveBtn.OnEvent("Click",   (*) => SaveActionsQuick())
    LoadBtn.OnEvent("Click",   (*) => LoadActions())

    ; Zeile 2: Manager-Tools  186+3+186 = 375px → x8..x383
    GuiMain.AddButton("x8 y+4 w186 h26 Background0x404040 cWhite", "Sequenz-Manager")
        .OnEvent("Click", (*) => ShowSeqManager())
    GuiMain.AddButton("x+3 yp w186 h26 Background0x404040 cWhite", "Zeit-Manager")
        .OnEvent("Click", (*) => SetAllDelays())

    ; ── Aufnahmeeinstellungen GroupBox ──
    GuiMain.AddGroupBox("x8 y+6 w492 h100 Section cBlue", "Aufnahmeeinstellungen")
    GuiMain.SetFont("s9")

    ; ── Raster: 2 Spalten, 3 Zeilen ──
    ; Spalte 1: xs+12         Spalte 2: xs+248
    ; Zeile 1:  ys+20         Zeile 2: ys+46         Zeile 3: ys+72

    ; Zeile 1 | Spalte 1: Tastatur aufnehmen
    chkKeys := GuiMain.AddCheckBox("xs+12 ys+20 vChkRecordKeys", "Tastatur aufnehmen")
    chkKeys.OnEvent("Click", (*) => OnChkRecordKeys())
    GuiMain.AddButton("xs+126 ys+19 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Tastatureingaben aufnehmen:`n`n"
            "Alle Tastendrücke während der Aufnahme werden gespeichert`n"
            "und bei Wiedergabe an die aktive Anwendung gesendet.`n`n"
            "Modifier-Tasten (Strg, Alt, Shift, Win) werden automatisch`n"
            "als Kombination erkannt, z.B. ^c für Strg+C.", "Hilfe"))

    ; Zeile 1 | Spalte 2: Mausbewegung aufnehmen
    chkMove := GuiMain.AddCheckBox("xs+248 ys+20 vChkRecordMove", "Mausbewegung aufnehmen")
    chkMove.OnEvent("Click", (*) => OnChkRecordMove())
    GuiMain.AddButton("xs+406 ys+19 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Mausbewegungen aufnehmen:`n`n"
            "Bewegungen der Maus (ohne Klick) werden aufgezeichnet`n"
            "und bei Wiedergabe langsam nachgefahren.", "Hilfe"))

    ; Zeile 2 | Spalte 1: Klicks zusammenfassen
    chkOpt := GuiMain.AddCheckBox("xs+12 ys+46 vChkOptimize", "Klicks zusammenfassen (beim Stopp)")
    chkOpt.OnEvent("Click", (*) => OnChkOptimize())
    GuiMain.AddButton("xs+222 ys+45 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Klicks zusammenfassen:`n`n"
            "Werden beim Stoppen der Aufnahme mehrere gleiche`n"
            "Klicks an derselben Position hintereinander erkannt,`n"
            "werden diese zu einem Eintrag zusammengefasst:`n`n"
            "'Linksklick (5 mal)'`n`n"
            "Bei Wiedergabe wird die Aktion trotzdem entsprechend`n"
            "oft ausgeführt.", "Hilfe"))

    ; Zeile 2 | Spalte 2: Maus-Schwellenwert
    GuiMain.AddText("xs+248 ys+48", "Maus-Schwellenwert:")
    GuiMain.AddEdit("xs+370 ys+46 vMoveThreshEdit w36", "8")
    GuiMain.AddText("xs+408 ys+48", "px")
    GuiMain.AddButton("xs+422 ys+45 w14 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Maus-Schwellenwert:`n`n"
            "Minimale Bewegung in Pixeln bevor ein neuer Punkt`n"
            "in der Liste gespeichert wird.`n`n"
            "3 px  = sehr genau, viele Einträge`n"
            "8 px  = Standard, ausgewogen`n"
            "15 px = grob, wenige Einträge", "Hilfe"))

    ; Zeile 3 | Spalte 1: Langer-Klick-Schwellenwert
    GuiMain.AddText("xs+12 ys+74", "Langer-Klick-Schwelle (ms):")
    GuiMain.AddEdit("xs+180 ys+72 vLongClickThresholdEdit w40", "500")
    GuiMain.AddButton("xs+222 ys+71 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Langer-Klick-Schwellenwert:`n`n"
            "Legt fest, ab wie vielen Millisekunden ein gehaltener`n"
            "Klick als 'Langer Klick' erfasst wird.`n`n"
            "500 = Standard (0,5 Sekunden)`n"
            "1000 = 1 Sekunde`n"
            "200 = sehr kurz (0,2 Sekunden)`n`n"
            "Kürzere Klicks werden als normaler Klick aufgenommen.", "Hilfe"))

    ; ── Abspieleinstellungen GroupBox ──
    GuiMain.SetFont("s10")
    playbackGroup := GuiMain.AddGroupBox("x8 y+12 w492 h142 Section cBlue", "Abspieleinstellungen")
    GuiMain.SetFont("s9")

    ; Zeile 1: Countdown | Wiederholungen
    GuiMain.AddText("xs+12 ys+20", "Countdown (s):")
    GuiMain.AddEdit("xs+152 ys+18 vCountdownSec w40", "0")
    GuiMain.AddButton("xs+194 ys+17 w18 h18", "?")
        .OnEvent("Click", (*) => ShowInfo(
            "Countdown vor Wiedergabe:`n`n"
            "Wartezeit in Sekunden bevor die Wiedergabe startet.`n"
            "Gibt dir Zeit das Zielfenster zu fokussieren.`n`n"
            "0 = sofort starten.", "Hilfe"))

    GuiMain.AddText("xs+250 ys+20", "Wiederholungen:")
    GuiMain.AddEdit("xs+406 ys+18 vRepeatCount w40", "0")
    GuiMain.AddButton("xs+448 ys+17 w18 h18", "?")
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

    GuiMain.AddText("xs+250 ys+48", "Mausgeschw. (×):")
    GuiMain.AddEdit("xs+406 ys+46 vMouseMultiplier w40", "1")
    GuiMain.AddButton("xs+448 ys+45 w18 h18", "?")
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

    GuiMain.AddText("xs+12 ys+78", "Zielbildschirm:")
    GuiMain.AddDropDownList("xs+104 ys+74 w268 vTargetScreen", ["Originalpositionen"])
        .OnEvent("Change", ScreenProfileChanged)
    GuiMain.AddButton("xs+378 ys+74 w100 h23", "Anzeigen")
        .OnEvent("Click", ShowTargetScreen)
    GuiMain.AddText("xs+12 ys+110", "Anpassung:")
    GuiMain.AddDropDownList("xs+104 ys+104 w228 vScreenScale Choose2", ["Positionen beibehalten", "Proportional skalieren"])
        .OnEvent("Change", ScreenProfileChanged)
    GuiMain.AddButton("xs+338 ys+104 w140 h24", "Aufnahmeauflösung...")
        .OnEvent("Click", SetSourceScreen)
    ; ── Aktionsliste mit Tabs ──
    playbackGroup.GetPos(, &settingsY, , &settingsHeight)
    MainTabCtrl := GuiMain.AddTab3("x8 y" (settingsY + settingsHeight + 8) " w492 h328", MainTabNames)
    MainTabCtrl.OnEvent("Change",      (*) => MainSwitchTabFromCtrl())
    MainTabCtrl.OnEvent("ContextMenu", MainTabCtxMenu)

    ; ListViews für alle Start-Tabs anlegen
    MainTabCtrl.GetPos(&tabX, &tabY, &tabW, &tabH)
    lvX := tabX + 4
    lvY := tabY + 26
    lvW := tabW - 8
    lvH := tabH - 30
    MainTabLVNames := []

    loop MainTabNames.Length {
        MainLVCounter++
        lvName := "MainLV_" MainLVCounter
        MainTabLVNames.Push(lvName)
        MainTabCtrl.UseTab(A_Index)
        lv := GuiMain.AddListView("v" lvName " x" lvX " y" lvY " w" lvW " h" lvH " Grid Checked", ["", "Nr", "Aktion", "Wert"])
        MainSetupLV(lv)
        if A_Index = 1
            MainCurrentLV := lv
    }
    MainTabCtrl.UseTab(0)

    ; ActionsList auf ersten Tab zeigen
    ActionsList := MainAllTabs[1]

    SetupLVColors()     ; NM_CUSTOMDRAW für Zeilenfarben aktivieren
    SetupLVDragDrop()   ; Drag & Drop zum Umsortieren aktivieren

    ; ── Navigation unter Tabs ──
    GuiMain.AddButton("x8 y+4 w244 h24 Background0x555555 cWhite", "⬆ Zum Anfang")
        .OnEvent("Click", (*) => LVScrollToTop())
    GuiMain.AddButton("x+4 yp w244 h24 Background0x555555 cWhite", "⬇ Zum Ende")
        .OnEvent("Click", (*) => LVScrollToBottom())

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
    GuiMain.AddText("vScreenBounds xs+8 y+5   w460 cGray", "Auflösung: ermittle...")
    GuiMain.SetFont("s10")

    ; ── Button-Gruppen für UpdateGui ──
    BtnsDisableOnRecord := [StartRecordingBtn, InsertBtn, SaveBtn, LoadBtn, PlayOnceBtn, ToggleRepeatBtn]
    BtnsAllowedOnRecord := [StopRecordingBtn, AbortBtn, ExitBtn, DeleteBtn]

    for btn in [StartRecordingBtn, StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn,
                AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn]
        OriginalBtnText[btn.Hwnd] := btn.Text

    try RecorderNumericSettings()
    GuiMain.Show()

    ; Zuletzt geöffnet laden und Menü aufbauen
    LoadRecentFiles()
    RebuildRecentMenu()
    ; Undo/Redo initial deaktivieren
    UpdateUndoMenuState()
    ; Tab-Lösch-Eintrag initial korrekt beschriften und enable/disable
    UpdateEditMenuTabs()
    ; Hover-Tooltip für abgekürzte Tab-Labels
    OnMessage(0x200, MainTabMouseMove)
}

; ═════════════════════════════════════════════
; Aktionslisten-Tab-System (Hauptfenster)
; ═════════════════════════════════════════════

; ListView konfigurieren und in MainLVHwnds registrieren
MainSetupLV(LV) {
    global MainLVHwnds
    LV.ModifyCol(1, "26")    ; Checkbox-Spalte (kein Header)
    LV.ModifyCol(2, "40")    ; Nr
    LV.ModifyCol(3, "150")   ; Aktion
    LV.ModifyCol(4, "268")   ; Wert
    LV.OnEvent("DoubleClick", (lv, r) => EditAction(lv, r))
    LV.OnEvent("ContextMenu", (lv,r,rc,x,y) => ShowLVContextMenu(lv,r,rc,x,y))
    MainLVHwnds.Push(LV.Hwnd)
}

; Tab-Wechsel durch Klick auf Reiter
MainSwitchTabFromCtrl() {
    global MainTabChanging, MainTabCtrl, MainCurrentTab
    global MainAllTabs, ActionsList, MainCurrentLV, MainTabLVNames
    global MainAllTabPaths, CurrentFilePath, GuiMain, IsRecording

    if MainTabChanging
        return
    newTab := MainTabCtrl.Value
    if newTab = MainCurrentTab || newTab < 1 || newTab > MainAllTabs.Length
        return
    if IsRecording {
        MainTabCtrl.Value := MainCurrentTab
        return
    }

    ; Aktuellen Zustand sichern
    MainAllTabs[MainCurrentTab]    := ActionsList
    MainAllTabPaths[MainCurrentTab] := CurrentFilePath

    MainCurrentTab  := newTab
    ActionsList     := MainAllTabs[newTab]
    CurrentFilePath := MainAllTabPaths[newTab]
    MainCurrentLV   := GuiMain[MainTabLVNames[newTab]]
    UpdateActionsList()
    SetCurrentFile(CurrentFilePath)
    UpdateUndoMenuState()
    UpdateEditMenuTabs()
}

; Rechtsklick auf Tab-Leiste
MainTabCtxMenu(ctrl, item, isRightClick, x, y) {
    global MainAllTabs
    n   := ctrl.Value
    ctx := Menu()
    if n >= 1 && n <= MainAllTabs.Length {
        ctx.Add("Umbenennen...", (*) => MainRenameTab(n))
        if MainAllTabs.Length > 1
            ctx.Add("Löschen",  (*) => MainDeleteTab(n))
        ctx.Add()
    }
    ctx.Add("Neuer Tab", (*) => MainNewTab())
    ctx.Show()
}

; Neuen Tab anlegen
MainNewTab() {
    global MainScreenProfiles
    global MainAllTabs, MainTabNames, MainTabLVNames, MainLVCounter, MainTabCtrl
    global MainCurrentTab, ActionsList, MainCurrentLV, MainTabChanging, GuiMain
    global MainLVHwnds, MainAllTabPaths, CurrentFilePath, MainTabTooltips
    global MainUndoTabs, MainRedoTabs
    global IsRecording
    if IsRecording
        return

    if MainTabNames.Length >= 16
        return

    ; Aktuellen Zustand sichern
    MainAllTabs[MainCurrentTab]    := ActionsList
    MainAllTabPaths[MainCurrentTab] := CurrentFilePath

    newName := "Tab " (MainTabNames.Length + 1)
    MainTabNames.Push(newName)
    MainAllTabs.Push([])
    MainScreenProfiles.Push(NewScreenProfile())
    MainUndoTabs.Push([])
    MainRedoTabs.Push([])
    MainAllTabPaths.Push("")
    MainTabTooltips.Push("")
    newIdx := MainTabNames.Length

    MainTabChanging := true
    MainTabCtrl.Add([newName])
    if newIdx <= MainTabLVNames.Length {
        lv := GuiMain[MainTabLVNames[newIdx]]
        lv.Delete()
    } else {
        MainLVCounter++
        lvName := "MainLV_" MainLVCounter
        MainTabLVNames.Push(lvName)

        MainTabCtrl.GetPos(&tabX, &tabY, &tabW, &tabH)
        lvX := tabX + 4
        lvY := tabY + 26
        lvW := tabW - 8
        lvH := tabH - 30

        MainTabCtrl.UseTab(newIdx)
        lv := GuiMain.AddListView("v" lvName " x" lvX " y" lvY " w" lvW " h" lvH " Grid Checked", ["", "Nr", "Aktion", "Wert"])
        MainSetupLV(lv)
        MainTabCtrl.UseTab(0)
    }
    MainTabChanging := false

    ; State vor Value-Zuweisung setzen, dann Value ausserhalb Guard
    MainCurrentTab  := newIdx
    ActionsList     := MainAllTabs[newIdx]
    CurrentFilePath := ""
    MainCurrentLV   := lv
    MainTabCtrl.Value := newIdx

    UpdateActionsList()
    SetCurrentFile("")
    UpdateUndoMenuState()
    UpdateEditMenuTabs()
}

; Tab löschen
MainDeleteTab(n) {
    global MainScreenProfiles
    global MainAllTabs, MainTabNames, MainTabLVNames, MainCurrentTab
    global ActionsList, MainCurrentLV, MainTabChanging, MainTabCtrl, GuiMain
    global MainAllTabPaths, CurrentFilePath, MainTabTooltips
    global MainUndoTabs, MainRedoTabs
    global IsRecording
    if IsRecording
        return

    if MainAllTabs.Length <= 1
        return
    if n < 1 || n > MainAllTabs.Length
        return

    MainAllTabs.RemoveAt(n)
    MainScreenProfiles.RemoveAt(n)
    MainUndoTabs.RemoveAt(n)
    MainRedoTabs.RemoveAt(n)
    MainTabNames.RemoveAt(n)
    MainAllTabPaths.RemoveAt(n)
    MainTabTooltips.RemoveAt(n)

    ; Steuerelement des frei gewordenen Tab-Platzes für später leeren.
    GuiMain[MainTabLVNames[MainAllTabs.Length + 1]].Delete()

    MainCurrentTab := Min(n, MainAllTabs.Length)

    ; State VOR dem Tab3-Rebuild setzen, damit jedes Change-Event das
    ; während des Rebuilds feuert bereits den korrekten Zustand vorfindet.
    ActionsList     := MainAllTabs[MainCurrentTab]
    CurrentFilePath := MainAllTabPaths[MainCurrentTab]
    MainCurrentLV   := GuiMain[MainTabLVNames[MainCurrentTab]]

    MainTabChanging := true
    MainTabCtrl.Delete()
    MainTabCtrl.Add(MainTabNames)
    MainTabChanging := false

    ; Value außerhalb Guard setzen damit Tab3 Show/Hide laufen kann.
    ; ABER: Nach Delete()+Add() kann AHK "Value schon 1" detektieren
    ; und das Show/Hide überspringen → LV bleibt hidden.
    ; Deshalb: LV explizit sichtbar setzen + nach Message-Queue-Flush
    ; nochmal rendern (SetTimer -1 = nach aktuellen pending events).
    MainTabCtrl.Value := MainCurrentTab
    if IsObject(MainCurrentLV)
        MainCurrentLV.Visible := true
    UpdateActionsList()
    SetCurrentFile(CurrentFilePath)

    _delTab := MainCurrentTab
    SetTimer(MainDeleteTabRefresh.Bind(_delTab), -1)
}

MainDeleteTabRefresh(savedTab) {
    global MainCurrentTab, MainCurrentLV
    if MainCurrentTab != savedTab
        return
    if IsObject(MainCurrentLV)
        MainCurrentLV.Visible := true
    UpdateActionsList()
    UpdateEditMenuTabs()
}

; Tab umbenennen
MainRenameTab(n) {
    global MainTabNames, MainAllTabs, GuiMain
    if n < 1 || n > MainTabNames.Length
        return
    originalTab := MainAllTabs[n]
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    try result := InputBox("Neuer Tab-Name:", "Tab umbenennen", "w280 h100", MainTabNames[n])
    finally {
        try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
        GuiMain.Show()
    }
    if result.Result != "OK" || Trim(result.Value) = ""
        return
    if n > MainAllTabs.Length || MainAllTabs[n] != originalTab {
        ShowWarning("Der Tab hat sich inzwischen geändert. Bitte erneut öffnen.")
        return
    }
    MainSilentRenameTab(n, Trim(result.Value))
}

; Tab lautlos umbenennen (kein InputBox) – für programmatisches Umbenennen
MainSilentRenameTab(n, name) {
    global MainTabNames, MainTabCtrl, MainTabChanging
    if n < 1 || n > MainTabNames.Length || name = ""
        return
    MainTabNames[n] := name
    curVal := MainTabCtrl.Value
    MainTabChanging := true
    MainTabCtrl.Delete()
    MainTabCtrl.Add(MainTabNames)
    MainTabChanging := false
    MainTabCtrl.Value := curVal
    UpdateEditMenuTabs()
}

; ─────────────────────────────────────────────
; Tab-Hover-Tooltip: zeigt vollen Namen wenn der
; Tab-Label auf 6 Zeichen abgekürzt wurde.
; Registrierung: OnMessage(0x200, MainTabMouseMove)
; ─────────────────────────────────────────────
MainTabMouseMove(wParam, lParam, msg, hwnd) {
    global MainTabCtrl, MainTabTooltips, _MainLastTooltipTab
    if !IsObject(MainTabCtrl) || hwnd != MainTabCtrl.Hwnd {
        ; Maus hat Tab-Control verlassen → Tooltip wegräumen
        if _MainLastTooltipTab != 0 {
            _MainLastTooltipTab := 0
            ToolTip()
        }
        return
    }
    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF
    ; TCM_HITTEST (0x130D): welcher Reiter liegt unter (x,y)?
    hti := Buffer(12, 0)
    NumPut("Int", x, hti, 0)
    NumPut("Int", y, hti, 4)
    idx := SendMessage(0x130D, 0, hti.Ptr, MainTabCtrl.Hwnd) + 1   ; 0-basiert → 1-basiert
    if idx >= 1 && idx <= MainTabTooltips.Length {
        tip := MainTabTooltips[idx]
        if tip != "" {
            if idx != _MainLastTooltipTab {
                _MainLastTooltipTab := idx
                ToolTip(tip)
                SetTimer(() => ToolTip(), -3000)
            }
            return
        }
    }
    ; Kein Tooltip für diesen Reiter
    if _MainLastTooltipTab != 0 {
        _MainLastTooltipTab := 0
        ToolTip()
    }
}

; ─────────────────────────────────────────────
; Kompakt-Modus: separates kleines Fenster mit nur der Steuerung
; ─────────────────────────────────────────────
ToggleCompactMode(*) {
    global CompactMode, CompactBtn, GuiMain, GuiCompact, _OrigBtnRefs
    global StartRecordingBtn, StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn, AbortBtn, ExitBtn
    global CmpStartRecordingBtn, CmpStopRecordingBtn, CmpPlayOnceBtn
    global CmpToggleRepeatBtn, CmpAbortBtn, CmpExitBtn
    global BtnsDisableOnRecord, BtnsAllowedOnRecord, OriginalBtnText, _LastRecordingState

    if CompactMode {
        ; ── Vollansicht wiederherstellen ──
        if IsObject(GuiCompact)
            GuiCompact.Hide()

        ; Globale Button-Refs auf GuiMain-Buttons zuruecksetzen
        StartRecordingBtn := _OrigBtnRefs["Start"]
        StopRecordingBtn  := _OrigBtnRefs["Stop"]
        PlayOnceBtn       := _OrigBtnRefs["Play"]
        ToggleRepeatBtn   := _OrigBtnRefs["Loop"]
        AbortBtn          := _OrigBtnRefs["Abort"]
        ExitBtn           := _OrigBtnRefs["Exit"]

        BtnsDisableOnRecord := [StartRecordingBtn, _OrigBtnRefs["Insert"],
                                _OrigBtnRefs["Save"], _OrigBtnRefs["Load"],
                                PlayOnceBtn, ToggleRepeatBtn]
        BtnsAllowedOnRecord := [StopRecordingBtn, AbortBtn, ExitBtn,
                                _OrigBtnRefs["Delete"]]

        CompactBtn.Text := "Kompakte`nAnsicht"
        CompactMode := false
        _LastRecordingState := -1   ; UpdateGui neu erzwingen
        GuiMain.Show()
        return
    }

    ; ── Kompakt-Fenster aufbauen (einmalig) ──
    if !IsObject(GuiCompact)
        _BuildCompactGui()

    ; Globale Button-Refs auf Compact-Buttons umschalten
    StartRecordingBtn := CmpStartRecordingBtn
    StopRecordingBtn  := CmpStopRecordingBtn
    PlayOnceBtn       := CmpPlayOnceBtn
    ToggleRepeatBtn   := CmpToggleRepeatBtn
    AbortBtn          := CmpAbortBtn
    ExitBtn           := CmpExitBtn

    BtnsDisableOnRecord := [CmpStartRecordingBtn, CmpPlayOnceBtn, CmpToggleRepeatBtn]
    BtnsAllowedOnRecord := [CmpStopRecordingBtn, CmpAbortBtn, CmpExitBtn]

    CompactMode := true
    CompactBtn.Text := "Volle`nAnsicht"
    _LastRecordingState := -1   ; UpdateGui neu erzwingen
    GuiMain.Hide()
    GuiCompact.Show()
}

; ─────────────────────────────────────────────
; Kompakt-Fenster einmalig aufbauen
; ─────────────────────────────────────────────
_BuildCompactGui() {
    global GuiCompact, OriginalBtnText, _OrigBtnRefs
    global InsertBtn, DeleteBtn, SaveBtn, LoadBtn
    global StartRecordingBtn, StopRecordingBtn, PlayOnceBtn, ToggleRepeatBtn, AbortBtn, ExitBtn
    global CmpStartRecordingBtn, CmpStopRecordingBtn, CmpPlayOnceBtn
    global CmpToggleRepeatBtn, CmpAbortBtn, CmpExitBtn
    global GuiMain

    ; Originale GuiMain-Button-Refs sichern
    _OrigBtnRefs["Start"]  := StartRecordingBtn
    _OrigBtnRefs["Stop"]   := StopRecordingBtn
    _OrigBtnRefs["Play"]   := PlayOnceBtn
    _OrigBtnRefs["Loop"]   := ToggleRepeatBtn
    _OrigBtnRefs["Abort"]  := AbortBtn
    _OrigBtnRefs["Exit"]   := ExitBtn
    _OrigBtnRefs["Insert"] := InsertBtn
    _OrigBtnRefs["Delete"] := DeleteBtn
    _OrigBtnRefs["Save"]   := SaveBtn
    _OrigBtnRefs["Load"]   := LoadBtn

    GuiCompact := Gui("+AlwaysOnTop +Resize", "AHK Recorder  [Kompakt]")
    GuiCompact.SetFont("s10")
    GuiCompact.OnEvent("Close", (*) => ToggleCompactMode())

    ; ── Steuerung ──
    GuiCompact.AddGroupBox("x8 y8 w492 h170 Section cBlue", "Steuerung")

    BtnW  := 238
    BtnH  := 42
    BtnH2 := 34

    ; Reihe 1: Aufnahme
    CmpStartRecordingBtn := GuiCompact.AddButton(
        "xs+4 ys+18 w" BtnW " h" BtnH " Background0x009900 cWhite", "AUFNAHME STARTEN  (F9)")
    CmpStopRecordingBtn  := GuiCompact.AddButton(
        "xs+" (BtnW+8) " ys+18 w" BtnW " h" BtnH " Background0xCC0000 cWhite", "AUFNAHME STOPPEN  (F10)")
    CmpStartRecordingBtn.OnEvent("Click", (*) => BtnStartRecording())
    CmpStopRecordingBtn.OnEvent("Click",  (*) => BtnStopRecording())

    ; Reihe 2: Wiedergabe
    CmpPlayOnceBtn     := GuiCompact.AddButton(
        "xs+4 ys+66 w" BtnW " h" BtnH " Background0x0070CC cWhite", "EINMAL ABSPIELEN  (F11)")
    CmpToggleRepeatBtn := GuiCompact.AddButton(
        "xs+" (BtnW+8) " ys+66 w" BtnW " h" BtnH " Background0xCC7700 cWhite", "LOOP AN/AUS  (F12)")
    CmpPlayOnceBtn.OnEvent("Click",     (*) => BtnPlayOnce())
    CmpToggleRepeatBtn.OnEvent("Click", (*) => BtnPlayLoop())

    ; Reihe 3: Abbrechen / Beenden
    CmpAbortBtn := GuiCompact.AddButton(
        "xs+4 ys+114 w" BtnW " h" BtnH2 " Background0x660088 cWhite", "ABBRECHEN  (ESC / Pause)")
    CmpExitBtn  := GuiCompact.AddButton(
        "xs+" (BtnW+8) " ys+114 w" BtnW " h" BtnH2 " Background0x444444 cWhite", "BEENDEN")
    CmpAbortBtn.OnEvent("Click", (*) => BtnAbortAll())
    CmpExitBtn.OnEvent("Click",  (*) => ExitScript())

    ; ── Vollansicht-Button ──
    GuiCompact.AddButton("x8 y+8 w160 h26 Background0x555555 cWhite", "⊞ Vollansicht")
        .OnEvent("Click", (*) => ToggleCompactMode())

    ; Original-Texte fuer UpdateGui registrieren
    for btn in [CmpStartRecordingBtn, CmpStopRecordingBtn, CmpPlayOnceBtn,
                CmpToggleRepeatBtn, CmpAbortBtn, CmpExitBtn]
        OriginalBtnText[btn.Hwnd] := btn.Text
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

ToggleOptimizeClicksMenu(*) {
    global OptimizeClicks, MenuRecordRef, GuiMain
    OptimizeClicks := !OptimizeClicks
    if OptimizeClicks {
        MenuRecordRef.Check("Klicks zusammenfassen")
    } else {
        MenuRecordRef.Uncheck("Klicks zusammenfassen")
    }
    GuiMain["ChkOptimize"].Value := OptimizeClicks
}

SetMoveThreshMenu(*) {
    global MouseMoveThreshold, GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    result := InputBox("Maus-Schwellenwert (Pixel, min. 1):", "Maus-Schwellenwert setzen", "w300 h110", MouseMoveThreshold)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    GuiMain.Show()
    if result.Result != "OK"
        return
    val := Trim(result.Value)
    if !TryParseIntegerSetting(val, 1, &parsed)
        return
    MouseMoveThreshold := parsed
    GuiMain["MoveThreshEdit"].Value := MouseMoveThreshold
}

SetLongClickThreshMenu(*) {
    global LongClickThreshold, GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    result := InputBox("Langer-Klick-Schwelle (ms, min. 50):", "Langer-Klick-Schwelle setzen", "w300 h110", LongClickThreshold)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    GuiMain.Show()
    if result.Result != "OK"
        return
    val := Trim(result.Value)
    if !TryParseIntegerSetting(val, 50, &parsed)
        return
    LongClickThreshold := parsed
    GuiMain["LongClickThresholdEdit"].Value := LongClickThreshold
}

; ─────────────────────────────────────────────
; Abspielen-Menü: Einstellungen setzen
; ─────────────────────────────────────────────
SetCountdownMenu(*) {
    global GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    result := InputBox("Countdown vor Wiedergabe (s, min. 0):", "Countdown setzen", "w300 h110", GuiMain["CountdownSec"].Value)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    GuiMain.Show()
    if result.Result != "OK"
        return
    val := Trim(result.Value)
    if !TryParseIntegerSetting(val, 0, &parsed) {
        ShowWarning("Bitte eine ganze Zahl ab 0 eingeben.")
        return
    }
    GuiMain["CountdownSec"].Value := parsed
}

SetRepeatCountMenu(*) {
    global GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    result := InputBox("Wiederholungen (0 = endlos):", "Wiederholungen setzen", "w300 h110", GuiMain["RepeatCount"].Value)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    GuiMain.Show()
    if result.Result != "OK"
        return
    val := Trim(result.Value)
    if !TryParseIntegerSetting(val, 0, &parsed) {
        ShowWarning("Bitte eine ganze Zahl ab 0 eingeben.")
        return
    }
    GuiMain["RepeatCount"].Value := parsed
}

SetSpeedFactorMenu(*) {
    global GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    result := InputBox("Abspielgeschwindigkeit (z.B. 1.0 = normal, 2.0 = doppelt):", "Abspielgeschwindigkeit setzen", "w320 h110", GuiMain["SpeedFactor"].Value)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    GuiMain.Show()
    if result.Result != "OK"
        return
    val := Trim(result.Value)
    if !IsPlaybackSpeedFactor(val)
        return
    GuiMain["SpeedFactor"].Value := Float(val)
}

SetMouseMultiplierMenu(*) {
    global GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    result := InputBox("Mausgeschwindigkeit (×, z.B. 1 = normal, 10 = 10× schneller):", "Mausgeschwindigkeit setzen", "w340 h110", GuiMain["MouseMultiplier"].Value)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    GuiMain.Show()
    if result.Result != "OK"
        return
    val := Trim(result.Value)
    if !IsPlaybackSpeedFactor(val, 0.01)
        return
    GuiMain["MouseMultiplier"].Value := Float(val)
}

; ─────────────────────────────────────────────
; Datei-Menü: Neu
; ─────────────────────────────────────────────
MenuFileNew(*) {
    global IsRecording
    if IsRecording
        return
    global ActionsList, GuiMain, CurrentFilePath, MainAllTabs, MainCurrentTab, MainAllTabPaths
    if ActionsList.Length > 0 {
        result := ShowYesNo("Aktuelle Liste verwerfen und neu beginnen?")
        if result != "Yes"
            return
    }
    ActionsList    := []
    CurrentFilePath := ""
    MainAllTabs[MainCurrentTab]    := ActionsList
    MainAllTabPaths[MainCurrentTab] := ""
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
    SplitPath(filePath, &filename)
    source := ActionsList
    original := source.Clone()
    staged := original.Clone()
    try {
        UpdateRecordingComments(staged, filename)
        WriteActionFile(filePath, staged, CurrentScreenProfile())
    } catch as err {
        ShowError("Fehler beim Speichern:`n" err.Message)
        return false
    }

    for index, action in staged {
        if action != original[index] && index <= source.Length && source[index] = original[index]
            source[index] := action
    }
    if ActionsList = source {
        SetCurrentFile(filePath)
        UpdateActionsList()
    }
    return true
}

; ─────────────────────────────────────────────
; Rechtsklick-Kontextmenü in der ListView
; ─────────────────────────────────────────────
PlaySelectedActions(lv, clickedRow := 0) {
    selected := GetActionsForContextMenu(lv, clickedRow)
    if selected.Length
        BtnPlayOnce(selected)
}

ExportSelectedActions(lv, clickedRow := 0) {
    global GuiMain
    selected := GetActionsForContextMenu(lv, clickedRow)
    if !selected.Length
        return
    profile := CurrentScreenProfile().Clone()
    for index, action in selected
        selected[index] := action.Clone()
    try {
        GuiMain.Opt("-AlwaysOnTop")
        try file := FileSelect("S16", A_ScriptDir "\Auswahl.json",
            "Aktionsauswahl speichern", "JSON-Dateien (*.json)")
        finally GuiMain.Opt("+AlwaysOnTop")
        if !file
            return
        file := ConfirmJsonSavePath(file)
        if file
            WriteActionFile(file, selected, profile)
    } catch Error as err {
        ShowError("Die Aktionsauswahl konnte nicht gespeichert werden." Chr(10) err.Message)
    }
}

GetActionsForContextMenu(lv, clickedRow := 0) {
    global ActionsList, MainCurrentLV
    if lv != MainCurrentLV
        return []
    selected := []
    state := lv.GetNext(0, "Checked") ? "Checked" : ""
    row := 0
    while row := lv.GetNext(row, state) {
        if row <= ActionsList.Length
            selected.Push(ActionsList[row])
    }
    if !selected.Length && clickedRow >= 1 && clickedRow <= ActionsList.Length
        selected.Push(ActionsList[clickedRow])
    return selected
}

ShowLVContextMenu(LV, rowIndex, isRightClick, x, y) {
    global ActionsList

    ; Anzahl der selektierten Zeilen zählen
    selCount := 0
    r := 0
    loop {
        r := LV.GetNext(r)
        if !r
            break
        selCount++
    }

    ; Anzahl der gecheckte Zeilen zählen
    checkedCount := 0
    r := 0
    loop {
        r := LV.GetNext(r, "Checked")
        if !r
            break
        checkedCount++
    }
    targetCount := checkedCount > 0 ? checkedCount : selCount
    hasSelection := targetCount > 0

    ctx := Menu()

    if rowIndex > 0 && rowIndex <= ActionsList.Length {
        if targetCount > 1 {
            ; ── Mehrfachauswahl ──
            ctx.Add(targetCount " Einträge löschen`tEntf", (*) => DelAction())
            ctx.Add("Duplizieren (" targetCount "×)",      (*) => DuplicateSelected(LV))
            ctx.Add("Kopieren (" targetCount "×)",         (*) => CopyActions(LV, rowIndex))
            ctx.Add("✏ Ersetzen...",                    (*) => ReplaceSelectedActions(LV))
        } else {
            ; ── Einzelauswahl ──
            ctx.Add("Bearbeiten`tEnter",    (*) => EditAction(LV, rowIndex))
            ctx.Add("Duplizieren",          (*) => (checkedCount ? DuplicateSelected(LV) : DuplicateAction(rowIndex)))
            ctx.Add("Kopieren",             (*) => CopyActions(LV, rowIndex))
            ctx.Add("✏ Ersetzen...",        (*) => ReplaceSelectedActions(LV))
            ctx.Add("Löschen`tEntf",        (*) => (checkedCount ? DelAction() : DelSingleRow(rowIndex)))
            ctx.Add()
            ctx.Add("Nach oben",            (*) => MoveActionRow(rowIndex, -1))
            ctx.Add("Nach unten",           (*) => MoveActionRow(rowIndex, +1))
            if rowIndex <= 1
                ctx.Disable("Nach oben")
            if rowIndex >= ActionsList.Length
                ctx.Disable("Nach unten")

            ; ── Position anzeigen (nur für Typen mit Koordinaten) ──
            aPos := ActionsList[rowIndex]
            if aPos is Map && aPos.Has("Type") {
                t := aPos["Type"]
                if t = "Click" || t = "LongClick" || t = "MouseMove" || (t = "Scroll" && HasScrollPosition(aPos)) {
                    ctx.Add()
                    ctx.Add("🎯 Position anzeigen",
                        (*) => ShowPositionMarker(aPos["X"], aPos["Y"]))
                } else if t = "Drag" {
                    ctx.Add()
                    ctx.Add("🎯 Startposition anzeigen",
                        (*) => ShowPositionMarker(aPos["X1"], aPos["Y1"]))
                    ctx.Add("🎯 Zielposition anzeigen",
                        (*) => ShowPositionMarker(aPos["X2"], aPos["Y2"]))
                }
            }
        }
        ctx.Add()
        ctx.Add("Hier einfügen",        (*) => PasteActionsAt(LV, rowIndex))
        if LVCopiedItems.Length = 0
            ctx.Disable("Hier einfügen")
    } else {
        ctx.Add("Einfügen...",          (*) => AddAction())
        ctx.Add()
        ctx.Add("Hier einfügen",        (*) => PasteActionsAt(LV, 0))
        if LVCopiedItems.Length = 0
            ctx.Disable("Hier einfügen")
    }

    ctx.Add()
    if hasSelection || (rowIndex >= 1 && rowIndex <= ActionsList.Length) {
        ctx.Add(hasSelection ? "Auswahl einmal abspielen" : "Diese Aktion einmal abspielen", (*) => PlaySelectedActions(LV, rowIndex))
        ctx.Add(hasSelection ? "Auswahl als JSON speichern..." : "Diese Aktion als JSON speichern...", (*) => ExportSelectedActions(LV, rowIndex))
        ctx.Add("Zeit-Manager für Auswahl...", (*) => SetSelectedDelays(LV, rowIndex))
    }
    ctx.Add("Alle auswählen`tStrg+A",  (*) => SelectAllInListView())
    ctx.Add()
    ctx.Add("⊞ Alle Klicks zusammenfassen",          (*) => OptimizeConsecutiveClicks())
    ctx.Add("↩ Alle Klicks wiederherstellen",         (*) => RestoreConsecutiveClicks())
    ctx.Add("⊞ Markierte Klicks zusammenfassen",     (*) => OptimizeSelectedClicks(LV))
    ctx.Add("↩ Markierte Klicks wiederherstellen",   (*) => RestoreSelectedClicks(LV))
    if !hasSelection {
        ctx.Disable("⊞ Markierte Klicks zusammenfassen")
        ctx.Disable("↩ Markierte Klicks wiederherstellen")
    }
    ctx.Add()
    ctx.Add("Alle löschen",              (*) => DelAllActions())
    ctx.Show(x, y)
}

; ─────────────────────────────────────────────
; Fadenkreuz-Marker: Maus zur Position bewegen und blinkendes
; Fadenkreuz (2 Linien + Kreis) an den Koordinaten anzeigen.
; ─────────────────────────────────────────────
ShowPositionMarker(px, py) {
    global _MarkerGuis, _MarkerBlinks

    ; Laufenden Marker stoppen und Fenster schließen
    SetTimer(BlinkMarker, 0)
    for mg in _MarkerGuis
        try mg.Destroy()
    _MarkerGuis := []

    ; Maus zur Zielposition bewegen (Geschwindigkeit 3 = sichtbar aber flott)
    MouseMove(px, py, 3)

    col := "FF2200"   ; leuchtendes Rot-Orange

    ; Horizontale Linie (60 × 3 px), zentriert bei py
    h := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    h.BackColor := col
    h.Show("x" (px - 30) " y" (py - 1) " w60 h3 NoActivate")
    _MarkerGuis.Push(h)

    ; Vertikale Linie (3 × 60 px), zentriert bei px
    v := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    v.BackColor := col
    v.Show("x" (px - 1) " y" (py - 30) " w3 h60 NoActivate")
    _MarkerGuis.Push(v)

    ; Kreis in der Mitte (16 × 16 px, elliptische Region per GDI)
    c := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    c.BackColor := col
    c.Show("x" (px - 8) " y" (py - 8) " w16 h16 NoActivate")
    hRgn := DllCall("CreateEllipticRgn", "Int", 0, "Int", 0, "Int", 16, "Int", 16, "Ptr")
    if hRgn {
        if !DllCall("SetWindowRgn", "Ptr", c.Hwnd, "Ptr", hRgn, "Int", 1)
            DllCall("DeleteObject", "Ptr", hRgn)   ; bei Fehler selbst freigeben
    }
    _MarkerGuis.Push(c)

    ; Koordinaten als Tooltip neben dem Cursor
    ToolTip("X=" px "   Y=" py, px + 18, py + 18)
    SetTimer(() => ToolTip(), -2500)

    _MarkerBlinks := 0
    SetTimer(BlinkMarker, 170)
}

BlinkMarker() {
    global _MarkerGuis, _MarkerBlinks
    _MarkerBlinks++
    if _MarkerBlinks > 13 {           ; ~13 × 170 ms ≈ 2,2 Sek. sichtbar
        SetTimer(BlinkMarker, 0)
        for mg in _MarkerGuis
            try mg.Destroy()
        _MarkerGuis := []
        return
    }
    show := Mod(_MarkerBlinks, 2) = 0
    for mg in _MarkerGuis {
        try {
            if show
                mg.Show("NoActivate")
            else
                mg.Hide()
        }
    }
}

; ═══════════════════════════════════════════════════════
; FARB-HILFSFUNKTIONEN
; ═══════════════════════════════════════════════════════

; COLORREF (0x00BBGGRR) → 6-stelliger RGB-Hex-String für AHK BackColor ("RRGGBB")
CRToHex(cr) {
    r := cr & 0xFF
    g := (cr >> 8)  & 0xFF
    b := (cr >> 16) & 0xFF
    return Format("{:02X}{:02X}{:02X}", r, g, b)
}

; Ist die COLORREF-Farbe dunkel? (für automatische Textfarbe auf Buttons)
IsDark(colorRef) {
    r := colorRef & 0xFF
    g := (colorRef >> 8)  & 0xFF
    b := (colorRef >> 16) & 0xFF
    return (0.299 * r + 0.587 * g + 0.114 * b) < 128
}

; Windows Standard-Farbauswahl-Dialog (ChooseColorW)
; Gibt gewählte COLORREF zurück, oder -1 bei Abbruch.
ShowWindowsColorPicker(initColorRef := 0xFFFFFF, ownerHwnd := 0) {
    static custColors := Buffer(64, 0)   ; 16 benutzerdefinierte Farben
    cc := Buffer(72, 0)
    NumPut("UInt", 72,             cc,  0)   ; lStructSize
    NumPut("Ptr",  ownerHwnd,      cc,  8)   ; hwndOwner
    NumPut("UInt", initColorRef,   cc, 24)   ; rgbResult (Initialfarbe)
    NumPut("Ptr",  custColors.Ptr, cc, 32)   ; lpCustColors
    NumPut("UInt", 0x3,            cc, 40)   ; CC_RGBINIT | CC_FULLOPEN
    if DllCall("comdlg32\ChooseColorW", "Ptr", cc.Ptr, "Int")
        return NumGet(cc, 24, "UInt")
    return -1
}

; Standardfarben pro Aktionstyp (COLORREF)
GetDefaultActionColors() {
    return Map(
        "Click",     Map("bg", 0xFFF0F0, "fg", 0x000000),
        "LongClick", Map("bg", 0xCCEEFF, "fg", 0x000000),
        "Drag",      Map("bg", 0xFFEECC, "fg", 0x000000),
        "Delay",     Map("bg", 0xCCCCFF, "fg", 0x000000),
        "Scroll",    Map("bg", 0xCCFFCC, "fg", 0x000000),
        "KeyPress",  Map("bg", 0xFFCCF5, "fg", 0x000000),
        "MouseMove", Map("bg", 0xFAFFCC, "fg", 0x000000),
        "Comment",   Map("bg", 0xCC4400, "fg", 0xFFFFFF),
        "TextInput", Map("bg", 0xFFCCEE, "fg", 0x000000)
    )
}

; Farben aus settings.ini laden (oder Standardwerte)
LoadColorSettings() {
    global ActionTypeColors
    ActionTypeColors := GetDefaultActionColors()
    iniPath := A_ScriptDir "\settings.ini"
    if !FileExist(iniPath)
        return
    for t, m in ActionTypeColors {
        try {
            bgHex := IniRead(iniPath, "ActionColors", t "_bg", Format("{:06X}", m["bg"]))
            fgHex := IniRead(iniPath, "ActionColors", t "_fg", Format("{:06X}", m["fg"]))
            m["bg"] := Integer("0x" bgHex)
            m["fg"] := Integer("0x" fgHex)
        }
    }
}

; Farben in settings.ini speichern
SaveColorSettings() {
    global ActionTypeColors
    iniPath := A_ScriptDir "\settings.ini"
    for t, m in ActionTypeColors {
        IniWrite(Format("{:06X}", m["bg"]), iniPath, "ActionColors", t "_bg")
        IniWrite(Format("{:06X}", m["fg"]), iniPath, "ActionColors", t "_fg")
    }
}

; ─────────────────────────────────────────────
; Per-Kommentar-Farbe im Insert-Dialog wählen
; ─────────────────────────────────────────────
PickInsertCommentColor(mode) {
    global _InsertCommentBg, _InsertCommentFg, ActionTypeColors, GuiActionInsert
    cur := (mode = "bg")
        ? (_InsertCommentBg >= 0 ? _InsertCommentBg : ActionTypeColors["Comment"]["bg"])
        : (_InsertCommentFg >= 0 ? _InsertCommentFg : ActionTypeColors["Comment"]["fg"])
    ownerHwnd := IsObject(GuiActionInsert) ? GuiActionInsert.Hwnd : 0
    picked := ShowWindowsColorPicker(cur, ownerHwnd)
    if picked = -1
        return
    btnName := (mode = "bg") ? "BtnInsCommentBg" : "BtnInsCommentFg"
    if mode = "bg"
        _InsertCommentBg := picked
    else
        _InsertCommentFg := picked
    try {
        hex := CRToHex(picked)
        GuiActionInsert[btnName].Opt("Background" hex)
        GuiActionInsert[btnName].SetFont("c" (IsDark(picked) ? "FFFFFF" : "000000"))
    }
}

ResetInsertCommentColor(mode) {
    global _InsertCommentBg, _InsertCommentFg, ActionTypeColors, GuiActionInsert
    if mode = "bg" {
        _InsertCommentBg := -1
        try {
            hex := CRToHex(ActionTypeColors["Comment"]["bg"])
            GuiActionInsert["BtnInsCommentBg"].Opt("Background" hex)
            GuiActionInsert["BtnInsCommentBg"].SetFont("c" (IsDark(ActionTypeColors["Comment"]["bg"]) ? "FFFFFF" : "000000"))
        }
    } else {
        _InsertCommentFg := -1
        try {
            hex := CRToHex(ActionTypeColors["Comment"]["fg"])
            GuiActionInsert["BtnInsCommentFg"].Opt("Background" hex)
            GuiActionInsert["BtnInsCommentFg"].SetFont("c" (IsDark(ActionTypeColors["Comment"]["fg"]) ? "FFFFFF" : "000000"))
        }
    }
}

; ─────────────────────────────────────────────
; Per-Kommentar-Farbe im Edit-Dialog wählen
; ─────────────────────────────────────────────
PickEditCommentColor(mode) {
    global _EditCommentBg, _EditCommentFg, ActionTypeColors, GuiActionEdit
    cur := (mode = "bg")
        ? (_EditCommentBg >= 0 ? _EditCommentBg : ActionTypeColors["Comment"]["bg"])
        : (_EditCommentFg >= 0 ? _EditCommentFg : ActionTypeColors["Comment"]["fg"])
    ownerHwnd := IsObject(GuiActionEdit) ? GuiActionEdit.Hwnd : 0
    picked := ShowWindowsColorPicker(cur, ownerHwnd)
    if picked = -1
        return
    btnName := (mode = "bg") ? "BtnEditCommentBg" : "BtnEditCommentFg"
    if mode = "bg"
        _EditCommentBg := picked
    else
        _EditCommentFg := picked
    try {
        hex := CRToHex(picked)
        GuiActionEdit[btnName].Opt("Background" hex)
        GuiActionEdit[btnName].SetFont("c" (IsDark(picked) ? "FFFFFF" : "000000"))
    }
}

ResetEditCommentColor(mode) {
    global _EditCommentBg, _EditCommentFg, ActionTypeColors, GuiActionEdit
    if mode = "bg" {
        _EditCommentBg := -1
        try {
            hex := CRToHex(ActionTypeColors["Comment"]["bg"])
            GuiActionEdit["BtnEditCommentBg"].Opt("Background" hex)
            GuiActionEdit["BtnEditCommentBg"].SetFont("c" (IsDark(ActionTypeColors["Comment"]["bg"]) ? "FFFFFF" : "000000"))
        }
    } else {
        _EditCommentFg := -1
        try {
            hex := CRToHex(ActionTypeColors["Comment"]["fg"])
            GuiActionEdit["BtnEditCommentFg"].Opt("Background" hex)
            GuiActionEdit["BtnEditCommentFg"].SetFont("c" (IsDark(ActionTypeColors["Comment"]["fg"]) ? "FFFFFF" : "000000"))
        }
    }
}

; ─────────────────────────────────────────────
; Extras → Aktionsfarben anpassen
; ─────────────────────────────────────────────
ShowActionColorsDialog() {
    global ActionTypeColors, GuiMain

    ; Lokale Kopie für Abbrechen-Sicherheit
    localColors := Map()
    for t, m in ActionTypeColors
        localColors[t] := Map("bg", m["bg"], "fg", m["fg"])

    types  := ["Click","LongClick","Delay","Drag","Scroll","KeyPress","MouseMove","Comment","TextInput"]
    labels := ["● Mausklick","◆ Langer Klick","⏱ Zeitverzögerung","↔ Drag & Drop",
               "↕ Scrollen","⌨ Tastendruck","→ Mausbewegung","✎ Kommentar","T Text eingeben"]

    g := Gui("+AlwaysOnTop +ToolWindow Owner" GuiMain.Hwnd, "🎨 Aktionsfarben anpassen")
    g.SetFont("s9")
    g.AddText("x8 y8 w170 ", "Aktionstyp")
    g.AddText("x180 yp w90 Center", "Hintergrund")
    g.AddText("x274 yp w90 Center", "Textfarbe")
    g.AddText("x8 y+4 w356 0x10")  ; Trennlinie

    bgBtns := []
    fgBtns := []

    for i, t in types {
        g.AddText("x8 y+6 w168", labels[i])
        bgC := localColors.Has(t) ? localColors[t]["bg"] : 0xFFFFFF
        fgC := localColors.Has(t) ? localColors[t]["fg"] : 0x000000
        bb := g.AddButton("x180 yp-3 w90 h22 Background" CRToHex(bgC), "■ " CRToHex(bgC))
        bb.SetFont("c" (IsDark(bgC) ? "FFFFFF" : "000000"))
        fb := g.AddButton("x274 yp w90 h22 Background" CRToHex(fgC), "■ " CRToHex(fgC))
        fb.SetFont("c" (IsDark(fgC) ? "FFFFFF" : "000000"))
        bgBtns.Push(bb)
        fgBtns.Push(fb)

        ; Closures via factory
        bb.OnEvent("Click", MakeColorBtnHandler(g, bb, localColors, t, "bg", bgBtns, fgBtns, i))
        fb.OnEvent("Click", MakeColorBtnHandler(g, fb, localColors, t, "fg", bgBtns, fgBtns, i))
    }

    g.AddText("x8 y+12 w356 0x10")
    g.AddButton("x8 y+8 w120", "↺ Standardfarben").OnEvent("Click",
        (*) => ResetAllColorsToDefault(bgBtns, fgBtns, types, localColors))
    g.AddButton("x+8 yp w80 Default", "✔ OK").OnEvent("Click", MakeOkHandler(localColors, g))
    g.AddButton("x+8 yp w80", "✖ Abbrechen").OnEvent("Click", (*) => g.Destroy())
    g.Show("AutoSize")
}

MakeOkHandler(localColors, g) {
    handler(*) {
        global ActionTypeColors
        for t, m in localColors
            ActionTypeColors[t] := Map("bg", m["bg"], "fg", m["fg"])
        SaveColorSettings()
        UpdateActionsList()
        g.Destroy()
    }
    return handler
}

MakeColorBtnHandler(ownerGui, btn, localColors, typeKey, mode, bgBtns, fgBtns, idx) {
    handler(*) {
        ownerHwnd := IsObject(ownerGui) ? ownerGui.Hwnd : 0
        cur := localColors[typeKey][mode]
        picked := ShowWindowsColorPicker(cur, ownerHwnd)
        if picked = -1
            return
        localColors[typeKey][mode] := picked
        hex := CRToHex(picked)
        btn.Opt("Background" hex)
        btn.SetFont("c" (IsDark(picked) ? "FFFFFF" : "000000"))
        btn.Text := "■ " hex
    }
    return handler
}

ResetAllColorsToDefault(bgBtns, fgBtns, types, localColors) {
    defs := GetDefaultActionColors()
    for i, t in types {
        if !defs.Has(t)
            continue
        localColors[t] := Map("bg", defs[t]["bg"], "fg", defs[t]["fg"])
        bgHex := CRToHex(defs[t]["bg"])
        fgHex := CRToHex(defs[t]["fg"])
        bgBtns[i].Opt("Background" bgHex)
        bgBtns[i].SetFont("c" (IsDark(defs[t]["bg"]) ? "FFFFFF" : "000000"))
        bgBtns[i].Text := "■ " bgHex
        fgBtns[i].Opt("Background" fgHex)
        fgBtns[i].SetFont("c" (IsDark(defs[t]["fg"]) ? "FFFFFF" : "000000"))
        fgBtns[i].Text := "■ " fgHex
    }
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

; ─────────────────────────────────────────────
; Kopieren: Checked-Zeilen (oder rowIndex) in LVCopiedItems speichern
; ─────────────────────────────────────────────
CopyActions(LV, rowIndex) {
    global MainCurrentLV, LVCopiedItems
    if LV != MainCurrentLV
        return
    selected := GetActionsForContextMenu(LV, rowIndex)
    if !selected.Length
        return
    copies := []
    for action in selected
        copies.Push(action.Clone())
    LVCopiedItems := copies
}

; ─────────────────────────────────────────────
; Einfügen: LVCopiedItems nach rowIndex einsetzen (0 = ans Ende)
; ─────────────────────────────────────────────
PasteActionsAt(LV, rowIndex) {
    global ActionsList, LVCopiedItems, MainCurrentLV, IsRecording
    if IsRecording || LV != MainCurrentLV || !LVCopiedItems.Length
        return
    if rowIndex < 0 || rowIndex > ActionsList.Length
        return
    insertPos := rowIndex ? rowIndex + 1 : ActionsList.Length + 1
    PushUndo()
    for action in LVCopiedItems {
        ActionsList.InsertAt(insertPos, action.Clone())
        insertPos++
    }
    UpdateActionsList()
}

; Eintrag duplizieren (nach der aktuellen Zeile einfügen)
DuplicateAction(rowIndex) {
    global ActionsList
    if rowIndex < 1 || rowIndex > ActionsList.Length
        return
    orig := ActionsList[rowIndex]
    copy := Map()
    for k, v in orig
        copy[k] := v
    PushUndo()
    ActionsList.InsertAt(rowIndex + 1, copy)
    UpdateActionsList(rowIndex + 1)
}

; Alle selektierten Einträge duplizieren (Mehrfachauswahl)
DuplicateSelected(LV) {
    global ActionsList, MainCurrentLV, IsRecording
    if IsRecording || LV != MainCurrentLV
        return
    state := LV.GetNext(0, "Checked") ? "Checked" : ""
    indices := []
    row := 0
    loop {
        row := LV.GetNext(row, state)
        if !row
            break
        indices.Push(row)
    }
    if indices.Length = 0
        return
    PushUndo()
    ; Von hinten nach vorne einfügen, damit Indizes stabil bleiben
    i := indices.Length
    while i >= 1 {
        orig := ActionsList[indices[i]]
        copy := Map()
        for k, v in orig
            copy[k] := v
        ActionsList.InsertAt(indices[i] + 1, copy)
        i--
    }
    UpdateActionsList()
}

; Alle Einträge löschen
DelAllActions() {
    global IsRecording, ActionsList, MainAllTabs, MainCurrentTab
    if IsRecording || !ActionsList.Length
        return
    source := ActionsList
    confirmedRows := source.Clone()
    if ShowYesNo("Alle " confirmedRows.Length " Aktionen löschen?") != "Yes"
        return
    if IsRecording || ActionsList != source
        return
    if source.Length != confirmedRows.Length {
        ShowWarning("Die Liste hat sich geändert. Bitte erneut bestätigen.")
        return
    }
    for index, action in confirmedRows {
        if source[index] != action {
            ShowWarning("Die Liste hat sich geändert. Bitte erneut bestätigen.")
            return
        }
    }
    PushUndo()
    ActionsList := []
    MainAllTabs[MainCurrentTab] := ActionsList
    UpdateActionsList()
}

; Zeile per Kontextmenü verschieben
MoveActionRow(rowIndex, direction) {
    global ActionsList, MainCurrentLV
    newIndex := rowIndex + direction
    if rowIndex < 1 || rowIndex > ActionsList.Length || newIndex < 1 || newIndex > ActionsList.Length || newIndex = rowIndex
        return
    PushUndo()
    tmp                    := ActionsList[newIndex]
    ActionsList[newIndex]  := ActionsList[rowIndex]
    ActionsList[rowIndex]  := tmp
    UpdateActionsList()
    if IsObject(MainCurrentLV)
        MainCurrentLV.Modify(newIndex, "Select Focus Vis")
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

OnChkOptimize(*) {
    global OptimizeClicks, GuiMain, MenuRecordRef
    OptimizeClicks := GuiMain["ChkOptimize"].Value
    if IsObject(MenuRecordRef) {
        if OptimizeClicks {
            MenuRecordRef.Check("Klicks zusammenfassen")
        } else {
            MenuRecordRef.Uncheck("Klicks zusammenfassen")
        }
    }
}

; ─────────────────────────────────────────────
UpdateGui() {
    global GuiMain, LastDelay, RepeatMode, IsRecording, ActionsList
    global BtnsDisableOnRecord, BtnsAllowedOnRecord, OriginalBtnText
    global _LastRecordingState
    global StartRecordingBtn, InsertBtn, SaveBtn, LoadBtn, PlayOnceBtn, ToggleRepeatBtn
    global MenuFileRef, MenuEditRef, MenuRecordRef, MenuPlayRef
    global LastActionTime, LastClickX, LastClickY, LastPlaybackAction, IsReplaying
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
    if (IsRecording || IsReplaying) && LastActionTime > 0 {
        elapsed := (A_TickCount - LastActionTime) & 0xFFFFFFFF
        try GuiMain["DelayDisplay"].Value := "Zeit seit letzter Aktion: " elapsed " ms"
    } else {
        try GuiMain["DelayDisplay"].Value := "Zeit seit letzter Aktion: --"
    }

    if IsReplaying {
        try GuiMain["LastAction"].Value := "Letzte Aktion: " (IsObject(LastPlaybackAction) ? FormatActionShort(LastPlaybackAction) : "--")
    } else if IsObject(ActionsList) && ActionsList.Length > 0 {
        try GuiMain["LastAction"].Value := "Letzte Aktion: " FormatActionShort(ActionsList[ActionsList.Length])
    } else {
        try GuiMain["LastAction"].Value := "Letzte Aktion: --"
    }

    ; Bildschirmgrenzen (statisch, einmalig gesetzt)
    try GuiMain["ScreenBounds"].Value := "Auflösung: " . (ScreenXMax - 1) . " x " . (ScreenYMax - 1)

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
    return Integer(Max(ScreenXMin, Min(ScreenXMax - 1, Float(v))))
}
ClampY(v) {
    global ScreenYMin, ScreenYMax
    return Integer(Max(ScreenYMin, Min(ScreenYMax - 1, Float(v))))
}

; Kurzdarstellung einer Aktion für die Status-Box
; ─────────────────────────────────────────────
AddScrollPositionFields(dialog, prefix, action, left := 8) {
    global ScreenXMin, ScreenYMin, ScreenXMax, ScreenYMax
    MouseGetPos(&x, &y)
    dialog.AddCheckBox("x" left " y+8 v" prefix "ScrollFixed Checked" HasScrollPosition(action), "Feste Scrollposition verwenden")
    dialog.AddText("x" left " y+6", "X")
    dialog.AddEdit("x+5 yp-2 v" prefix "ScrollX w80", action.Get("X", x))
    dialog.AddText("x+10 yp+2", "Y")
    dialog.AddEdit("x+5 yp-2 v" prefix "ScrollY w80", action.Get("Y", y))
    dialog.AddText("x" left " y+4 w260 cGray", "X: " ScreenXMin " bis " (ScreenXMax - 1) "   Y: " ScreenYMin " bis " (ScreenYMax - 1))
}

SaveScrollPosition(dialog, prefix, action) {
    if !dialog[prefix "ScrollFixed"].Value {
        for axis in ["X", "Y"] {
            if action.Has(axis)
                action.Delete(axis)
        }
        return true
    }
    x := dialog[prefix "ScrollX"].Value
    y := dialog[prefix "ScrollY"].Value
    if !IsInteger(x) || !IsInteger(y) {
        ShowWarning("Bitte ganze Zahlen für X und Y eingeben.")
        return false
    }
    action["X"] := ClampX(x)
    action["Y"] := ClampY(y)
    return true
}

HasScrollPosition(action) {
    return action.Has("X") && action.Has("Y")
}

ScrollPositionSuffix(action) {
    return HasScrollPosition(action) ? "  X=" action["X"] " Y=" action["Y"] : ""
}

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
UpdateActionsList(scrollTo := 0, previousAction := unset, replacementAction := unset) {
    RefreshScreenProfileUI()
    global GuiMain, ActionsList, LVRowColors, IsRecording, MainCurrentLV
    if !IsObject(MainCurrentLV)
        return
    LV := MainCurrentLV

    ; Aktuelle Scroll-Position merken (LVM_GETTOPINDEX = 0x1027)
    topIndex := SendMessage(0x1027, 0, 0, LV.Hwnd)

    static displayedActions := Map()
    previous := displayedActions.Get(LV.Hwnd, [])
    checked := Map()
    row := 0
    while row := LV.GetNext(row, "Checked") {
        if row <= previous.Length
            checked[previous[row]] := true
    }
    if IsSet(previousAction) && checked.Has(previousAction)
        checked[replacementAction] := true
    displayed := []
    displayedActions[LV.Hwnd] := displayed

    LV.Delete()
    LVRowColors := Map()

    if !(IsObject(ActionsList) && ActionsList.Length > 0)
        return

    maxIndex := ActionsList.Length
    digits   := StrLen(maxIndex)

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

        if type = "Click" {
            cntNum   := a.Has("Count")      ? a["Count"]      : 1
            delayNum := a.Has("ClickDelay") ? a["ClickDelay"] : 0
            cntTxt   := (cntNum > 1) ? " (" cntNum " mal)" : ""
            valTxt   := "X=" a["X"] " Y=" a["Y"]
            if cntNum > 1
                valTxt .= "  " cntNum "x"
            if a.Has("ClickTiming")
                valTxt .= "  variable Abstände"
            else if delayNum > 0
                valTxt .= "  " delayNum "ms"
            label := (cntNum > 1) ? "●● " : s
            LV.Add("", "", displayIndex, label bLbl "klick" cntTxt, valTxt)
        }
        else if type = "LongClick"
            LV.Add("", "", displayIndex, s "Langer Klick (" bLbl ")", "X=" a["X"] " Y=" a["Y"] "  " a["Duration"] " ms")
        else if type = "Delay"
            LV.Add("", "", displayIndex, s "Zeitverzögerung", a["Time"] " ms")
        else if type = "Drag"
            LV.Add("", "", displayIndex, s "Drag (" bLbl ")", "X1=" a["X1"] " Y1=" a["Y1"] " -> X2=" a["X2"] " Y2=" a["Y2"])
        else if type = "Scroll"
            LV.Add("", "", displayIndex, s "Scrollen", (a["Direction"]="Up" ? "Hoch" : "Runter") " x " a["Amount"] ScrollPositionSuffix(a))
        else if type = "KeyPress"
            LV.Add("", "", displayIndex, s "Taste", a["Key"])
        else if type = "MouseMove"
            LV.Add("", "", displayIndex, s "Mausbewegung", "X=" a["X"] " Y=" a["Y"])
        else if type = "Comment"
            LV.Add("", "", displayIndex, s "Kommentar", a["Text"])
        else if type = "TextInput"
            LV.Add("", "", displayIndex, s "Text eingeben", a["Text"])
        else
            LV.Add("", "", displayIndex, type, "")

        bgC := ActionTypeColors.Has(type) ? ActionTypeColors[type]["bg"] : 0xFFFFFF
        fgC := ActionTypeColors.Has(type) ? ActionTypeColors[type]["fg"] : 0x000000
        if type = "Comment" && IsObject(a) && a is Map {
            if a.Has("BgColor")   && a["BgColor"]   >= 0
                bgC := a["BgColor"]
            if a.Has("TextColor") && a["TextColor"]  >= 0
                fgC := a["TextColor"]
        }
        LVRowColors[rowNum] := Map("bg", bgC, "fg", fgC)
        displayed.Push(a)
        if checked.Has(a)
            LV.Modify(rowNum, "Check")
    }

    ; Spaltenbreiten automatisch an Inhalt anpassen.
    ; Checkbox-Spalte (1) bleibt fix; alle anderen richten sich nach
    ; dem breitesten Wert (inkl. Spaltenüberschrift).
    LV.ModifyCol(1, "26")
    LV.ModifyCol(2, "AutoHdr")
    LV.ModifyCol(3, "AutoHdr")
    LV.ModifyCol(4, "AutoHdr")

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
    } else if topIndex > 0 {
        visibleRows := Max(1, SendMessage(0x1028, 0, 0, LV.Hwnd))  ; LVM_GETCOUNTPERPAGE
        bottomIndex := Min(topIndex + visibleRows - 1, rowCount - 1)
        SendMessage(0x1013, bottomIndex, 0, LV.Hwnd)  ; LVM_ENSUREVISIBLE
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
    global MainCurrentLV
    if !IsObject(MainCurrentLV)
        return
    if MainCurrentLV.GetCount() > 0
        MainCurrentLV.Modify(1, "Vis Select Focus")
}

LVScrollToBottom() {
    global MainCurrentLV
    if !IsObject(MainCurrentLV)
        return
    n := MainCurrentLV.GetCount()
    if n > 0
        MainCurrentLV.Modify(n, "Vis Select Focus")
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

    if !IsSet(GuiMain) || !IsObject(GuiMain)
        return
    global MainCurrentLV, MainLVHwnds
    if !IsObject(MainCurrentLV)
        return

    hwndFrom := NumGet(lParam, 0, "Ptr")
    isMainLV := false
    for h in MainLVHwnds {
        if hwndFrom = h {
            isMainLV := true
            break
        }
    }
    if !isMainLV
        return
    LV := MainCurrentLV

    code := NumGet(lParam, 16, "Int")
    if code != NM_CUSTOMDRAW
        return

    dwDrawStage := NumGet(lParam, 24, "UInt")

    if dwDrawStage = CDDS_PREPAINT
        return CDRF_NOTIFYITEMDRAW

    if dwDrawStage = CDDS_ITEMPREPAINT {
        dwItemSpec := NumGet(lParam, 56, "Ptr")
        row := Integer(dwItemSpec) + 1

        ; Gezogene Zeile: orange mit weißem Text (höchste Priorität)
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

        needReturn := false

        global ActionsList
        if IsObject(ActionsList) && row >= 1 && row <= ActionsList.Length {
            a := ActionsList[row]

            ; Mehrfach-Klick (Count > 1): fette Schrift
            if IsObject(a) && a.Has("Type") && a["Type"] = "Click"
                && a.Has("Count") && a["Count"] > 1 {
                static hBoldFont := 0
                hdc := NumGet(lParam, 32, "Ptr")
                if hBoldFont = 0 {
                    hCurFont := DllCall("GetCurrentObject", "Ptr", hdc, "UInt", 6, "Ptr")
                    lf := Buffer(92, 0)
                    DllCall("GetObject", "Ptr", hCurFont, "Int", 92, "Ptr", lf.Ptr)
                    NumPut("Int", 700, lf.Ptr, 16)   ; lfWeight = FW_BOLD
                    hBoldFont := DllCall("CreateFontIndirectW", "Ptr", lf.Ptr, "Ptr")
                }
                if hBoldFont
                    DllCall("SelectObject", "Ptr", hdc, "Ptr", hBoldFont)
                needReturn := true
            }
        }

        if LVRowColors.Has(row) {
            clrs := LVRowColors[row]
            NumPut("UInt", clrs["fg"], lParam, 80)  ; clrText
            NumPut("UInt", clrs["bg"], lParam, 84)  ; clrTextBk
            needReturn := true
        }

        if needReturn
            return CDRF_NEWFONT
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
    global GuiMain, LVDragRow, LVDragging, MainCurrentLV, MainLVHwnds
    static LVN_BEGINDRAG := -109

    if !IsSet(GuiMain) || !IsObject(GuiMain)
        return
    if !IsObject(MainCurrentLV)
        return

    hwndFrom := NumGet(lParam, 0, "Ptr")
    isMainLV := false
    for h in MainLVHwnds {
        if hwndFrom = h {
            isMainLV := true
            break
        }
    }
    if !isMainLV
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
    global GuiMain, ActionsList, LVDragRow, LVDragTargetRow, LVDragging, MainCurrentLV

    if !LVDragging
        return

    LV := MainCurrentLV
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
AddAction(replacements := Map()) {
    global ActionsList, GuiActionInsert
    global ScreenXMin, ScreenYMin, ScreenXMax, ScreenYMax

    if IsObject(GuiActionInsert) {
        GuiActionInsert.Show()
        return false
    }
    GuiActionInsert := Gui("+ToolWindow +AlwaysOnTop", "+ Aktion hinzufügen")
    global _InsertCommentBg, _InsertCommentFg
    _InsertCommentBg := -1
    _InsertCommentFg := -1
    GuiActionInsert.SetFont("s9")

    ; Einfügeposition oben
    GuiActionInsert.AddText("x8 y8", "Einfügen an Position:")
    GuiActionInsert.AddEdit("x+6 yp-2 vInsertIndex w50", ActionsList.Length + 1)
    GuiActionInsert.AddText("x+4 yp+2 cGray", "(1 = ganz oben)")

    ; Tab-Control
    tabs := GuiActionInsert.AddTab3("x8 y+8 w360 h295 vActionTab",
        ["Mausklick", "Delay", "Drag", "Scrollen", "Langer Klick", "Kommentar", "Text", "Taste"])
    GuiActionInsert.SetFont("s9")

    ; ── Tab 1: Mausklick ──
    tabs.UseTab(1)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Klickt einmal an einer Bildschirmposition.")
    GuiActionInsert.AddCheckBox("x20 y+8 vUseCurrentPos", "Aktuelle Mausposition verwenden")
        .OnEvent("Click", (*) => OnUseCurrentPosClick())
    GuiActionInsert.AddText("x20 y+8", "X-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vPosX w70")
    GuiActionInsert.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
    GuiActionInsert.AddText("x20 y+8", "Y-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vPosY w70")
    GuiActionInsert.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
    GuiActionInsert.AddText("x20 y+8", "Maustaste:")
    dd1 := GuiActionInsert.AddDropDownList("x+6 yp-2 vClickBtn w100", ["Links", "Rechts"])
    dd1.Value := 1

    ; ── Weitere Einstellungen (Mausklick) ──
    GuiActionInsert.AddGroupBox("x12 y+12 w336 h68 Section", "Weitere Einstellungen")
    GuiActionInsert.AddCheckBox("xs+8 ys+16 vMultiClick", "Mehrere Klicks?")
        .OnEvent("Click", ToggleInsertClickFields)
    GuiActionInsert.AddText("xs+140 ys+18", "Anzahl:")
    GuiActionInsert.AddEdit("x+5 yp-2 vClickCount w38 Disabled", "2")
    GuiActionInsert.AddText("xs+8 ys+42", "Verzögerung für Klicks:")
    GuiActionInsert.AddEdit("x+5 yp-2 vClickDelay w50 Disabled", "0")
    GuiActionInsert.AddText("x+3 yp+2 cGray", "ms")

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
    GuiActionInsert.AddText("x20 y+2 cGray", "(X: " . ScreenXMin . "-" . (ScreenXMax - 1) . " | Y: " . ScreenYMin . "-" . (ScreenYMax - 1) . ")")
    GuiActionInsert.AddText("x20 y+8", "Ziel  X2:")
    GuiActionInsert.AddEdit("x+6 yp-2 vDragX2 w70")
    GuiActionInsert.AddText("x+8 yp+2", "Y2:")
    GuiActionInsert.AddEdit("x+4 yp-2 vDragY2 w70")
    GuiActionInsert.AddText("x20 y+2 cGray", "(X: " . ScreenXMin . "-" . (ScreenXMax - 1) . " | Y: " . ScreenYMin . "-" . (ScreenYMax - 1) . ")")

    ; ── Tab 4: Scrollen ──
    tabs.UseTab(4)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Dreht das Mausrad an der aktuellen Position.")
    GuiActionInsert.AddText("x20 y+20", "Richtung:")
    dd4 := GuiActionInsert.AddDropDownList("x+6 yp-2 vScrollDir w100", ["Hoch", "Runter"])
    dd4.Value := 1
    GuiActionInsert.AddText("x20 y+8", "Anzahl Schritte:")
    GuiActionInsert.AddEdit("x+6 yp-2 vScrollAmount w60", "3")
    AddScrollPositionFields(GuiActionInsert, "Insert", Map(), 20)

    ; ── Tab 5: Langer Klick ──
    tabs.UseTab(5)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Maustaste halten ohne Bewegung.")
    GuiActionInsert.AddText("x20 y+18", "X-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vLongX w70")
    GuiActionInsert.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
    GuiActionInsert.AddText("x20 y+8", "Y-Koordinate:")
    GuiActionInsert.AddEdit("x+6 yp-2 vLongY w70")
    GuiActionInsert.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
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
    GuiActionInsert.AddText("x20 y+12", "Hintergrundfarbe:")
    GuiActionInsert.AddButton("x+8 yp-2 w80 h22 vBtnInsCommentBg", "■ wählen")
        .OnEvent("Click", (*) => PickInsertCommentColor("bg"))
    GuiActionInsert.AddButton("x+4 yp w52 h22", "Standard")
        .OnEvent("Click", (*) => ResetInsertCommentColor("bg"))
    GuiActionInsert.AddText("x20 y+6", "Textfarbe:")
    GuiActionInsert.AddButton("x+8 yp-2 w80 h22 vBtnInsCommentFg", "■ wählen")
        .OnEvent("Click", (*) => PickInsertCommentColor("fg"))
    GuiActionInsert.AddButton("x+4 yp w52 h22", "Standard")
        .OnEvent("Click", (*) => ResetInsertCommentColor("fg"))

    ; ── Tab 7: Text eingeben ──
    tabs.UseTab(7)
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Sendet Text an das aktive Fenster (z.B. für Textfelder).")
    GuiActionInsert.AddText("x20 y+10 w320 cGray", "Sonderzeichen werden korrekt übertragen.")
    GuiActionInsert.AddText("x20 y+16", "Einzugebender Text:")
    GuiActionInsert.AddEdit("x20 y+4 vTextInput w320 h60 Multi")

    ; ── Tab 8: Tastendruck ──
    tabs.UseTab(8)
    GuiActionInsert.AddText("x20 y+10 w320 cGray",
        "Sendet einen einzelnen Tastendruck an die aktive Anwendung.")
    GuiActionInsert.AddText("x20 y+20 w320 cGray",
        "Klicke den Button und drücke dann die gewünschte Taste.")

    GuiActionInsert.AddButton("x20 y+14 w200 h32 vBtnRecordKey", "⌨  Taste jetzt drücken")
        .OnEvent("Click", (*) => RecordActionKey(GuiActionInsert, "KeyEdit", "BtnRecordKey"))

    GuiActionInsert.AddEdit("x20 y+10 w200 vKeyEdit")
    GuiActionInsert.AddText("x20 y+4 w320 cGray",
        "Oder manuell im AHK-Format eingeben:`n"
        "  {Enter}  {Tab}  {F5}  {Delete}`n"
        "  ^c = Strg+C   !{F4} = Alt+F4   +{Tab} = Umschalt+Tab")

    tabs.UseTab()  ; zurück zu keinem Tab

    ; Explizite Y-Position nach dem Tab-Control berechnen
    tabs.GetPos(, &tabY, , &tabH)
    btnY := tabY + tabH + 8

    sourceList := ActionsList
    insertDialog := GuiActionInsert
    ; OK / Abbrechen
    GuiActionInsert.AddButton("x8 y" btnY " w80 Default", "OK")
        .OnEvent("Click", (*) => InsertConfirm(insertDialog, sourceList, replacements))
    GuiActionInsert.AddButton("x+6 yp w80", "Abbrechen")
        .OnEvent("Click",  (*) => InsertCancel())
    GuiActionInsert.OnEvent("Close",  (*) => InsertCancel())
    GuiActionInsert.OnEvent("Escape", (*) => InsertCancel())

    GuiActionInsert.Show()
    return true
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
PointInControl(control, x, y) {
    rect := Buffer(16)
    if !DllCall("User32\GetWindowRect", "Ptr", control.Hwnd, "Ptr", rect, "Int")
        return false
    return x >= NumGet(rect, 0, "Int") && x < NumGet(rect, 8, "Int")
        && y >= NumGet(rect, 4, "Int") && y < NumGet(rect, 12, "Int")
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
    if GetKeyState("LButton", "P") || GetKeyState("RButton", "P") {
        if !PointInControl(ctrl, x, y) {
            GuiActionInsert["UseCurrentPos"].Value := false
            SetTimer(UpdateInsertMousePos, 0)
            ToolTip()
        }
    }
}

; ─────────────────────────────────────────────
; Mausposition live im Edit-Dialog übernehmen
; ─────────────────────────────────────────────
OnUseCurrentPosEditClick(*) {
    global GuiActionEdit
    if !IsObject(GuiActionEdit)
        return
    if GuiActionEdit["UseCurrentPosEdit"].Value
        SetTimer(UpdateEditMousePos, 50)
    else {
        SetTimer(UpdateEditMousePos, 0)
        ToolTip()
    }
}

OnUseCurrentPosEdit1Click(*) {
    global GuiActionEdit
    if !IsObject(GuiActionEdit)
        return
    if GuiActionEdit["UseCurrentPosEdit1"].Value
        SetTimer(UpdateEditMousePos, 50)
    else {
        SetTimer(UpdateEditMousePos, 0)
        ToolTip()
    }
}

OnUseCurrentPosEdit2Click(*) {
    global GuiActionEdit
    if !IsObject(GuiActionEdit)
        return
    if GuiActionEdit["UseCurrentPosEdit2"].Value
        SetTimer(UpdateEditMousePos, 50)
    else {
        SetTimer(UpdateEditMousePos, 0)
        ToolTip()
    }
}

UpdateEditMousePos(*) {
    global GuiActionEdit
    if !IsObject(GuiActionEdit) {
        SetTimer(UpdateEditMousePos, 0)
        ToolTip()
        return
    }

    MouseGetPos(&mx, &my)
    anyActive := false

    ; ── Einzelposition (Click / LongClick / MouseMove) ──
    try {
        if GuiActionEdit["UseCurrentPosEdit"].Value {
            anyActive := true
            GuiActionEdit["EditX"].Value := mx
            GuiActionEdit["EditY"].Value := my
            ctrl := GuiActionEdit["UseCurrentPosEdit"]
            if GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
                if !PointInControl(ctrl, mx, my) {
                    GuiActionEdit["UseCurrentPosEdit"].Value := false
                    anyActive := false
                }
        }
    }

    ; ── Drag Startposition ──
    try {
        if GuiActionEdit["UseCurrentPosEdit1"].Value {
            anyActive := true
            GuiActionEdit["EditX1"].Value := mx
            GuiActionEdit["EditY1"].Value := my
            ctrl := GuiActionEdit["UseCurrentPosEdit1"]
            if GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
                if !PointInControl(ctrl, mx, my) {
                    GuiActionEdit["UseCurrentPosEdit1"].Value := false
                    anyActive := false
                }
        }
    }

    ; ── Drag Zielposition ──
    try {
        if GuiActionEdit["UseCurrentPosEdit2"].Value {
            anyActive := true
            GuiActionEdit["EditX2"].Value := mx
            GuiActionEdit["EditY2"].Value := my
            ctrl := GuiActionEdit["UseCurrentPosEdit2"]
            if GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
                if !PointInControl(ctrl, mx, my) {
                    GuiActionEdit["UseCurrentPosEdit2"].Value := false
                    anyActive := false
                }
        }
    }

    if anyActive
        ToolTip("X=" mx "  Y=" my "  — Klick zum Übernehmen", mx + 20, my + 20)
    else {
        SetTimer(UpdateEditMousePos, 0)
        ToolTip()
    }
}

; ─────────────────────────────────────────────
DelAction(*) {
    global IsRecording, ActionsList, MainCurrentLV
    if IsRecording || !IsObject(MainCurrentLV)
        return

    lv := MainCurrentLV
    state := lv.GetNext(0, "Checked") ? "Checked" : ""
    rows := Map()
    row := 0
    while row := lv.GetNext(row, state) {
        if row <= ActionsList.Length
            rows[row] := true
    }

    if !rows.Count {
        DelAllActions()
        return
    }

    PushUndo()
    RemoveMatchingActions(ActionsList, (action, index) => rows.Has(index))
    UpdateActionsList()
}

RemoveMatchingActions(actions, shouldRemove) {
    nextIndex := 1
    for index, action in actions {
        if shouldRemove.Call(action, index)
            continue
        actions[nextIndex] := action
        nextIndex++
    }
    actions.Length := nextIndex - 1
}

; ─────────────────────────────────────────────
EditAction(LV, rowIndex) {
    global ActionsList, GuiActionEdit
    global ScreenXMin, ScreenYMin, ScreenXMax, ScreenYMax

    if IsObject(GuiActionEdit) {
        GuiActionEdit.Show()
        return
    }

    if rowIndex = 0 || rowIndex > ActionsList.Length
        return

    a    := ActionsList[rowIndex]
    if !(IsObject(a) && a is Map && a.Has("Type"))
        return

    type := a["Type"]
    btn  := a.Has("Button") ? a["Button"] : "Left"

    GuiActionEdit := Gui("+ToolWindow +AlwaysOnTop", "Aktion bearbeiten")
    GuiActionEdit.SetFont("s9")
    GuiActionEdit.OnEvent("Close",  (*) => StopEditMousePosAndDestroy())
    GuiActionEdit.OnEvent("Escape", (*) => StopEditMousePosAndDestroy())

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
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Horizontale Position in Pixeln (0 = linker Bildschirmrand).")
        GuiActionEdit.AddText("y+8", "Y-Koordinate:")
        GuiActionEdit.AddEdit("vEditY w80", a["Y"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Vertikale Position in Pixeln (0 = oberer Bildschirmrand).")
        GuiActionEdit.AddCheckBox("x8 y+8 vUseCurrentPosEdit", "Aktuelle Mausposition verwenden")
            .OnEvent("Click", (*) => OnUseCurrentPosEditClick())
        ; ── Weitere Einstellungen ──
        editCnt   := a.Has("Count")      ? a["Count"]      : 1
        editDelay := a.Has("ClickTiming") ? "" : a.Get("ClickDelay", 0)
        GuiActionEdit.AddGroupBox("x8 y+10 w260 h" (a.Has("ClickTiming") ? 91 : 68) " Section", "Weitere Einstellungen")
        GuiActionEdit.AddText("xs+8 ys+18", "Anzahl:")
        GuiActionEdit.AddEdit("x+5 yp-2 vEditCount w50", editCnt)
        GuiActionEdit.AddText("xs+8 ys+42", "Verzögerung für Klicks:")
        GuiActionEdit.AddEdit("x+5 yp-2 vEditClickDelay w50", editDelay)
        GuiActionEdit.AddText("x+3 yp+2 cGray", "ms")
        if a.Has("ClickTiming")
            GuiActionEdit.AddText("xs+8 ys+66 w246 cGray", "Leer lassen für individuelle Abstände.")

    } else if type = "LongClick" {
        GuiActionEdit.AddText("w260 cBlue", "Langer Klick")
        GuiActionEdit.AddText("w260 y+2 cGray", "Maustaste wird gedrückt gehalten und dann losgelassen.")
        GuiActionEdit.AddText("y+8", "Maustaste:")
        dd := GuiActionEdit.AddDropDownList("vEditBtn w120", ["Links", "Rechts"])
        dd.Value := (btn = "Right") ? 2 : 1
        GuiActionEdit.AddText("y+2 w260 cGray", "Welche Maustaste gehalten wird.")
        GuiActionEdit.AddText("y+8", "X-Koordinate:")
        GuiActionEdit.AddEdit("vEditX w80", a["X"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Horizontale Position in Pixeln.")
        GuiActionEdit.AddText("y+8", "Y-Koordinate:")
        GuiActionEdit.AddEdit("vEditY w80", a["Y"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Vertikale Position in Pixeln.")
        GuiActionEdit.AddCheckBox("x8 y+8 vUseCurrentPosEdit", "Aktuelle Mausposition verwenden")
            .OnEvent("Click", (*) => OnUseCurrentPosEditClick())
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
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+8", "Startposition Y1:")
        GuiActionEdit.AddEdit("vEditY1 w80", a["Y1"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Wo der Drag beginnt (Maustaste wird hier gedrückt).")
        GuiActionEdit.AddCheckBox("x8 y+6 vUseCurrentPosEdit1", "Aktuelle Position als Startpunkt")
            .OnEvent("Click", (*) => OnUseCurrentPosEdit1Click())
        GuiActionEdit.AddText("y+8", "Zielposition X2:")
        GuiActionEdit.AddEdit("vEditX2 w80", a["X2"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+8", "Zielposition Y2:")
        GuiActionEdit.AddEdit("vEditY2 w80", a["Y2"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Wo der Drag endet (Maustaste wird hier losgelassen).")
        GuiActionEdit.AddCheckBox("x8 y+6 vUseCurrentPosEdit2", "Aktuelle Position als Zielpunkt")
            .OnEvent("Click", (*) => OnUseCurrentPosEdit2Click())

    } else if type = "Scroll" {
        GuiActionEdit.AddText("w260 cBlue", "Scrollen")
        GuiActionEdit.AddText("w260 y+2 cGray", HasScrollPosition(a)
            ? "Gespeicherte Position:" ScrollPositionSuffix(a)
            : "Dreht das Mausrad an der aktuellen Mausposition.")
        GuiActionEdit.AddText("y+8", "Richtung:")
        dd := GuiActionEdit.AddDropDownList("vEditScrollDir w120", ["Hoch", "Runter"])
        dd.Value := (a["Direction"] = "Up") ? 1 : 2
        GuiActionEdit.AddText("y+2 w260 cGray", "Hoch = Seite nach oben scrollen, Runter = nach unten.")
        GuiActionEdit.AddText("y+8", "Anzahl Schritte:")
        GuiActionEdit.AddEdit("vEditScrollAmount w80", a["Amount"])
        GuiActionEdit.AddText("y+2 w260 cGray", "Wie viele Mausrad-Klicks ausgeführt werden (1-20 typisch).")
        AddScrollPositionFields(GuiActionEdit, "Edit", a)

    } else if type = "KeyPress" {
        GuiActionEdit.AddText("w260 cBlue", "Tastendruck")
        GuiActionEdit.AddText("w260 y+2 cGray", "Sendet einen Tastendruck an die aktive Anwendung.")
        GuiActionEdit.AddText("y+8", "Taste (AHK-Format):")
        GuiActionEdit.AddEdit("vEditKey w160", a["Key"])
        GuiActionEdit.AddButton("x+6 yp vBtnEditRecordKey", "Taste erfassen")
            .OnEvent("Click", (button, *) => RecordActionKey(button.Gui, "EditKey", "BtnEditRecordKey"))
        GuiActionEdit.AddText("y+2 w260 cGray", "Beispiele:  {Enter}  {Tab}  {F5}  ^c (Strg+C)  !{F4} (Alt+F4)")

    } else if type = "MouseMove" {
        GuiActionEdit.AddText("w260 cBlue", "Mausbewegung")
        GuiActionEdit.AddText("w260 y+2 cGray", "Bewegt den Mauszeiger ohne zu klicken.")
        GuiActionEdit.AddText("y+8", "X-Koordinate:")
        GuiActionEdit.AddEdit("vEditX w80", a["X"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenXMin . " | max " . (ScreenXMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Horizontale Zielposition in Pixeln.")
        GuiActionEdit.AddText("y+8", "Y-Koordinate:")
        GuiActionEdit.AddEdit("vEditY w80", a["Y"])
        GuiActionEdit.AddText("x+4 yp+2 cGray", "(min " . ScreenYMin . " | max " . (ScreenYMax - 1) . ")")
        GuiActionEdit.AddText("x8 y+2 w260 cGray", "Vertikale Zielposition in Pixeln.")
        GuiActionEdit.AddCheckBox("x8 y+8 vUseCurrentPosEdit", "Aktuelle Mausposition verwenden")
            .OnEvent("Click", (*) => OnUseCurrentPosEditClick())

    } else if type = "Comment" {
        GuiActionEdit.AddText("w260 cBlue", "Kommentar")
        GuiActionEdit.AddText("w260 y+2 cGray", "Nur zur Beschriftung - wird bei Wiedergabe übersprungen.")
        GuiActionEdit.AddText("y+8", "Kommentartext:")
        GuiActionEdit.AddEdit("vEditCommentText w220", a["Text"])
        ; Per-Kommentar-Farben initialisieren
        global _EditCommentBg, _EditCommentFg
        _EditCommentBg := (a.Has("BgColor")   && a["BgColor"]   >= 0) ? a["BgColor"]   : -1
        _EditCommentFg := (a.Has("TextColor") && a["TextColor"]  >= 0) ? a["TextColor"]  : -1
        initBgHex := CRToHex(_EditCommentBg >= 0 ? _EditCommentBg : ActionTypeColors["Comment"]["bg"])
        initFgHex := CRToHex(_EditCommentFg >= 0 ? _EditCommentFg : ActionTypeColors["Comment"]["fg"])
        GuiActionEdit.AddText("x8 y+10", "Hintergrundfarbe:")
        GuiActionEdit.AddButton("x+8 yp-2 w80 h22 vBtnEditCommentBg Background" initBgHex, "■ wählen")
            .OnEvent("Click", (*) => PickEditCommentColor("bg"))
        GuiActionEdit.AddButton("x+4 yp w52 h22", "Standard")
            .OnEvent("Click", (*) => ResetEditCommentColor("bg"))
        GuiActionEdit.AddText("x8 y+6", "Textfarbe:")
        GuiActionEdit.AddButton("x+8 yp-2 w80 h22 vBtnEditCommentFg Background" initFgHex, "■ wählen")
            .OnEvent("Click", (*) => PickEditCommentColor("fg"))
        GuiActionEdit.AddButton("x+4 yp w52 h22", "Standard")
            .OnEvent("Click", (*) => ResetEditCommentColor("fg"))

    } else if type = "TextInput" {
        GuiActionEdit.AddText("w260 cBlue", "Text eingeben")
        GuiActionEdit.AddText("w260 y+2 cGray", "Sendet Text an das aktive Fenster (Textfelder ausfüllen).")
        GuiActionEdit.AddText("y+8", "Einzugebender Text:")
        GuiActionEdit.AddEdit("vEditTextInput w260 h80 Multi", a["Text"])

    } else {
        GuiActionEdit.AddText(, "Dieser Typ ist nicht editierbar.")
        GuiActionEdit.AddButton("w80", "Schliessen").OnEvent("Click", (*) => StopEditMousePosAndDestroy())
        GuiActionEdit.Show()
        return
    }

    GuiActionEdit.AddText("x8 y+12", "Position in der Liste:")
    GuiActionEdit.AddEdit("x+6 yp-2 vEditPosition w50", rowIndex)
    GuiActionEdit.AddText("x+4 yp+2 cGray", "(1 – " ActionsList.Length ")")

    GuiActionEdit.AddText("y+10", "")
    sourceList := ActionsList
    editDialog := GuiActionEdit
    editDialog.AddButton("w80 Default", "OK").OnEvent("Click",
        (*) => EditConfirm(editDialog, rowIndex, type, sourceList, a))
    GuiActionEdit.AddButton("w80", "Abbrechen").OnEvent("Click",
        (*) => StopEditMousePosAndDestroy())
    GuiActionEdit.Show()
}

EditConfirm(GuiObj, rowIndex, type, sourceList, originalAction) {
    global ActionsList, GuiActionEdit, IsRecording

    if IsRecording || GuiObj != GuiActionEdit || ActionsList != sourceList
        return

    if rowIndex < 1 || rowIndex > ActionsList.Length {
        ShowWarning("Ungültiger Zeilenindex.")
        return
    }
    try {
        if ActionsList[rowIndex] != originalAction {
            ShowWarning("Die Aktion wurde inzwischen verschoben oder ersetzt. Bitte erneut öffnen.")
            return
        }
        a := originalAction.Clone()
    } catch {
        ShowWarning("Fehler beim Zugriff auf die Aktion.")
        return
    }

    if type = "Click" {
        x := GuiObj["EditX"].Value
        y := GuiObj["EditY"].Value
        if !(IsNumber(x) && IsNumber(y)) {
            ShowWarning("Ungültige Koordinaten!")
            return
        }
        a["X"] := ClampX(x), a["Y"] := ClampY(y)
        a["Button"] := (GuiObj["EditBtn"].Text = "Rechts") ? "Right" : "Left"
        if !ApplyClickCount(a, GuiObj["EditCount"].Value, GuiObj["EditClickDelay"].Value)
            return

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
        if !(IsInteger(amount) && amount >= 1) {
            ShowWarning("Ungültige Schrittanzahl!")
            return
        }
        if !SaveScrollPosition(GuiObj, "Edit", a)
            return
        a["Direction"] := (dir = "Hoch") ? "Up" : "Down"
        a["Amount"]    := Integer(amount)

    } else if type = "KeyPress" {
        key := Trim(GuiObj["EditKey"].Value)
        if key = "" || key = "⌨ Warte auf Taste..." {
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
        if _EditCommentBg >= 0
            a["BgColor"]   := _EditCommentBg
        else if a.Has("BgColor")
            a.Delete("BgColor")
        if _EditCommentFg >= 0
            a["TextColor"] := _EditCommentFg
        else if a.Has("TextColor")
            a.Delete("TextColor")
        _EditCommentBg := -1
        _EditCommentFg := -1

    } else if type = "TextInput" {
        txt := GuiObj["EditTextInput"].Value
        if txt = "" {
            ShowWarning("Bitte einen Text eingeben!")
            return
        }
        a["Text"] := txt
    }

    ; Position auslesen und ggf. verschieben
    newPosStr := GuiObj["EditPosition"].Value
    newPos := (IsNumber(newPosStr) && Integer(newPosStr) >= 1 && Integer(newPosStr) <= ActionsList.Length)
        ? Integer(newPosStr) : rowIndex

    StopEditMousePosAndDestroy()
    PushUndo()

    if newPos = rowIndex {
        ActionsList[rowIndex] := a
    } else {
        ActionsList.RemoveAt(rowIndex)
        ActionsList.InsertAt(newPos, a)
    }

    global MainAllTabs, MainCurrentTab
    MainAllTabs[MainCurrentTab] := ActionsList
    UpdateActionsList(0, originalAction, a)
}

StopEditMousePosAndDestroy(*) {
    global GuiActionEdit
    SetTimer(UpdateEditMousePos, 0)
    ToolTip()
    dialog := GuiActionEdit
    StopActionKeyCapture(dialog)
    GuiActionEdit := ""
    if IsObject(dialog)
        dialog.Destroy()
}

; ─────────────────────────────────────────────
; Tastendruck aufzeichnen (Tab 8 im Insert-Dialog)
; ─────────────────────────────────────────────
RecordActionKey(dialog, fieldName, buttonName) {
    global ActionKeyHook, ActionKeyDialog
    if !IsObject(dialog) || IsObject(ActionKeyHook) || !WinActive("ahk_id " dialog.Hwnd)
        return
    field := dialog[fieldName]
    button := dialog[buttonName]
    previous := field.Value
    field.Value := "⌨ Warte auf Taste..."
    button.Enabled := false
    ih := InputHook("L0 T10")
    ih.KeyOpt("{All}", "E S")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E-S")
    ActionKeyDialog := dialog
    ActionKeyHook := ih
    try {
        ih.Start()
        SetTimer(CheckActionKeyFocus, 25)
        if ih.Wait() = "EndKey" && ActionKeyHook = ih && WinActive("ahk_id " dialog.Hwnd)
            previous := FormatCapturedKey(ih.EndKey, ih.EndMods)
    } finally {
        if ActionKeyHook = ih {
            SetTimer(CheckActionKeyFocus, 0)
            ActionKeyHook := ""
            ActionKeyDialog := ""
            field.Value := previous
            button.Enabled := true
        }
    }
}

CheckActionKeyFocus() {
    global ActionKeyHook, ActionKeyDialog
    if IsObject(ActionKeyHook) && !WinActive("ahk_id " ActionKeyDialog.Hwnd)
        ActionKeyHook.Stop()
}

StopActionKeyCapture(dialog) {
    global ActionKeyHook, ActionKeyDialog
    if !IsObject(ActionKeyHook) || ActionKeyDialog != dialog
        return
    SetTimer(CheckActionKeyFocus, 0)
    hook := ActionKeyHook
    ActionKeyHook := ""
    ActionKeyDialog := ""
    hook.Stop()
}

FormatCapturedKey(key, modifiers) {
    mods := RegExReplace(modifiers, "[<>](.)(?:>\1)?", "$1")
    return mods "{" key "}"
}

; ─────────────────────────────────────────────
; Abbrechen des Insert-Dialogs (auch im Ersetzen-Modus)
; ─────────────────────────────────────────────
InsertCancel() {
    global GuiActionInsert
    global _InsertCommentBg, _InsertCommentFg
    _InsertCommentBg := -1
    _InsertCommentFg := -1
    SetTimer(UpdateInsertMousePos, 0)
    ToolTip()
    dialog := GuiActionInsert
    StopActionKeyCapture(dialog)
    GuiActionInsert := ""
    if IsObject(dialog)
        dialog.Destroy()
}

; ─────────────────────────────────────────────
; Markierte Aktionen durch eine neue ersetzen:
; Öffnet den Insert-Dialog im Ersetzen-Modus.
; ─────────────────────────────────────────────
ReplaceSelectedActions(LV) {
    global ActionsList, GuiActionInsert

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

    replacements := Map()
    for index in indices {
        if index >= 1 && index <= ActionsList.Length
            replacements[index] := ActionsList[index]
    }
    if !replacements.Count
        return
    if !AddAction(replacements)
        return
    ; Titel und Position-Feld anpassen
    try GuiActionInsert.Title := "✏ " indices.Length " Aktion(en) ersetzen"
    try GuiActionInsert["InsertIndex"].Enabled := false
}

; ─────────────────────────────────────────────
; Insert-Dialog bestätigen — baut newAction auf,
; fügt dann ein oder ersetzt die beim Öffnen ausgewählten Aktionen.
; ─────────────────────────────────────────────
ToggleInsertClickFields(checkbox, *) {
    dialog := checkbox.Gui
    dialog["ClickCount"].Enabled := checkbox.Value
    dialog["ClickDelay"].Enabled := checkbox.Value
}

ApplyClickCount(action, count, delay, minimum := 1) {
    if action.Has("ClickTiming") && Trim(delay) = "" {
        if TryParseIntegerSetting(count, minimum, &countValue) && countValue = action["Count"]
            return true
        ShowWarning("Bei geänderter Klickanzahl bitte einen einheitlichen Abstand eingeben.")
        return false
    }
    if !TryParseIntegerSetting(count, minimum, &countValue) || !TryParseIntegerSetting(delay, 0, &delayValue) {
        ShowWarning("Bitte eine ganze Klickanzahl ab " minimum " und eine ganze Verzögerung ab 0 ms eingeben.")
        return false
    }
    for field in ["Count", "ClickDelay", "ClickTiming"] {
        if action.Has(field)
            action.Delete(field)
    }
    if countValue > 1 {
        action["Count"] := countValue
        if delayValue > 0
            action["ClickDelay"] := delayValue
    }
    return true
}

InsertConfirm(dialog, sourceList, replacements) {
    global ActionsList, GuiActionInsert, MainAllTabs, MainCurrentTab, IsRecording
    global _InsertCommentBg, _InsertCommentFg

    if IsRecording || dialog != GuiActionInsert || ActionsList != sourceList
        return
    for index, original in replacements {
        if index > ActionsList.Length || ActionsList[index] != original {
            ShowWarning("Die Auswahl hat sich geändert. Bitte erneut auswählen.")
            return
        }
    }

    try {
        tabIndex    := dialog["ActionTab"].Value
        insertIndex := Integer(dialog["InsertIndex"].Value)
    } catch {
        ShowWarning("Fehler beim Lesen der Eingabefelder.")
        return
    }
    if (insertIndex < 1 || insertIndex > ActionsList.Length + 1)
        insertIndex := ActionsList.Length + 1

    ; ── Neue Aktion aufbauen (kein direktes Insert hier) ──
    newAction := ""

    if tabIndex = 1 {   ; Mausklick
        if dialog["UseCurrentPos"].Value {
            MouseGetPos &x, &y
        } else {
            x := dialog["PosX"].Value
            y := dialog["PosY"].Value
            if !(IsNumber(x) && IsNumber(y)) {
                ShowWarning("Ungültige Koordinaten!")
                return
            }
        }
        btn      := (dialog["ClickBtn"].Text = "Rechts") ? "Right" : "Left"
        newAction := Map("Type", "Click", "Button", btn, "X", ClampX(x), "Y", ClampY(y))
        if dialog["MultiClick"].Value && !ApplyClickCount(newAction, dialog["ClickCount"].Value, dialog["ClickDelay"].Value, 2)
            return

    } else if tabIndex = 2 {   ; Delay
        delay := dialog["DelayValue"].Value
        if !(IsNumber(delay) && delay > 0) {
            ShowWarning("Ungültige Zeit!")
            return
        }
        newAction := Map("Type","Delay","Time",Integer(delay))

    } else if tabIndex = 3 {   ; Drag
        x1 := dialog["DragX1"].Value
        y1 := dialog["DragY1"].Value
        x2 := dialog["DragX2"].Value
        y2 := dialog["DragY2"].Value
        if !(IsNumber(x1) && IsNumber(y1) && IsNumber(x2) && IsNumber(y2)) {
            ShowWarning("Ungültige Koordinaten!")
            return
        }
        btn := (dialog["DragBtn"].Text = "Rechts") ? "Right" : "Left"
        newAction := Map("Type","Drag","Button",btn,
            "X1",ClampX(x1),"Y1",ClampY(y1),"X2",ClampX(x2),"Y2",ClampY(y2))

    } else if tabIndex = 4 {   ; Scroll
        dir    := dialog["ScrollDir"].Text
        amount := dialog["ScrollAmount"].Value
        if !(IsInteger(amount) && amount >= 1) {
            ShowWarning("Ungültige Schritte!")
            return
        }
        newAction := Map("Type","Scroll",
            "Direction",(dir="Hoch")?"Up":"Down","Amount",Integer(amount))
        if !SaveScrollPosition(GuiActionInsert, "Insert", newAction)
            return

    } else if tabIndex = 5 {   ; Langer Klick
        x   := dialog["LongX"].Value
        y   := dialog["LongY"].Value
        dur := dialog["LongDur"].Value
        if !(IsNumber(x) && IsNumber(y) && IsNumber(dur) && dur > 0) {
            ShowWarning("Ungültige Werte!")
            return
        }
        btn := (dialog["LongBtn"].Text = "Rechts") ? "Right" : "Left"
        newAction := Map("Type","LongClick","Button",btn,
            "X",ClampX(x),"Y",ClampY(y),"Duration",Integer(dur))

    } else if tabIndex = 6 {   ; Kommentar
        txt := Trim(dialog["CommentText"].Value)
        if txt = "" {
            ShowWarning("Bitte Kommentartext eingeben!")
            return
        }
        newAction := Map("Type","Comment","Text",txt)
        if _InsertCommentBg >= 0
            newAction["BgColor"]   := _InsertCommentBg
        if _InsertCommentFg >= 0
            newAction["TextColor"] := _InsertCommentFg
        _InsertCommentBg := -1
        _InsertCommentFg := -1

    } else if tabIndex = 7 {   ; Text eingeben
        txt := dialog["TextInput"].Value
        if txt = "" {
            ShowWarning("Bitte Text eingeben!")
            return
        }
        newAction := Map("Type","TextInput","Text",txt)

    } else if tabIndex = 8 {   ; Tastendruck
        key := Trim(dialog["KeyEdit"].Value)
        if key = "" || key = "⌨ Warte auf Taste..." {
            ShowWarning("Bitte eine Taste aufzeichnen oder manuell eingeben!")
            return
        }
        newAction := Map("Type","KeyPress","Key",key)
    }

    if newAction = ""
        return

    InsertCancel()
    TagActionScreen(newAction)
    PushUndo()

    if replacements.Count {
        ; ── Ersetzen-Modus: jede markierte Zeile durch newAction ersetzen ──
        for idx, original in replacements {
            copy := Map()
            for k, v in newAction
                copy[k] := v
            ActionsList[idx] := copy
        }
        MainAllTabs[MainCurrentTab] := ActionsList
        UpdateActionsList()
    } else {
        ; ── Normal einfügen ──
        ActionsList.InsertAt(insertIndex, newAction)
        MainAllTabs[MainCurrentTab] := ActionsList
        UpdateActionsList(insertIndex)
    }
}

; ─────────────────────────────────────────────
; ─────────────────────────────────────────────
SelectAllInListView() {
    global MainCurrentLV
    if !IsObject(MainCurrentLV)
        return
    count := MainCurrentLV.GetCount()
    if count <= 0
        return
    Loop count
        MainCurrentLV.Modify(A_Index, "Select")
    MainCurrentLV.Modify(count, "Vis")
}

IsListViewFocused() {
    global GuiMain, MainCurrentLV
    if !IsObject(GuiMain)
        return false
    if !WinActive("ahk_id " GuiMain.Hwnd)
        return false
    if !IsObject(MainCurrentLV)
        return false
    focusedHwnd := DllCall("GetFocus", "Ptr")
    return (focusedHwnd = MainCurrentLV.Hwnd)
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
    global GuiMain, CurrentFilePath, MainAllTabPaths, MainCurrentTab
    CurrentFilePath := filePath
    if IsSet(MainAllTabPaths) && MainAllTabPaths.Length >= MainCurrentTab
        MainAllTabPaths[MainCurrentTab] := filePath
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
SetSelectedDelays(lv, clickedRow) {
    scope := Map()
    for action in GetActionsForContextMenu(lv, clickedRow) {
        if action["Type"] = "Delay"
            scope[action] := true
    }
    if !scope.Count {
        ShowWarning("Die Auswahl enthält keine Zeitverzögerungen.")
        return
    }
    SetAllDelays(scope)
}

SetAllDelays(scope := "") {
    global ActionsList, IsRecording
    if IsRecording
        return
    source := ActionsList

    if ActionsList.Length = 0 {
        ShowWarning("Keine Aktionen in der Liste.")
        return
    }

    delayCount := CountDelays(source, scope)

    if delayCount = 0 {
        ShowWarning("Keine Zeitverzögerungen in der Liste vorhanden.")
        return
    }

    GuiDelay := Gui("+ToolWindow +AlwaysOnTop", IsObject(scope) ? "Zeit-Manager – Auswahl" : "Zeit-Manager")
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
        .OnEvent("Click", (*) => ApplyAllDelays(GuiDelay, source, scope))
    GuiDelay.AddButton("x+6 yp w110 h26 Background0xCC0000 cWhite", IsObject(scope) ? "✖ Auswahl löschen" : "✖ Alle löschen")
        .OnEvent("Click", (*) => DeleteAllDelays(GuiDelay, source, false, scope))
    GuiDelay.AddButton("x+6 yp w60 h26", "Abbrechen")
        .OnEvent("Click", (*) => GuiDelay.Destroy())

    GuiDelay.Show()
}

ApplyAllDelays(GuiDelay, source, scope := "") {
    global ActionsList, IsRecording
    if IsRecording || ActionsList != source
        return

    valMs  := GuiDelay["DelayMs"].Value
    valRnd := GuiDelay["DelayRandom"].Value

    if !TryParseIntegerSetting(valMs, 0, &newTime) {
        ShowWarning("Bitte eine ganze Verzögerung ab 0 ms eingeben.")
        return
    }

    if !TryParseIntegerSetting(valRnd, 0, &variation) {
        ShowWarning("Bitte eine ganze Zufallsvariation ab 0 ms eingeben.")
        return
    }

    if newTime = 0 {
        DeleteAllDelays(GuiDelay, source, true, scope)
        return
    }

    delayCount := CountDelays(source, scope)
    if IsObject(scope) && delayCount != scope.Count {
        ShowWarning("Die ausgewählten Verzögerungen haben sich geändert. Bitte die Auswahl erneut öffnen.")
        return
    }
    if !delayCount
        return

    if variation > 9223372036854775807 - newTime {
        ShowWarning("Verzögerung und Zufallsvariation ergeben zusammen einen zu großen Wert.")
        return
    }
    minimum := Max(1, newTime - variation)
    maximum := newTime + variation
    PushUndo()
    changed := 0
    for action in ActionsList {
        if action["Type"] = "Delay" && (!IsObject(scope) || scope.Has(action)) {
            action["Time"] := variation > 0 ? Random(minimum, maximum) : newTime
            changed++
        }
    }

    GuiDelay.Destroy()
    UpdateActionsList()
    range := variation > 0 ? minimum " bis " maximum : newTime
    ShowInfo(changed " Verzögerung(en) gesetzt. Bereich: " range " ms.")
}

CountDelays(actions, scope := "") {
    count := 0
    for action in actions {
        if action["Type"] = "Delay" && (!IsObject(scope) || scope.Has(action))
            count++
    }
    return count
}

DeleteAllDelays(GuiDelay, source, zeroDelay := false, scope := "") {
    global ActionsList, IsRecording
    if IsRecording || ActionsList != source
        return
    delayCount := CountDelays(source, scope)
    if IsObject(scope) && delayCount != scope.Count {
        ShowWarning("Die ausgewählten Verzögerungen haben sich geändert. Bitte die Auswahl erneut öffnen.")
        return
    }
    if !delayCount {
        ShowWarning("Die Liste enthält keine Verzögerungen mehr.")
        return
    }
    prompt := (zeroDelay ? "Neuer Wert ist 0 ms.`n`n" : "")
        . (IsObject(scope) ? "Ausgewählte " : "Alle ") delayCount " Verzögerungen aus der Liste entfernen?`n`n"
        . "Dieser Schritt kann rückgängig gemacht werden."
    if ShowYesNo(prompt, "Verzögerungen löschen?") != "Yes" || IsRecording || ActionsList != source
        return
    if CountDelays(source, scope) != delayCount {
        ShowWarning("Die Anzahl der Verzögerungen hat sich geändert. Bitte erneut bestätigen.")
        return
    }
    GuiDelay.Destroy()
    _RemoveAllDelays(scope)
}

_RemoveAllDelays(scope := "") {
    global ActionsList
    PushUndo()
    RemoveMatchingActions(ActionsList, (action, *) => action["Type"] = "Delay" && (!IsObject(scope) || scope.Has(action)))
    UpdateActionsList()
    ShowInfo(IsObject(scope) ? "Die ausgewählten Verzögerungen wurden entfernt." : "Alle Verzögerungen wurden entfernt.")
}

; ─────────────────────────────────────────────
; UNDO / REDO
; ─────────────────────────────────────────────
global MainUndoTabs := [[], [], []]
global MainRedoTabs := [[], [], []]
global _UndoMaxDepth := 30

; Aktuellen Stand auf Undo-Stack sichern (vor jeder Listenänderung aufrufen)
PushUndo() {
    global ActionsList, _UndoMaxDepth, MainCurrentTab, MainUndoTabs, MainRedoTabs
    undoStack := MainUndoTabs[MainCurrentTab]
    redoStack := MainRedoTabs[MainCurrentTab]
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
    redoStack.Length := 0
    UpdateUndoMenuState()
}

MenuUndo(*) {
    global IsRecording
    if IsRecording
        return
    global ActionsList, MainAllTabs, MainCurrentTab, MainUndoTabs, MainRedoTabs
    undoStack := MainUndoTabs[MainCurrentTab]
    redoStack := MainRedoTabs[MainCurrentTab]
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
    MainAllTabs[MainCurrentTab] := ActionsList   ; Tab-Slot synchron halten
    UpdateActionsList()
    UpdateUndoMenuState()
}

MenuRedo(*) {
    global IsRecording
    if IsRecording
        return
    global ActionsList, MainAllTabs, MainCurrentTab, MainUndoTabs, MainRedoTabs
    undoStack := MainUndoTabs[MainCurrentTab]
    redoStack := MainRedoTabs[MainCurrentTab]
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
    MainAllTabs[MainCurrentTab] := ActionsList   ; Tab-Slot synchron halten
    UpdateActionsList()
    UpdateUndoMenuState()
}

UpdateUndoMenuState() {
    global MenuEditRef, MainCurrentTab, MainUndoTabs, MainRedoTabs
    undoStack := MainUndoTabs[MainCurrentTab]
    redoStack := MainRedoTabs[MainCurrentTab]
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
; Bearbeiten-Menü: Tab-Einträge dynamisch aktualisieren
; ─────────────────────────────────────────────
global _MenuTabDeleteLabel := "Tab löschen"

MainDeleteCurrentTabMenu(*) {
    global MainCurrentTab, MainAllTabs
    if MainAllTabs.Length <= 1 {
        ShowInfo("Der letzte Tab kann nicht gelöscht werden.")
        return
    }
    MainDeleteTab(MainCurrentTab)
}

UpdateEditMenuTabs() {
    global MenuEditRef, MainCurrentTab, MainTabNames, MainAllTabs, _MenuTabDeleteLabel
    if !IsObject(MenuEditRef)
        return
    tabName := (MainCurrentTab >= 1 && MainCurrentTab <= MainTabNames.Length)
        ? MainTabNames[MainCurrentTab] : "Tab"
    newLabel := 'Tab "' tabName '" löschen'
    try MenuEditRef.Rename(_MenuTabDeleteLabel, newLabel)
    _MenuTabDeleteLabel := newLabel
    if MainAllTabs.Length <= 1 {
        MenuEditRef.Disable(newLabel)
    } else {
        MenuEditRef.Enable(newLabel)
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
    global ActionsList, IsRecording
    if IsRecording
        return
    if !FileExist(filePath) {
        ShowWarning("Datei nicht mehr vorhanden:`n" filePath)
        return
    }
    try {
        loadedActions := ReadActionFile(filePath)
        if !(loadedActions is Array) {
            ShowWarning("Keine gültige Aktionsliste!")
            return
        }
        global MainAllTabs, MainCurrentTab
        ActionsList := loadedActions
        global MainScreenProfiles, MainCurrentTab
        MainScreenProfiles[MainCurrentTab] := loadedActions.HasOwnProp("RecorderScreenProfile")
            ? loadedActions.RecorderScreenProfile : NewScreenProfile()
        MainAllTabs[MainCurrentTab] := ActionsList
        UpdateActionsList()
        SetCurrentFile(filePath)
        AddToRecentFiles(filePath)
    } catch as err {
        ShowError("Fehler beim Laden:`n" err.Message)
    }
}

ConfirmJsonSavePath(path) {
    if RegExMatch(path, "i)\.json$")
        return path
    path .= ".json"
    if FileExist(path) && ShowYesNo("Vorhandene Datei überschreiben?`n" path, "Speichern") != "Yes"
        return ""
    return path
}

SaveActions(*) {
    global ActionsList, GuiMain, CurrentFilePath

    if !(ActionsList is Array) {
        ShowError("ActionsList ist kein Array!")
        return
    }

    source := ActionsList

    try {
        WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    defaultPath := (CurrentFilePath != "") ? CurrentFilePath : A_ScriptDir "\actions.json"
    file := FileSelect("S16", defaultPath, "JSON speichern unter...", "JSON-Dateien (*.json)")

    try {
        WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    if !file || ActionsList != source
        return

    file := ConfirmJsonSavePath(file)
    if !file || ActionsList != source
        return

    if SaveActionsToFile(file)
        AddToRecentFiles(file)
}

LoadActions(*) {
    global ActionsList, GuiMain, IsRecording
    if IsRecording
        return

    source := ActionsList

    try {
        WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    file := FileSelect("3", A_ScriptDir, "JSON-Datei laden", "JSON-Dateien (*.json)")

    try {
        WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    if !file || IsRecording || ActionsList != source
        return

    if !FileExist(file) {
        ShowError("Datei nicht gefunden:`n" file)
        return
    }

    try {
        loadedActions := ReadActionFile(file)
        if IsRecording || ActionsList != source
            return
        if !(loadedActions is Array) {
            ShowWarning("Datei enthaelt keine gueltige Aktionsliste!")
            return
        }
        global MainAllTabs, MainCurrentTab
        ActionsList := loadedActions
        global MainScreenProfiles, MainCurrentTab
        MainScreenProfiles[MainCurrentTab] := loadedActions.HasOwnProp("RecorderScreenProfile")
            ? loadedActions.RecorderScreenProfile : NewScreenProfile()
        MainAllTabs[MainCurrentTab] := ActionsList   ; Tab-Slot synchron halten
        UpdateActionsList()
        SetCurrentFile(file)
        AddToRecentFiles(file)
    } catch as err {
        ShowError("Fehler beim Laden:`n" err.Message)
    }
}

UpdateRecordingComments(actions, filename) {
    first := 0
    last := 0
    for index, action in actions {
        if action["Type"] = "Comment" {
            if !first
                first := index
            last := index
        }
    }
    if !first
        return
    for boundary in [[first, "Aufnahme gestartet"], [last, "Aufnahme beendet"]] {
        index := boundary[1], label := boundary[2]
        action := actions[index]
        if RegExMatch(action["Text"], "^(?:\d+\. )?" label "(?::.*)?$", &match) {
            copy := action.Clone()
            copy["Text"] := RegExReplace(match[0], ":.*$") ": " filename
            actions[index] := copy
        }
    }
}

; ─────────────────────────────────────────────
; JSON-Kompatibilitaet
; ─────────────────────────────────────────────
