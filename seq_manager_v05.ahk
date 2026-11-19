;=========================
; Datei: seq_manager_v05.ahk
; Features:
;   - Einzelne JSON-Dateien laden
;   - Ganzen Ordner laden (alle *.json automatisch)
;   - Ordnerpfad wird in INI gespeichert und beim Start wiederhergestellt
;   - Sequenzen zu einem SET zusammenfassen (neue JSON mit allen Aktionen)
;   - Reihenfolge per Drag & Drop oder Hoch/Runter anpassen
;   - Alle Sequenzen hintereinander abspielen (Loop optional)
;=========================

#Requires AutoHotkey v2.0

global GuiSeqManager    := ""
global SeqAllTabs       := [[], [], []]               ; Array von SeqListen, eine pro Tab
global SeqTabNames      := ["Tab 1", "Tab 2", "Tab 3"] ; Tab-Namen
global SeqCurrentTab    := 1          ; Aktiver Tab (1-basiert)
global SeqList          := SeqAllTabs[1]  ; Alias für aktiven Tab
global SeqPlaybackList := []
global SeqSinglePlaying := false
global SeqTabCtrl       := ""         ; Tab3-Control
global SeqTabChanging   := false      ; Schutz vor Endlosschleife (Change-Event)
global SeqCurrentLV     := ""         ; Aktuell sichtbare ListView
global SeqLVCounter     := 0          ; Einzigartiger Zaehler fuer LV-Namen (nie zuruecksetzen)
global SeqTabLVNames    := []         ; Tab-Index → ListView-vName
global IsSeqPlaying     := false
global SeqCurrentIndex  := 0
global SeqRepeatMode    := false
global SeqFolder        := ""

; INI-Datei im gleichen Verzeichnis wie das Skript
global SeqIniFile := A_ScriptDir "\AHK_Recorder_settings.ini"

; Drag & Drop Zustand für SeqListView
global SeqLVDragRow       := 0
global SeqLVDragTargetRow := 0
global SeqLVDragging      := false

; ─────────────────────────────────────────────
; Sequenz-Manager Fenster öffnen
; ─────────────────────────────────────────────
ShowSeqManager(*) {
    global GuiSeqManager, GuiMain, SeqTabCtrl, SeqTabLVNames, SeqLVCounter, SeqCurrentLV, SeqTabNames

    if IsObject(GuiMain)
        try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)

    if IsObject(GuiSeqManager) {
        GuiSeqManager.Show()
        return
    }

    GuiSeqManager := Gui("+Resize +AlwaysOnTop", "Sequenz-Manager")
    GuiSeqManager.SetFont("s9")
    GuiSeqManager.OnEvent("Close", SeqManagerClose)

    ; ── GroupBox: Dateien laden ──
    GuiSeqManager.SetFont("s10")
    GuiSeqManager.AddGroupBox("x8 y8 w594 h82 Section cBlue", "Dateien laden")
    GuiSeqManager.SetFont("s9")

    GuiSeqManager.AddButton("xs+8 ys+22 w170 h28 Background0x00CC00 cWhite", "+ Dateien hinzufügen")
        .OnEvent("Click", SeqAdd)
    GuiSeqManager.AddButton("x+5 yp w140 h28 Background0x007050 cWhite", "Ordner laden")
        .OnEvent("Click", SeqLoadFolder)
    GuiSeqManager.AddButton("x+5 yp w140 h28 Background0x005090 cWhite", "Ordner neu laden")
        .OnEvent("Click", SeqReloadFolder)
    GuiSeqManager.AddText("vSeqFolderLabel xs+8 y+6 w576 cGray", "Kein Ordner ausgewählt.")

    ; ── Hinweiszeile ──
    GuiSeqManager.AddText("x8 y+8 w576 cGray",
        "Rechtsklick = Kontextmenue  |  Enter = Abspielen  |  Entf = Entfernen  |  Drag+Drop = Reihenfolge")

    ; Tab3 – eine ListView pro Tab (UseTab(n) vor AddListView).
    ; Tab3 – eine ListView pro Tab (UseTab(n) vor AddListView).
    SeqTabCtrl := GuiSeqManager.AddTab3("x8 y+6 w576 h244", SeqTabNames)
    SeqTabCtrl.OnEvent("Change",      (*) => SeqSwitchTabFromCtrl())
    SeqTabCtrl.OnEvent("ContextMenu", SeqTabCtxMenu)

    ; Erste ListView innerhalb Tab 1 anlegen.
    SeqLVCounter++
    lvName1 := "SeqLV_" SeqLVCounter
    SeqTabLVNames := [lvName1]
    SeqTabCtrl.GetPos(&tabX, &tabY, &tabW, &tabH)
    lvX := tabX + 8
    lvY := tabY + 30
    lvW := tabW - 16
    lvH := tabH - 38
    SeqTabCtrl.UseTab(1)
    LV := GuiSeqManager.AddListView(
        "v" lvName1 " x" lvX " y" lvY " w" lvW " h" lvH " Grid Multi Checked",
        ["", "Nr", "Dateiname", "Aktionen", "Status"])
    LV.ModifyCol(1, "26")    ; Checkbox-Spalte (kein Header)
    LV.ModifyCol(2, "40")    ; Nr
    LV.ModifyCol(3, "252")   ; Dateiname
    LV.ModifyCol(4, "80")    ; Aktionen
    LV.ModifyCol(5, "110")   ; Status
    LV.OnEvent("ContextMenu",   (lv,r,rc,x,y) => ShowSeqLVContextMenu(lv,r,rc,x,y))
    LV.OnEvent("DoubleClick",  (lv,row)       => (row >= 1 ? SeqEditActions(row) : 0))
    LV.OnEvent("ItemSelect",   (lv, row, sel) => (row >= 1 && sel ? lv.Modify(row, "Check") : 0))
    SeqTabCtrl.UseTab(0)
    SeqCurrentLV := LV
    SetupSeqLVDragDrop()

    ; Verwaltungs-Buttons: direkt unter ListView (y+8 = ListView.bottom + 8)
    GuiSeqManager.AddButton("x8 y+8 w115 h28 Background0xCC0000 cWhite", "✕ Entfernen")
        .OnEvent("Click", SeqRemove)
    GuiSeqManager.AddButton("x+5 yp w90 h28 Background0x444444 cWhite", "▲ Hoch")
        .OnEvent("Click", SeqMoveUp)
    GuiSeqManager.AddButton("x+5 yp w90 h28 Background0x444444 cWhite", "▼ Runter")
        .OnEvent("Click", SeqMoveDown)
    GuiSeqManager.AddButton("x+5 yp w196 h28 Background0x804000 cWhite", "⊞ Zu SET zusammenfassen")
        .OnEvent("Click", SeqMergeToSet)

    ; ── GroupBox: Sequenz-Steuerung ──
    GuiSeqManager.SetFont("s10")
    GuiSeqManager.AddGroupBox("x8 y+8 w594 h112 Section cBlue", "Sequenz-Steuerung")
    GuiSeqManager.SetFont("s9")

    GuiSeqManager.AddButton("xs+8 ys+24 w160 h36 Background0x0080FF cWhite", "▶ Alle abspielen")
        .OnEvent("Click", SeqPlayAll)
    GuiSeqManager.AddButton("x+5 yp w130 h36 Background0xCC7700 cWhite", "⟳ Loop an/aus")
        .OnEvent("Click", SeqToggleLoop)
    GuiSeqManager.AddButton("x+5 yp w100 h36 Background0x800080 cWhite", "■ Stop")
        .OnEvent("Click", (*) => SeqAbort())

    GuiSeqManager.AddText("xs+8 y+8 vSeqStatus w576", "Bereit.")
    GuiSeqManager.AddText("xs+8 y+4 vSeqLoopLabel w200", "Loop: Inaktiv")

    GuiSeqManager.Show("w610")
    SeqRefreshList()
    SeqRestoreOnStartup()
}

; ─────────────────────────────────────────────
; SeqManager schließen: Hauptfenster AlwaysOnTop wiederherstellen
; ─────────────────────────────────────────────
SeqManagerClose(*) {
    global GuiSeqManager, GuiMain

    ; AlwaysOnTop kurz deaktivieren, damit die MsgBox sichtbar ist
    try WinSetAlwaysOnTop(0, "ahk_id " GuiSeqManager.Hwnd)
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)

    answer := MsgBox(
        "Tabs und Inhalte für den nächsten Programmstart speichern?",
        "Sequenz-Manager schließen",
        "YesNoCancel Icon?"
    )

    try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    try WinSetAlwaysOnTop(1, "ahk_id " GuiSeqManager.Hwnd)

    if answer = "Cancel"
        return true   ; Fenster bleibt geöffnet

    if answer = "Yes" && !SeqSaveList()
        return true

    GuiSeqManager.Hide()
    if IsObject(GuiMain)
        WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
}

; ─────────────────────────────────────────────
; Tab-Verwaltung
; ─────────────────────────────────────────────

; ListView sichtbar machen UND Header-Control zum Neuzeichnen zwingen.
; Windows-Quirk: nach Tab3 Show/Hide bleibt die Spaltenleiste (SysHeader32)
; unsichtbar bis ein Maus-Event sie zur Neuzeichnung zwingt.
; LVM_GETHEADER = 0x101F liefert das HWND des Header-Child-Windows.
SeqForceRedrawLV(lv) {
    if !IsObject(lv)
        return
    lv.Visible := true
    hdr := SendMessage(0x101F, 0, 0, lv.Hwnd)
    if hdr {
        DllCall("InvalidateRect", "Ptr", hdr, "Ptr", 0, "Int", 1)
        DllCall("UpdateWindow",   "Ptr", hdr)
    }
    DllCall("InvalidateRect", "Ptr", lv.Hwnd, "Ptr", 0, "Int", 1)
}

; Alle Reiter loeschen, alle neu anlegen, aktiven Reiter setzen.
; SeqTabLVNames bleibt unveraendert (LV-Slots behalten ihre Indizes).
SeqRebuildTabBar() {
    global SeqTabCtrl, SeqTabNames, SeqCurrentTab, SeqTabChanging
    global SeqCurrentLV, SeqTabLVNames, GuiSeqManager
    if !IsObject(SeqTabCtrl)
        return
    if SeqTabLVNames.Length >= SeqCurrentTab
        SeqCurrentLV := GuiSeqManager[SeqTabLVNames[SeqCurrentTab]]
    SeqTabChanging := true
    SeqTabCtrl.Delete()
    SeqTabCtrl.Add(SeqTabNames)
    SeqTabChanging := false
    SeqTabCtrl.Value := SeqCurrentTab
    ; LV explizit sichtbar setzen und Header-Control zum Neuzeichnen zwingen.
    SeqForceRedrawLV(SeqCurrentLV)
}

; Daten wechseln + ListView aktualisieren + Reiter hervorheben.
SeqSwitchTab(n) {
    global SeqAllTabs, SeqCurrentTab, SeqList, SeqTabCtrl, SeqTabChanging
    global SeqCurrentLV, SeqTabLVNames, GuiSeqManager
    if n < 1 || n > SeqAllTabs.Length
        return
    SeqCurrentTab := n
    SeqList       := SeqAllTabs[n]
    if SeqTabLVNames.Length >= n
        SeqCurrentLV := GuiSeqManager[SeqTabLVNames[n]]
    SeqRefreshList()
    if IsObject(SeqTabCtrl)
        SeqTabCtrl.Value := n   ; kein Guard noetig: State schon gesetzt
    SeqForceRedrawLV(SeqCurrentLV)
}

; Change-Event: Benutzer klickt auf einen Reiter.
SeqSwitchTabFromCtrl() {
    global SeqTabCtrl, SeqAllTabs, SeqTabChanging
    if SeqTabChanging
        return
    n := SeqTabCtrl.Value
    if n >= 1 && n <= SeqAllTabs.Length
        SeqSwitchTab(n)
}

; Neuen Tab anlegen.
SeqNewTab() {
    global SeqAllTabs, SeqTabNames, SeqTabCtrl, SeqTabChanging
    global SeqCurrentLV, SeqLVCounter, SeqTabLVNames, GuiSeqManager
    global SeqCurrentTab, SeqList

    if SeqAllTabs.Length >= 16 {
        ShowInfo("Maximal 16 Tabs moeglich.")
        return
    }
    name   := "Tab " (SeqAllTabs.Length + 1)
    SeqAllTabs.Push([])
    SeqTabNames.Push(name)
    newIdx := SeqAllTabs.Length

    ; ListView fuer neuen Tab anlegen (UseTab vor AddListView)
    SeqTabChanging := true
    SeqTabCtrl.Add([name])
    if newIdx <= SeqTabLVNames.Length {
        lv := GuiSeqManager[SeqTabLVNames[newIdx]]
        lv.Delete()
    } else {
        SeqLVCounter++
        lvName := "SeqLV_" SeqLVCounter
        SeqTabLVNames.Push(lvName)

        SeqTabCtrl.UseTab(newIdx)
        SeqTabCtrl.GetPos(&tabX, &tabY, &tabW, &tabH)
        lvX := tabX + 8
        lvY := tabY + 30
        lvW := tabW - 16
        lvH := tabH - 38
        lv  := GuiSeqManager.AddListView(
            "v" lvName " x" lvX " y" lvY " w" lvW " h" lvH " Grid Multi Checked",
            ["", "Nr", "Dateiname", "Aktionen", "Status"])
        lv.ModifyCol(1, "26")    ; Checkbox-Spalte (kein Header)
        lv.ModifyCol(2, "40")    ; Nr
        lv.ModifyCol(3, "252")   ; Dateiname
        lv.ModifyCol(4, "80")    ; Aktionen
        lv.ModifyCol(5, "110")   ; Status
        lv.OnEvent("ContextMenu",  (lv2,r,rc,x,y) => ShowSeqLVContextMenu(lv2,r,rc,x,y))
        lv.OnEvent("DoubleClick",  (lv2,row)      => (row >= 1 ? SeqEditActions(row) : 0))
        lv.OnEvent("ItemSelect",   (lv2, row, sel) => (row >= 1 && sel ? lv2.Modify(row, "Check") : 0))
        SeqTabCtrl.UseTab(0)
    }
    SeqTabChanging := false

    ; State vor Value-Zuweisung setzen, dann Value ausserhalb Guard
    SeqCurrentTab := newIdx
    SeqList       := SeqAllTabs[newIdx]
    SeqCurrentLV  := lv
    SeqTabCtrl.Value := newIdx

    SeqRefreshList()
}

; Rechtsklick auf Tab3: ctrl.Value liefert den angeklickten Reiter.
SeqTabCtxMenu(ctrl, item, isRightClick, x, y) {
    global SeqAllTabs
    n := ctrl.Value   ; beim Rechtsklick aktiviert Windows den Reiter automatisch
    ctx := Menu()
    if n >= 1 && n <= SeqAllTabs.Length {
        ctx.Add("Tab umbenennen...", (*) => SeqRenameTab(n))
        if SeqAllTabs.Length > 1
            ctx.Add("Tab loeschen",  (*) => SeqDeleteTab(n))
        ctx.Add()
    }
    ctx.Add("Neuer Tab  (Tab " (SeqAllTabs.Length + 1) ")", (*) => SeqNewTab())
    ctx.Show()
}

; Tab loeschen.
; Nach Delete()+Add() auf Tab3 bleiben die Sub-Control-Slots unveraendert.
; Der hoechste Slot (N) wird orphaned – Pop() entfernt ihn aus SeqTabLVNames.
SeqDeleteTab(n) {
    global SeqAllTabs, SeqTabNames, SeqCurrentTab, SeqList
    global SeqTabChanging, SeqTabCtrl, SeqCurrentLV, SeqTabLVNames, GuiSeqManager

    if SeqAllTabs.Length <= 1 {
        ShowInfo("Der letzte Tab kann nicht geloescht werden.")
        return
    }
    if n < 1 || n > SeqAllTabs.Length
        return

    SeqAllTabs.RemoveAt(n)
    SeqTabNames.RemoveAt(n)

    ; Steuerelement des frei gewordenen Tab-Platzes für später leeren.
    GuiSeqManager[SeqTabLVNames[SeqAllTabs.Length + 1]].Delete()

    SeqCurrentTab := Min(n, SeqAllTabs.Length)
    SeqList       := SeqAllTabs[SeqCurrentTab]
    SeqCurrentLV  := GuiSeqManager[SeqTabLVNames[SeqCurrentTab]]

    SeqTabChanging := true
    SeqTabCtrl.Delete()
    SeqTabCtrl.Add(SeqTabNames)
    SeqTabChanging := false

    SeqTabCtrl.Value := SeqCurrentTab
    SeqForceRedrawLV(SeqCurrentLV)
    SeqRefreshList()

    _delTab := SeqCurrentTab
    SetTimer(SeqDeleteTabRefresh.Bind(_delTab), -1)
}

SeqDeleteTabRefresh(savedTab) {
    global SeqCurrentTab, SeqCurrentLV
    if SeqCurrentTab != savedTab
        return
    SeqForceRedrawLV(SeqCurrentLV)
    SeqRefreshList()
}

; Beim Start: ListViews fuer alle Tabs anlegen, die noch keine haben.
; Tab 1 hat bereits eine LV (aus ShowSeqManager). Tabs 2..N werden hier erstellt.
SeqEnsureTabLVs() {
    global SeqTabCtrl, SeqTabNames, SeqTabLVNames, SeqLVCounter, GuiSeqManager

    if !IsObject(SeqTabCtrl)
        return

    SeqTabCtrl.GetPos(&tabX, &tabY, &tabW, &tabH)
    lvX := tabX + 8
    lvY := tabY + 30
    lvW := tabW - 16
    lvH := tabH - 38

    i := SeqTabLVNames.Length + 1
    while i <= SeqTabNames.Length {
        SeqLVCounter++
        lvName := "SeqLV_" SeqLVCounter
        SeqTabLVNames.Push(lvName)
        SeqTabCtrl.UseTab(i)
        lv := GuiSeqManager.AddListView(
            "v" lvName " x" lvX " y" lvY " w" lvW " h" lvH " Grid Multi Checked",
            ["", "Nr", "Dateiname", "Aktionen", "Status"])
        lv.ModifyCol(1, "26")    ; Checkbox-Spalte (kein Header)
        lv.ModifyCol(2, "40")    ; Nr
        lv.ModifyCol(3, "252")   ; Dateiname
        lv.ModifyCol(4, "80")    ; Aktionen
        lv.ModifyCol(5, "110")   ; Status
        lv.OnEvent("ContextMenu",  (lv2,r,rc,x,y) => ShowSeqLVContextMenu(lv2,r,rc,x,y))
        lv.OnEvent("DoubleClick",  (lv2,row)      => (row >= 1 ? SeqEditActions(row) : 0))
        lv.OnEvent("ItemSelect",   (lv2, row, sel) => (row >= 1 && sel ? lv2.Modify(row, "Check") : 0))
        SeqTabCtrl.UseTab(0)
        i++
    }
}

; Tab umbenennen.
SeqRenameTab(n) {
    global SeqTabNames, SeqAllTabs, GuiSeqManager, GuiMain
    if n < 1 || n > SeqTabNames.Length
        return
    originalTab := SeqAllTabs[n]
    SeqSuspendTopmost()
    try result := InputBox("Neuer Tab-Name:", "Tab umbenennen", "w300 h100", SeqTabNames[n])
    finally {
        try WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
        SeqRestoreTopmost()
    }
    if result.Result != "OK" || Trim(result.Value) = ""
        return
    if n > SeqAllTabs.Length || SeqAllTabs[n] != originalTab {
        ShowWarning("Der Tab hat sich inzwischen geändert. Bitte erneut öffnen.")
        return
    }
    SeqTabNames[n] := Trim(result.Value)
    SeqRebuildTabBar()
}

; Hilfsfunktion: vor Datei-/Ordner-Dialog beide Fenster zurücksetzen
SeqSuspendTopmost() {
    global GuiSeqManager, GuiMain
    try WinSetAlwaysOnTop(0, "ahk_id " GuiSeqManager.Hwnd)
    try WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
}

SeqRestoreTopmost() {
    global GuiSeqManager, GuiMain
    try WinSetAlwaysOnTop(1, "ahk_id " GuiSeqManager.Hwnd)
    try GuiSeqManager.Show()
}

; ─────────────────────────────────────────────
; Einzelne Dateien hinzufügen
; ─────────────────────────────────────────────
SeqAdd(*) {
    global SeqList, GuiSeqManager

    source := SeqList
    SeqSuspendTopmost()
    try files := FileSelect("M3", A_ScriptDir, "JSON-Sequenzen auswählen", "JSON-Dateien (*.json)")
    finally SeqRestoreTopmost()

    if !files || SeqList != source
        return

    if !(files is Array)
        files := [files]

    SeqAddFiles(files)
}

; ─────────────────────────────────────────────
; Hilfsfunktion: Array von Dateipfaden hinzufügen
; ─────────────────────────────────────────────
SeqAddFiles(files) {
    global SeqList

    for file in files {
        if !FileExist(file)
            continue

        skip := false
        for s in SeqList {
            if s.Has("file") && s["file"] = file {
                skip := true
                ShowWarning("Bereits in der Liste:`n" SeqBasename(file) "`n`nDie Datei wurde übersprungen.")
                break
            }
        }
        if skip
            continue

        count := SeqGetActionCount(file)
        name  := SeqBasename(file)

        SeqList.Push(Map(
            "type",   "file",
            "file",   file,
            "name",   name,
            "count",  count,
            "status", "Wartet"
        ))
    }

    SeqRefreshList()
}

; ─────────────────────────────────────────────
; Ordner auswählen und alle JSONs laden
; ─────────────────────────────────────────────
SeqLoadFolder(*) {
    global SeqFolder, SeqIniFile, GuiSeqManager, SeqList

    source := SeqList
    SeqSuspendTopmost()
    try folder := DirSelect(A_ScriptDir, 3, "Ordner mit JSON-Sequenzen auswählen")
    finally SeqRestoreTopmost()

    if !folder || SeqList != source
        return

    SeqFolder := folder

    try {
        IniWrite(SeqFolder, SeqIniFile, "SeqManager", "LastFolder")
    } catch {
        SeqUpdateStatus("Warnung: Ordner konnte nicht in INI gespeichert werden.")
    }

    SeqLoadAllFromFolder(SeqFolder)
}

; ─────────────────────────────────────────────
; Gespeicherten Ordner neu laden
; ─────────────────────────────────────────────
SeqReloadFolder(*) {
    global SeqFolder

    if SeqFolder = "" {
        ShowWarning("Kein Ordner ausgewählt. Bitte zuerst 'Ordner laden' verwenden.")
        return
    }

    SeqLoadAllFromFolder(SeqFolder)
}

; ─────────────────────────────────────────────
; Alle JSONs aus einem Ordner laden
; ─────────────────────────────────────────────
SeqLoadAllFromFolder(folder) {
    global SeqList, GuiSeqManager

    if !DirExist(folder) {
        ShowWarning("Ordner nicht gefunden:`n" folder)
        return
    }

    files := []
    loop files folder "\*.json" {
        files.Push(A_LoopFileFullPath)
    }

    if files.Length = 0 {
        ShowWarning("Keine JSON-Dateien in:`n" folder)
        return
    }

    SeqAddFiles(files)

    if IsObject(GuiSeqManager) {
        shortPath := (StrLen(folder) > 60) ? "..." SubStr(folder, -57) : folder
        GuiSeqManager["SeqFolderLabel"].Value := "Ordner: " shortPath " (" files.Length " Dateien gefunden)"
    }

    SeqUpdateStatus(files.Length " JSON-Datei(en) aus Ordner geladen.")
}

; ─────────────────────────────────────────────
; Gespeicherten Ordner beim Start wiederherstellen
; ─────────────────────────────────────────────
SeqRestoreFolder() {
    global SeqFolder, SeqIniFile, GuiSeqManager

    savedFolder := ""
    try {
        savedFolder := IniRead(SeqIniFile, "SeqManager", "LastFolder", "")
    } catch {
        SeqUpdateStatus("Warnung: Ordner konnte nicht aus INI gelesen werden.")
    }

    if savedFolder = "" || !DirExist(savedFolder)
        return

    SeqFolder := savedFolder
    if IsObject(GuiSeqManager) {
        shortPath := (StrLen(savedFolder) > 60) ? "..." SubStr(savedFolder, -57) : savedFolder
        GuiSeqManager["SeqFolderLabel"].Value := "Ordner: " shortPath " (gespeichert)"
    }
}

; ─────────────────────────────────────────────
; Startup: gespeicherte Liste laden.
; ─────────────────────────────────────────────
SeqRestoreOnStartup() {
    global SeqList, SeqIniFile, SeqFolder, SeqAllTabs, SeqTabNames, SeqCurrentTab
    global SeqCurrentLV, SeqTabLVNames, GuiSeqManager

    SeqRestoreFolder()
    SeqLoadSavedList()

    ; Mindestens 3 Tabs sicherstellen.
    ; Wurden beim letzten Speichern weniger als 3 Tabs gespeichert (oder kein INI
    ; vorhanden), werden leere Tabs bis zur Mindestanzahl ergänzt.
    ; Wurden mehr als 3 Tabs gespeichert, bleibt alles unverändert.
    while SeqAllTabs.Length < 3 {
        n := SeqAllTabs.Length + 1
        SeqAllTabs.Push([])
        SeqTabNames.Push("Tab " n)
    }

    ; ListViews fuer alle aus INI geladenen Tabs sicherstellen
    SeqEnsureTabLVs()

    if SeqCurrentTab > SeqAllTabs.Length
        SeqCurrentTab := SeqAllTabs.Length
    SeqList := SeqAllTabs[SeqCurrentTab]

    SeqRebuildTabBar()
    if SeqTabLVNames.Length >= SeqCurrentTab
        SeqCurrentLV := GuiSeqManager[SeqTabLVNames[SeqCurrentTab]]
    SeqRefreshList()

    if SeqList.Length = 0 && SeqFolder != "" {
        SeqLoadAllFromFolder(SeqFolder)
    }
}

; ─────────────────────────────────────────────
; Geordnete Sequenzliste im INI speichern
; ─────────────────────────────────────────────
SeqSaveList() {
    global SeqIniFile, SeqAllTabs, SeqTabNames

    tempPath := SeqIniFile ".tmp-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount
    try {
        if FileExist(SeqIniFile) && FileGetSize(SeqIniFile) > 0
            FileAppend(FileRead(SeqIniFile, "CP0"), tempPath, "UTF-16")
        else
            FileAppend(Chr(13) Chr(10), tempPath, "UTF-16")
        IniDelete(tempPath, "SeqTabs")
        for section in StrSplit(IniRead(tempPath, , , ""), Chr(10), Chr(13)) {
            if RegExMatch(section, "i)^SeqTab[0-9]+$")
                IniDelete(tempPath, section)
        }
        IniWrite(SeqAllTabs.Length, tempPath, "SeqTabs", "Count")

        for tabIndex, entries in SeqAllTabs {
            IniWrite(Chr(34) SeqTabNames[tabIndex] Chr(34), tempPath, "SeqTabs", "Name" tabIndex)
            section := "SeqTab" tabIndex
            IniWrite(entries.Length, tempPath, section, "Count")

            for index, entry in entries {
                kind := entry.Get("type", "file")
                IniWrite(kind, tempPath, section, "Type" index)
                IniWrite(Chr(34) entry["name"] Chr(34), tempPath, section, "Name" index)
                if kind = "pause"
                    IniWrite(entry.Get("duration", 1000), tempPath, section, "Duration" index)
                else if kind != "comment"
                    IniWrite(entry["file"], tempPath, section, "File" index)
            }
        }

        FileMove(tempPath, SeqIniFile, 1)
        return true
    } catch as err {
        SeqUpdateStatus("Sequenzliste konnte nicht gespeichert werden: " err.Message)
        return false
    } finally {
        if FileExist(tempPath)
            try FileDelete(tempPath)
    }
}

; ─────────────────────────────────────────────
; Gespeicherte Sequenzliste beim Start laden
; ─────────────────────────────────────────────
SeqSavedTabCount(path) {
    rawCount := IniRead(path, "SeqTabs", "Count", "")
    sections := Map()
    sections.CaseSense := "Off"
    for section in StrSplit(IniRead(path, , , ""), Chr(10), Chr(13))
        sections[section] := true
    limit := TryParseIntegerSetting(rawCount, 0, &savedCount) ? Min(savedCount, sections.Count) : sections.Count
    count := 0
    while count < limit && sections.Has("SeqTab" (count + 1))
        count++
    return count
}

SeqSavedEntryCount(path, section) {
    if !FileExist(path)
        return 0
    rawCount := IniRead(path, section, "Count", "")
    if TryParseIntegerSetting(rawCount, 0, &count) && (!count || count <= FileGetSize(path))
        return count

    rows := Map()
    inSection := false
    for line in StrSplit(FileRead(path, "CP0"), Chr(10), Chr(13)) {
        if RegExMatch(line, "^\s*\[([^\]]+)\]", &header) {
            inSection := header[1] = section
            continue
        }
        if inSection && RegExMatch(line, "i)^\s*(?:Type|File|Name|Duration)([1-9][0-9]*)\s*=", &key)
            rows[key[1]] := true
    }
    count := 0
    while rows.Has(String(count + 1))
        count++
    return count
}

SeqLoadSavedList() {
    global SeqList, SeqIniFile, SeqAllTabs, SeqTabNames, SeqCurrentTab

    ; ── Neues Multi-Tab-Format ──
    tabCount := SeqSavedTabCount(SeqIniFile)

    if tabCount > 0 {
        SeqAllTabs  := []
        SeqTabNames := []
        tabIdx := 1
        while tabIdx <= tabCount {
            tabName := "Tab " tabIdx
            try {
                tabName := IniRead(SeqIniFile, "SeqTabs", "Name" tabIdx, tabName)
            } catch {
            }
            SeqTabNames.Push(tabName)
            tabArr  := []
            section := "SeqTab" tabIdx
            cnt := SeqSavedEntryCount(SeqIniFile, section)
            j := 1
            while j <= cnt {
                try {
                    sType := IniRead(SeqIniFile, section, "Type" j, "file")
                    if sType = "comment" {
                        nm := IniRead(SeqIniFile, section, "Name" j, "Kommentar")
                        tabArr.Push(Map("type", "comment", "name", nm, "status", ""))
                    } else if sType = "pause" {
                        dur  := SeqParsePauseDuration(IniRead(SeqIniFile, section, "Duration" j, "1000"), 1000)
                        secs := Round(dur / 1000, 1)
                        tabArr.Push(Map("type", "pause", "duration", dur, "name", IniRead(SeqIniFile, section, "Name" j, "Pause " secs "s"), "status", ""))
                    } else {
                        file := IniRead(SeqIniFile, section, "File" j, "")
                        if file != "" {
                            tabArr.Push(Map("file", file, "name", IniRead(SeqIniFile, section, "Name" j, SeqBasename(file)),
                                "count", SeqGetActionCount(file), "status", FileExist(file) ? "Wartet" : "Datei fehlt", "type", "file"))
                        }
                    }
                } catch {
                }
                j++
            }
            SeqAllTabs.Push(tabArr)
            tabIdx++
        }
        if SeqAllTabs.Length = 0 {
            SeqAllTabs  := [[], [], []]
            SeqTabNames := ["Tab 1", "Tab 2", "Tab 3"]
        }
        SeqCurrentTab := 1
        SeqList       := SeqAllTabs[1]
        return
    }

    ; ── Altes Format (SeqList-Sektion) – Fallback / Migration ──
    oldCount := SeqSavedEntryCount(SeqIniFile, "SeqList")
    if oldCount <= 0
        return

    i := 1
    while i <= oldCount {
        try {
            sType := IniRead(SeqIniFile, "SeqList", "Type" i, "file")
            if sType = "comment" {
                nm := IniRead(SeqIniFile, "SeqList", "Name" i, "Kommentar")
                SeqList.Push(Map("type", "comment", "name", nm, "status", ""))
            } else if sType = "pause" {
                dur  := SeqParsePauseDuration(IniRead(SeqIniFile, "SeqList", "Duration" i, "1000"), 1000)
                secs := Round(dur / 1000, 1)
                SeqList.Push(Map("type", "pause", "duration", dur, "name", IniRead(SeqIniFile, "SeqList", "Name" i, "Pause " secs "s"), "status", ""))
            } else {
                file := IniRead(SeqIniFile, "SeqList", "File" i, "")
                if file != "" {
                    SeqList.Push(Map("file", file, "name", IniRead(SeqIniFile, "SeqList", "Name" i, SeqBasename(file)),
                        "count", SeqGetActionCount(file), "status", FileExist(file) ? "Wartet" : "Datei fehlt", "type", "file"))
                }
            }
        } catch {
        }
        i++
    }

    SeqRefreshList()
    SeqSaveList()   ; In neues Format migrieren
}

; ─────────────────────────────────────────────
; Selektierte Sequenz(en) entfernen
; ─────────────────────────────────────────────
SeqRemove(*) {
    global SeqList, SeqCurrentLV
    if !IsObject(SeqCurrentLV)
        return

    lv := SeqCurrentLV
    state := lv.GetNext(0, "Checked") ? "Checked" : ""
    rows := Map()
    row := 0
    while row := lv.GetNext(row, state) {
        if row <= SeqList.Length
            rows[row] := true
    }
    if !rows.Count {
        ShowWarning("Bitte eine oder mehrere Sequenzen anhaken oder auswählen.")
        return
    }

    RemoveMatchingActions(SeqList, (entry, index) => rows.Has(index))
    SeqRefreshList()
}

; ─────────────────────────────────────────────
; Selektion → Checkbox automatisch setzen.
; Wird als ItemSelect-Event-Handler an allen SeqListViews registriert.
; LVM_GETITEMSTATE (0x102A) prüft ob die Zeile wirklich selektiert ist,
; damit Deselektierungen die Checkbox NICHT setzen.
; LVIS_SELECTED = 0x0002
; ─────────────────────────────────────────────
SeqLVItemSelect(LV, row, selected) {
    if row >= 1 && selected
        LV.Modify(row, "Check")
}

; ─────────────────────────────────────────────
; Zu verschiebende Zeile ermitteln:
;   Genau 1 Checkbox gesetzt  → diese Zeile verwenden
;   Sonst                     → erste selektierte (blau markierte) Zeile
; ─────────────────────────────────────────────
SeqGetMoveRow(LV) {
    row := LV.GetNext(0, "Checked")
    if row
        return LV.GetNext(row, "Checked") ? 0 : row
    row := LV.GetNext(0)
    return row && !LV.GetNext(row) ? row : 0
}

; ─────────────────────────────────────────────
; Sequenz nach oben
; ─────────────────────────────────────────────
SeqMoveUp(*) {
    global SeqList, SeqCurrentLV

    LV  := SeqCurrentLV
    row := SeqGetMoveRow(LV)
    if !row || row <= 1
        return

    tmp              := SeqList[row - 1]
    SeqList[row - 1] := SeqList[row]
    SeqList[row]     := tmp

    SeqRefreshList()
    LV.Modify(row - 1, "Check Select Focus Vis")
}

; ─────────────────────────────────────────────
; Sequenz nach unten
; ─────────────────────────────────────────────
SeqMoveDown(*) {
    global SeqList, SeqCurrentLV

    LV  := SeqCurrentLV
    row := SeqGetMoveRow(LV)
    if !row || row >= SeqList.Length
        return

    tmp              := SeqList[row + 1]
    SeqList[row + 1] := SeqList[row]
    SeqList[row]     := tmp

    SeqRefreshList()
    LV.Modify(row + 1, "Check Select Focus Vis")
}

; ─────────────────────────────────────────────
; Markierte Sequenzen zu einem SET zusammenfassen
; ─────────────────────────────────────────────
SeqMergeToSet(*) {
    global GuiSeqManager, SeqList, SeqIniFile, SeqCurrentLV

    LV := SeqCurrentLV

    selectedIndices := []
    row := 0
    loop {
        row := LV.GetNext(row, "Checked")
        if !row
            break
        selectedIndices.Push(row)
    }

    if selectedIndices.Length = 0 {
        if SeqList.Length = 0 {
            ShowWarning("Keine Sequenzen in der Liste.")
            return
        }
        result := ShowYesNo("Keine Sequenzen per Checkbox ausgewählt.`n`nAlle " SeqList.Length " Sequenzen zusammenfassen?")
        if result != "Yes"
            return
        i := 1
        while i <= SeqList.Length {
            selectedIndices.Push(i)
            i++
        }
    }

    if selectedIndices.Length < 2 {
        ShowWarning("Bitte mindestens 2 Sequenzen auswählen.")
        return
    }

    source := SeqList
    entries := []
    for index in selectedIndices
        entries.Push(source[index])
    merged := SeqBuildSet(entries)
    details := ""
    for index, failure in merged.Skipped {
        if index > 8 {
            details .= Chr(10) "Weitere übersprungene Dateien: " (merged.Skipped.Length - 8)
            break
        }
        details .= Chr(10) "Zeile " selectedIndices[failure.Index] " · " failure.Name " – " failure.Message
    }
    if !merged.HasActions {
        ShowWarning("Keine abspielbaren Aktionen oder Pausen gefunden." details)
        return
    }
    mergedActions := merged.Actions
    defaultName := merged.Folder "\SET_" FormatTime(, "yyyyMMdd_HHmmss") ".json"

    SeqSuspendTopmost()
    try outFile := FileSelect("S16", defaultName, "SET speichern unter...", "JSON-Dateien (*.json)")
    finally SeqRestoreTopmost()

    if !outFile || SeqList != source
        return

    outFile := ConfirmJsonSavePath(outFile)
    if !outFile || SeqList != source
        return

    ; Jetzt Dateinamen im Start-Kommentar nachtragen
    mergedActions[1]["Text"] := "=== SET START: " SeqBasename(outFile) " ==="

    try {
        WriteActionFile(outFile, mergedActions)
    } catch as err {
        ShowError("Fehler beim Speichern:`n" err.Message)
        return
    }

    count   := mergedActions.Length
    setName := SeqBasename(outFile)

    SeqList.Push(Map(
        "file",   outFile,
        "name",   setName,
        "count",  count,
        "status", "Wartet"
    ))

    SeqRefreshList()
    ShowInfo("SET erstellt: " setName "`n" count " Einträge. Übersprungene Dateien: " merged.Skipped.Length "." details)
}

; ─────────────────────────────────────────────
; Alle Sequenzen abspielen
; ─────────────────────────────────────────────
SeqBuildSet(entries) {
    actions := [Map("Type", "Comment", "Text", "=== SET START ===")]
    hasActions := false
    skipped := []
    folder := ""
    for index, entry in entries {
        switch entry.Get("type", "file") {
            case "comment":
                actions.Push(Map("Type", "Comment", "Text", entry["name"]))
            case "pause":
                actions.Push(Map("Type", "Delay", "Time", Max(0, entry.Get("duration", 1000))))
                hasActions := true
            case "file":
                try {
                    imported := SeqReadPlayableActions(entry["file"])
                } catch Error as err {
                    skipped.Push({Index: index, Name: entry.Get("name", ""), Message: err.Message})
                    continue
                }
                if folder = ""
                    SplitPath(entry["file"], , &folder)
                actions.Push(Map("Type", "Comment", "Text", "--- Beginn: " entry["name"] " ---"))
                sourceScreen := imported.HasOwnProp("RecorderScreenProfile")
                    ? imported.RecorderScreenProfile["Source"] : ""
                for action in imported {
                    if IsObject(sourceScreen) && !action.Has("SourceScreen")
                        && (action.Has("X") || action["Type"] = "Drag") {
                        action := action.Clone()
                        action["SourceScreen"] := sourceScreen.Clone()
                    }
                    actions.Push(action)
                }
                actions.Push(Map("Type", "Comment", "Text", "--- Ende: " entry["name"] " ---"))
                hasActions := true
        }
    }
    actions.Push(Map("Type", "Comment", "Text", "=== SET ENDE ==="))
    return {Actions: actions, HasActions: hasActions, Folder: folder != "" ? folder : A_ScriptDir, Skipped: skipped}
}

SeqPlayAll(*) {
    global SeqList
    SeqPlayEntries(SeqList)
}

SeqPlayChecked(lv) {
    global SeqList, SeqCurrentLV
    if lv != SeqCurrentLV
        return
    entries := []
    row := 0
    while row := lv.GetNext(row, "Checked") {
        if row <= SeqList.Length
            entries.Push(SeqList[row])
    }
    if !entries.Length
        return
    SeqPlayEntries(entries)
}

SeqFailedEntries(entries) {
    failed := []
    for entry in entries {
        if entry.Get("status", "") = "Fehler"
            failed.Push(entry)
    }
    return failed
}

SeqRetryFailed(source) {
    global SeqList
    if source != SeqList
        return
    failed := SeqFailedEntries(source)
    if failed.Length
        SeqPlayEntries(failed)
}

SeqPlayEntries(entries) {
    global SeqPlaybackList, IsSeqPlaying, SeqCurrentIndex, IsReplaying, IsRecording

    if IsRecording {
        ShowWarning("Aufnahme läuft — bitte zuerst stoppen.")
        return
    }

    if entries.Length = 0 {
        ShowWarning("Keine Sequenzen geladen.")
        return
    }

    if IsSeqPlaying || IsReplaying {
        ShowInfo("Wiedergabe läuft bereits!")
        return
    }

    i := 1
    while i <= entries.Length {
        entries[i]["status"] := "Wartet"
        i++
    }

    ReadPlaybackSettings()
    SeqPlaybackList := entries.Clone()
    IsSeqPlaying    := true
    SeqCurrentIndex := 0
    SeqRefreshList()
    SeqLoadNext()
}

; ─────────────────────────────────────────────
; Nächste Sequenz laden und starten
; ─────────────────────────────────────────────
HasCompletedPause(entries) {
    for entry in entries {
        if entry.Get("type", "file") = "pause" && entry["status"] = "Fertig"
            return true
    }
    return false
}

SeqLoadNext() {
    global SeqPlaybackList, SeqCurrentIndex, IsSeqPlaying, SeqRepeatMode
    global GuiSeqManager

    if !IsSeqPlaying
        return
    SeqCurrentIndex += 1

    if SeqCurrentIndex > SeqPlaybackList.Length {
        played := 0
        skipped := 0
        for entry in SeqPlaybackList {
            if entry.Get("type", "file") != "file"
                continue
            if entry["status"] = "Fertig"
                played++
            else if entry["status"] = "Fehler"
                skipped++
        }
        if SeqRepeatMode && (played > 0 || HasCompletedPause(SeqPlaybackList)) {
            i := 1
            while i <= SeqPlaybackList.Length {
                SeqPlaybackList[i]["status"] := "Wartet"
                i++
            }
            SeqCurrentIndex := 0
            SeqRefreshList()
            SetTimer(SeqLoadNext, -1)
            return
        }
        IsSeqPlaying    := false
        SeqCurrentIndex := 0
        SeqUpdateStatus("Sequenzlauf beendet. Abgespielt: " played ", übersprungen: " skipped ".")
        SeqRefreshList()
        SoundBeep(800, 200)
        return
    }

    if SeqCurrentIndex < 1 || SeqCurrentIndex > SeqPlaybackList.Length {
        IsSeqPlaying := false
        SeqUpdateStatus("Fehler: Ungültiger Sequenzindex.")
        return
    }

    s     := SeqPlaybackList[SeqCurrentIndex]
    sType := s.Has("type") ? s["type"] : "file"

    ; Kommentar-Eintrag: sofort überspringen
    if sType = "comment" {
        SeqPlaybackList[SeqCurrentIndex]["status"] := "Fertig"
        SeqRefreshList()
        SetTimer(SeqLoadNext, -1)
        return
    }

    ; Pause-Eintrag: Timer-basierte Wartezeit
    if sType = "pause" {
        dur := s.Has("duration") ? s["duration"] : 1000
        SeqPlaybackList[SeqCurrentIndex]["status"] := "Läuft..."
        SeqUpdateStatus("Pause: " Round(dur / 1000, 1) "s...")
        SeqRefreshList()
        SetTimer(SeqOnPauseFinished, -Max(1, dur))
        return
    }

    if !s.Has("file") || !FileExist(s["file"]) {
        SeqPlaybackList[SeqCurrentIndex]["status"] := "Fehler"
        s["error"] := "Datei nicht gefunden: " s.Get("file", s.Get("name", "unbekannt"))
        SeqUpdateStatus(s["error"])
        SeqRefreshList()
        SetTimer(SeqLoadNext, -1)
        return
    }

    try {
        playbackActions := SeqReadPlayableActions(s["file"])
    } catch Error as err {
        SeqPlaybackList[SeqCurrentIndex]["status"] := "Fehler"
        s["error"] := "Datei übersprungen: " s["name"] " – " err.Message
        SeqUpdateStatus(s["error"])
        SeqRefreshList()
        SetTimer(SeqLoadNext, -1)
        return
    }

    SeqPlaybackList[SeqCurrentIndex]["status"] := "Läuft..."
    SeqUpdateStatus("Sequenz " SeqCurrentIndex "/" SeqPlaybackList.Length ": " s["name"])
    SeqRefreshList()
    StartPlayback(playbackActions, false, ScreenProfileForFile(s["file"], playbackActions))
}

; ─────────────────────────────────────────────
; Wird von PlaybackTimer aufgerufen wenn fertig
; ─────────────────────────────────────────────
SeqOnSequenceFinished() {
    global SeqPlaybackList, SeqCurrentIndex

    if SeqCurrentIndex >= 1 && SeqCurrentIndex <= SeqPlaybackList.Length {
        SeqPlaybackList[SeqCurrentIndex]["status"] := "Fertig"
        SeqRefreshList()
    }

    SeqLoadNext()
}

; Pause-Timer abgelaufen → weiter mit nächster Sequenz
SeqOnPauseFinished() {
    global SeqPlaybackList, SeqCurrentIndex, IsSeqPlaying

    if !IsSeqPlaying
        return
    if SeqCurrentIndex >= 1 && SeqCurrentIndex <= SeqPlaybackList.Length {
        SeqPlaybackList[SeqCurrentIndex]["status"] := "Fertig"
        SeqRefreshList()
    }
    SeqLoadNext()
}

; ─────────────────────────────────────────────
; Wiedergabe abbrechen
; ─────────────────────────────────────────────
SeqAbort(errorMessage := "") {
    global IsSeqPlaying, SeqCurrentIndex, SeqPlaybackList, StopRequested, IsReplaying, SeqSinglePlaying, GuiMain

    if !IsSeqPlaying && !SeqSinglePlaying
        return

    StopRequested := true
    IsReplaying := false
    IsSeqPlaying := false
    SeqSinglePlaying := false
    SetTimer(PlaybackTimer, 0)
    SetTimer(SeqOnPauseFinished, 0)
    SetTimer(SeqLoadNext, 0)

    if SeqCurrentIndex >= 1 && SeqCurrentIndex <= SeqPlaybackList.Length {
        SeqPlaybackList[SeqCurrentIndex]["status"] := errorMessage = "" ? "Abgebrochen" : "Fehler"
        if errorMessage != ""
            SeqPlaybackList[SeqCurrentIndex]["error"] := errorMessage
        SeqRefreshList()
    }

    SeqCurrentIndex := 0
    status := errorMessage = "" ? "Abgebrochen." : errorMessage
    SeqUpdateStatus(status)
    if IsSet(GuiMain) && IsObject(GuiMain)
        GuiMain["StatusText"].Value := "Status: " status
}

; ─────────────────────────────────────────────
; Loop umschalten
; ─────────────────────────────────────────────
SeqToggleLoop(*) {
    global SeqRepeatMode, GuiSeqManager

    SeqRepeatMode := !SeqRepeatMode

    if IsObject(GuiSeqManager) {
        GuiSeqManager["SeqLoopLabel"].Value :=
            "Loop: " (SeqRepeatMode ? "Aktiv" : "Inaktiv")
    }
}

; ─────────────────────────────────────────────
; ListView neu aufbauen
; ─────────────────────────────────────────────
SeqRefreshList(previousEntry := unset, replacementEntry := unset) {
    global SeqList, SeqCurrentLV

    if !IsObject(SeqCurrentLV)
        return

    LV := SeqCurrentLV
    topIndex := SendMessage(0x1027, 0, 0, LV.Hwnd)  ; LVM_GETTOPINDEX

    static displayedEntries := Map()
    previous := displayedEntries.Get(LV.Hwnd, [])
    checked := Map()
    row := 0
    while row := LV.GetNext(row, "Checked") {
        if row <= previous.Length
            checked[previous[row]] := true
    }
    if IsSet(previousEntry) && checked.Has(previousEntry)
        checked[replacementEntry] := true
    displayedEntries[LV.Hwnd] := SeqList.Clone()

    LV.Delete()

    i := 1
    while i <= SeqList.Length {
        s := SeqList[i]
        sType := s.Has("type") ? s["type"] : "file"

        if sType = "comment" {
            LV.Add("", "", i, "── " s["name"], "", "")
        } else if sType = "pause" {
            st := s.Has("status") ? s["status"] : ""
            if st = "Läuft..."
                statusIcon := ">>> Läuft..."
            else if st = "Fertig"
                statusIcon := "✔  Fertig"
            else
                statusIcon := st
            LV.Add("", "", i, "⏸ " s["name"], "", statusIcon)
        } else {
            st := s["status"]
            if st = "Wartet"
                statusIcon := "Wartet"
            else if st = "Läuft..."
                statusIcon := ">>> Läuft..."
            else if st = "Fertig"
                statusIcon := "✔  Fertig"
            else if st = "Fehler"
                statusIcon := "✖  Fehler"
            else if st = "Abgebrochen"
                statusIcon := "—  Abgebrochen"
            else
                statusIcon := st

            LV.Add("", "", i, s["name"], s["count"], statusIcon)

        }

        if checked.Has(s)
            LV.Modify(i, "Check")

        i++
    }

    ; Spaltenbreiten automatisch an Inhalt anpassen.
    ; Checkbox-Spalte (1) bleibt fix; alle anderen richten sich nach
    ; dem breitesten Wert (inkl. Spaltenüberschrift).
    LV.ModifyCol(1, "26")
    LV.ModifyCol(2, "AutoHdr")
    LV.ModifyCol(3, "AutoHdr")
    LV.ModifyCol(4, "AutoHdr")
    LV.ModifyCol(5, "AutoHdr")

    ; Header-Control explizit neu zeichnen – AutoHdr kann die Spaltenleiste
    ; in versteckten ListViews in einen ungültigen Zustand bringen.
    if SeqList.Length && topIndex > 0 {
        visibleRows := Max(1, SendMessage(0x1028, 0, 0, LV.Hwnd))  ; LVM_GETCOUNTPERPAGE
        bottomIndex := Min(topIndex + visibleRows - 1, SeqList.Length - 1)
        SendMessage(0x1013, bottomIndex, 0, LV.Hwnd)  ; LVM_ENSUREVISIBLE
    }
    SeqForceRedrawLV(LV)
}

; ─────────────────────────────────────────────
; Statustext aktualisieren
; ─────────────────────────────────────────────
SeqUpdateStatus(text) {
    global GuiSeqManager
    if IsObject(GuiSeqManager) {
        GuiSeqManager["SeqStatus"].Value := text
    }
}

; ─────────────────────────────────────────────
; Hilfsfunktionen
; ─────────────────────────────────────────────
SeqReadPlayableActions(path) {
    actions := ReadActionFile(path)
    if !actions.Length
        throw ValueError("Die Aktionsliste ist leer.")
    return actions
}

SeqValidateTab(entries) {
    checked := 0
    failed := 0
    details := ""
    for row, entry in entries {
        if entry.Get("type", "file") != "file"
            continue
        checked++
        path := entry.Get("file", "")
        try {
            SeqReadPlayableActions(path)
        } catch Error as err {
            failed++
            if failed <= 8
                details .= Chr(10) "Zeile " row " · " entry.Get("name", path) " – " err.Message
        }
    }
    if !checked {
        ShowInfo("Dieser Tab enthält keine Aktionsdateien.")
        return
    }
    summary := (checked - failed) " von " checked " Aktionsdateien sind gültig."
    if failed {
        if failed > 8
            details .= Chr(10) "Weitere fehlerhafte Einträge: " (failed - 8)
        ShowError(summary Chr(10) details)
    } else {
        ShowInfo(summary)
    }
}

SeqValidateActionFile(path) {
    try {
        actions := SeqReadPlayableActions(path)
    } catch Error as err {
        ShowError("Aktionsdatei kann nicht abgespielt werden." Chr(10) path Chr(10) err.Message)
        return
    }
    ShowInfo("Aktionsdatei ist gültig. Aktionen: " actions.Length Chr(10) path)
}

SeqGetActionCount(file) {
    count := 0
    try {
        data := ReadActionFile(file)
        if data is Array {
            count := data.Length
        }
    } catch {
    }
    return count
}

SeqBasename(path) {
    return RegExReplace(path, ".*\\", "")
}

; ─────────────────────────────────────────────
; Rechtsklick-Kontextmenü in der Sequenz-Liste
; ─────────────────────────────────────────────
ShowSeqLVContextMenu(LV, rowIndex, isRightClick, x, y) {
    global SeqList

    ctx := Menu()
    ctx.SetColor("White")

    if rowIndex > 0 && rowIndex <= SeqList.Length {
        ctx.Add("Einzeln abspielen`tEnter",  (*) => SeqPlaySingle(rowIndex))
        ctx.Add()
        ctx.Add("Diese Zeile entfernen",           (*) => SeqRemoveSingle(rowIndex))
        ctx.Add()
        ctx.Add("Nach oben",                 (*) => SeqMoveRowDirect(rowIndex, -1))
        ctx.Add("Nach unten",                (*) => SeqMoveRowDirect(rowIndex, +1))
        if rowIndex <= 1
            ctx.Disable("Nach oben")
        if rowIndex >= SeqList.Length
            ctx.Disable("Nach unten")
        ctx.Add()
        isChecked := (LV.GetNext(rowIndex - 1, "Checked") = rowIndex)
        if isChecked {
            ctx.Add("SET-Auswahl entfernen", (*) => LV.Modify(rowIndex, "-Check"))
        } else {
            ctx.Add("Für SET auswählen",     (*) => LV.Modify(rowIndex, "Check"))
        }
        ctx.Add()
        ctx.Add("Umbenennen...",             (*) => SeqRename(rowIndex))
        s0 := SeqList[rowIndex]
        if s0.Get("status", "") = "Fehler" && s0.Has("error") {
            errorDetail := s0["error"]
            ctx.Add("Wiedergabefehler anzeigen", (*) => ShowError(errorDetail))
        }
        if s0.Has("file") {
            ctx.Add("Aktionen bearbeiten...", (*) => SeqEditActions(rowIndex))
            ctx.Add("Aktionsdatei prüfen", (*) => SeqValidateActionFile(s0["file"]))
            ctx.Add("Datei neu verknüpfen...", (*) => SeqRelinkFile(rowIndex))
        } else if s0.Get("type", "") = "pause" {
            ctx.Add("Pausendauer ändern...", (*) => SeqAddPause(rowIndex, true))
        }
        ctx.Add()
        ctx.Add("Duplizieren",               (*) => SeqDuplicate(rowIndex))
        ctx.Add()
        ctx.Add("Kommentar einfügen...",     (*) => SeqAddComment(rowIndex))
        ctx.Add("Pause einfügen...",         (*) => SeqAddPause(rowIndex))
    } else {
        ctx.Add("Dateien hinzufügen...",     SeqAdd)
        ctx.Add("Ordner laden...",           SeqLoadFolder)
        ctx.Add()
        ctx.Add("Kommentar anhängen...",     (*) => SeqAddComment())
        ctx.Add("Pause anhängen...",         (*) => SeqAddPause())
    }

    ctx.Add()
    ctx.Add("Angehakte Einträge abspielen", (*) => SeqPlayChecked(LV))
    if !LV.GetNext(0, "Checked")
        ctx.Disable("Angehakte Einträge abspielen")
    source := SeqList
    ctx.Add("Fehlerhafte Einträge erneut abspielen", (*) => SeqRetryFailed(source))
    if !SeqFailedEntries(source).Length
        ctx.Disable("Fehlerhafte Einträge erneut abspielen")
    ctx.Add("Sequenz-Tab prüfen", (*) => SeqValidateTab(SeqList))
    ctx.Show(x, y)
}

; Einzelne Sequenz per Kontextmenü entfernen
SeqRemoveSingle(rowIndex) {
    global SeqList
    if rowIndex >= 1 && rowIndex <= SeqList.Length {
        SeqList.RemoveAt(rowIndex)
        SeqRefreshList()
    }
}

; Sequenz duplizieren (Kontextmenü)
SeqDuplicate(rowIndex) {
    global SeqList
    if rowIndex < 1 || rowIndex > SeqList.Length
        return
    src  := SeqList[rowIndex]
    copy := Map()
    for k, v in src
        copy[k] := v
    copy["status"] := "Wartet"
    SeqList.InsertAt(rowIndex + 1, copy)
    SeqRefreshList()
}

; Kommentar-Eintrag einfügen (nach rowIndex)
SeqAddComment(rowIndex := 0) {
    global SeqList
    source := SeqList
    if rowIndex < 0 || rowIndex > source.Length
        return
    anchor := rowIndex ? source[rowIndex] : ""
    SeqSuspendTopmost()
    try result := InputBox("Kommentartext:", "Kommentar einfügen", "w300 h100")
    finally SeqRestoreTopmost()
    if result.Result != "OK" || Trim(result.Value) = "" || SeqList != source
        return
    if rowIndex && (rowIndex > source.Length || source[rowIndex] != anchor)
        return
    entry := Map("type", "comment", "name", Trim(result.Value), "status", "")
    source.InsertAt(rowIndex ? rowIndex + 1 : source.Length + 1, entry)
    SeqRefreshList()
}

; Pause-Eintrag einfügen (nach rowIndex)
SeqAddPause(rowIndex := 0, edit := false) {
    global SeqList
    source := SeqList
    if rowIndex < 0 || rowIndex > source.Length
        return
    if edit && (!rowIndex || source[rowIndex].Get("type", "") != "pause")
        return
    original := rowIndex ? source[rowIndex] : ""
    title := edit ? "Pausendauer ändern" : "Pause einfügen"
    duration := edit ? original.Get("duration", 1000) : 1000
    SeqSuspendTopmost()
    try {
        result := InputBox("Pausendauer in ganzen Millisekunden:", title, "w320 h105", duration)
    } finally {
        SeqRestoreTopmost()
    }
    if result.Result != "OK" || SeqList != source
        return
    if rowIndex && (rowIndex > source.Length || source[rowIndex] != original)
        return
    try {
        entry := SeqMakePause(result.Value, edit ? original : "")
    } catch as err {
        ShowWarning(err.Message)
        return
    }
    if edit {
        source[rowIndex] := entry
        SeqRefreshList(original, entry)
    } else {
        position := rowIndex ? rowIndex + 1 : source.Length + 1
        source.InsertAt(position, entry)
        SeqRefreshList()
    }
}

SeqParsePauseDuration(value, fallback := unset) {
    value := LTrim(Trim(value), "0")
    if RegExMatch(value, "^[1-9][0-9]{0,9}$") && Integer(value) <= 0xFFFFFFFF
        return Integer(value)
    if IsSet(fallback)
        return fallback
    throw ValueError("Bitte eine ganze Pausendauer von 1 bis 4294967295 ms eingeben.")
}

SeqMakePause(value, original := "") {
    duration := SeqParsePauseDuration(value)
    name := "Pause " duration " ms"
    if IsObject(original) && !RegExMatch(original["name"], "^Pause \d+(?:\.\d+)?\s*(?:s|ms)$")
        name := original["name"]
    return Map("type", "pause", "duration", duration, "name", name, "status", "")
}

; Sequenz umbenennen
SeqRelinkFile(rowIndex) {
    global SeqList

    if rowIndex < 1 || rowIndex > SeqList.Length || !SeqList[rowIndex].Has("file")
        return
    source := SeqList
    entry := source[rowIndex]
    SplitPath(entry["file"], , &folder)

    SeqSuspendTopmost()
    try {
        path := FileSelect("3", DirExist(folder) ? folder : A_ScriptDir,
            "Aktionsdatei neu verknüpfen", "JSON-Dateien (*.json)")
    } finally {
        SeqRestoreTopmost()
    }

    if path = "" || SeqList != source || rowIndex > source.Length || source[rowIndex] != entry
        return
    try {
        source[rowIndex] := SeqMakeRelinkedEntry(entry, path)
    } catch as err {
        ShowError("Datei konnte nicht verknüpft werden:`n" err.Message)
        return
    }
    SeqRefreshList(entry, source[rowIndex])
}

SeqMakeRelinkedEntry(entry, path) {
    actions := ReadActionFile(path)
    replacement := entry.Clone()
    replacement["file"] := path
    replacement["count"] := actions.Length
    replacement["status"] := "Wartet"
    return replacement
}

SeqRename(rowIndex) {
    global SeqList
    source := SeqList
    if rowIndex < 1 || rowIndex > source.Length
        return
    entry := source[rowIndex]
    SeqSuspendTopmost()
    try result := InputBox("Neuer Name:", "Umbenennen", "w300 h100", entry.Get("name", ""))
    finally SeqRestoreTopmost()
    name := Trim(result.Value)
    if result.Result != "OK" || name = ""
        return
    if SeqList != source || rowIndex > source.Length || source[rowIndex] != entry {
        ShowWarning("Der Sequenzeintrag wurde inzwischen verschoben oder ersetzt. Bitte erneut öffnen.")
        return
    }
    entry["name"] := name
    SeqRefreshList()
}

; Aktionen einer Sequenz im Hauptfenster bearbeiten.
; Regel: Existiert bereits ein Tab mit dieser Datei → nur Fokus setzen.
;        Sonst: neuen Tab anlegen und Datei dort laden.
SeqEditActions(rowIndex) {
    global SeqList, ActionsList, GuiMain, IsRecording
    global MainAllTabs, MainAllTabPaths, MainCurrentTab, MainTabCtrl

    if IsRecording
        return
    if rowIndex < 1 || rowIndex > SeqList.Length
        return
    s := SeqList[rowIndex]
    ; Kommentar- und Pause-Einträge haben keine Datei → stillschweigend abbrechen
    if s.Has("type") && (s["type"] = "comment" || s["type"] = "pause")
        return
    if !s.Has("file") || !FileExist(s["file"]) {
        ShowWarning("Datei nicht gefunden:`n" (s.Has("file") ? s["file"] : "unbekannt"))
        return
    }
    targetFile := s["file"]

    ; ── Tab mit dieser Datei suchen ──
    existingTab := 0
    loop MainAllTabPaths.Length {
        if MainAllTabPaths[A_Index] = targetFile {
            existingTab := A_Index
            break
        }
    }

    if existingTab > 0 {
        ; Tab existiert bereits → nur dorthin wechseln
        MainTabCtrl.Value := existingTab
        MainSwitchTabFromCtrl()
    } else {
        ; Keinen passenden Tab gefunden → neuen Tab anlegen
        try {
            loadedActions := ReadActionFile(targetFile)
            if !(loadedActions is Array) {
                ShowWarning("Datei enthält keine gültige Aktionsliste!")
                return
            }
        } catch as err {
            ShowError("Fehler beim Laden:`n" err.Message)
            return
        }
        if MainAllTabs.Length >= 16 {
            ShowWarning("Die Datei kann nicht geöffnet werden. Es sind bereits 16 Tabs geöffnet.")
            return
        }
        MainNewTab()
        ActionsList := loadedActions
        global MainScreenProfiles, MainCurrentTab
        MainScreenProfiles[MainCurrentTab] := loadedActions.HasOwnProp("RecorderScreenProfile")
            ? loadedActions.RecorderScreenProfile : NewScreenProfile()
        MainAllTabs[MainCurrentTab] := ActionsList
        SetCurrentFile(targetFile)
        UpdateActionsList()

        ; Tab-Label auf ersten 6 Zeichen des Dateinamens kürzen;
        ; vollen Namen als Hover-Tooltip merken.
        SplitPath(targetFile, , , , &nameNoExt)
        shortLabel := SubStr(nameNoExt, 1, 6)
        global MainTabTooltips
        MainTabTooltips[MainCurrentTab] := nameNoExt
        MainSilentRenameTab(MainCurrentTab, shortLabel)
    }

    if IsObject(GuiMain) {
        try GuiMain.Show()
        try WinActivate("ahk_id " GuiMain.Hwnd)
    }
}

; Zeile direkt verschieben (für Kontextmenü)
SeqMoveRowDirect(rowIndex, direction) {
    global SeqList, GuiSeqManager, SeqCurrentLV
    newIndex := rowIndex + direction
    if newIndex < 1 || newIndex > SeqList.Length
        return
    tmp               := SeqList[newIndex]
    SeqList[newIndex] := SeqList[rowIndex]
    SeqList[rowIndex] := tmp
    SeqRefreshList()
    if IsObject(SeqCurrentLV)
        SeqCurrentLV.Modify(newIndex, "Select Focus Vis")
}

; Einzelne Sequenz abspielen (Enter oder Kontextmenü)
SeqPlaySelectedRow() {
    global SeqCurrentLV
    if !IsObject(SeqCurrentLV)
        return
    row := SeqCurrentLV.GetNext(0)
    if row > 0
        SeqPlaySingle(row)
}

SeqPlaySingle(rowIndex) {
    global SeqList, IsRecording, IsReplaying, IsSeqPlaying, RepeatMode, StopRequested, SeqSinglePlaying

    if IsRecording {
        ShowWarning("Aufnahme läuft — bitte zuerst stoppen.")
        return
    }
    if IsReplaying || IsSeqPlaying {
        ShowInfo("Wiedergabe läuft bereits!")
        return
    }
    if rowIndex < 1 || rowIndex > SeqList.Length
        return

    s     := SeqList[rowIndex]
    sType := s.Has("type") ? s["type"] : "file"
    if sType != "file" {
        ShowInfo("Kommentar- und Pause-Einträge können nicht einzeln abgespielt werden.")
        return
    }
    if !s.Has("file") || !FileExist(s["file"]) {
        ShowWarning("Datei nicht gefunden:`n" (s.Has("file") ? s["file"] : "unbekannt"))
        return
    }
    try {
        playbackActions := ReadActionFile(s["file"])
        if !playbackActions.Length {
            ShowWarning("Die Aktionsdatei enthält keine Aktionen.")
            return
        }
    } catch as err {
        ShowError("Fehler beim Laden:`n" err.Message)
        return
    }

    RepeatMode := false
    SeqSinglePlaying := true
    StartPlayback(playbackActions, true, ScreenProfileForFile(s["file"], playbackActions))
    if StopRequested || !IsReplaying
        return
    SeqUpdateStatus("Einzelwiedergabe: " s["name"])
}

; Prüft ob die SeqManager-ListView den Fokus hat
IsSeqLVFocused() {
    global GuiSeqManager, SeqCurrentLV
    if !IsObject(GuiSeqManager)
        return false
    if !WinActive("ahk_id " GuiSeqManager.Hwnd)
        return false
    if !IsObject(SeqCurrentLV)
        return false
    focusedHwnd := DllCall("GetFocus", "Ptr")
    return (focusedHwnd = SeqCurrentLV.Hwnd)
}

; ─────────────────────────────────────────────
; Drag & Drop für SeqListView
; ─────────────────────────────────────────────
SetupSeqLVDragDrop() {
    OnMessage(0x004E, SeqLV_OnNotify_Drag)
    OnMessage(0x004E, SeqLV_CustomDraw)
}

SeqLV_CustomDraw(wParam, lParam, msg, hwnd) {
    global GuiSeqManager, SeqLVDragging, SeqLVDragRow, SeqLVDragTargetRow, SeqCurrentLV

    static NM_CUSTOMDRAW        := -12
    static CDDS_PREPAINT        := 0x1
    static CDDS_ITEMPREPAINT    := 0x10001
    static CDRF_DODEFAULT       := 0x0
    static CDRF_NOTIFYITEMDRAW  := 0x20
    static CDRF_NEWFONT         := 0x2

    if !IsObject(GuiSeqManager)
        return
    if !IsObject(SeqCurrentLV)
        return
    LV := SeqCurrentLV

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
        if SeqLVDragging && row = SeqLVDragRow {
            NumPut("UInt", 0xFFFFFF,   lParam, 80)
            NumPut("UInt", 0x000082FF, lParam, 84)
            return CDRF_NEWFONT
        }
        ; Zielzeile: hellgrün
        if SeqLVDragging && SeqLVDragTargetRow > 0 && row = SeqLVDragTargetRow && SeqLVDragTargetRow != SeqLVDragRow {
            NumPut("UInt", 0x000000,   lParam, 80)
            NumPut("UInt", 0x00B4E6B4, lParam, 84)
            return CDRF_NEWFONT
        }
    }

    return CDRF_DODEFAULT
}

SeqLV_OnNotify_Drag(wParam, lParam, msg, hwnd) {
    global GuiSeqManager, SeqLVDragRow, SeqLVDragging, SeqCurrentLV
    static LVN_BEGINDRAG := -109

    if !IsObject(GuiSeqManager)
        return
    if !IsObject(SeqCurrentLV)
        return
    LV := SeqCurrentLV

    hwndFrom := NumGet(lParam, 0, "Ptr")
    if hwndFrom != LV.Hwnd
        return

    code := NumGet(lParam, 16, "Int")
    if code != LVN_BEGINDRAG
        return

    SeqLVDragRow  := NumGet(lParam, 24, "Int") + 1
    SeqLVDragging := true
    SetTimer(SeqLVDragTimer, 16)
    return 0
}

SeqLVDragTimer(*) {
    global GuiSeqManager, SeqList, SeqLVDragRow, SeqLVDragTargetRow, SeqLVDragging, SeqCurrentLV

    if !SeqLVDragging
        return

    if !IsObject(SeqCurrentLV)
        return
    LV := SeqCurrentLV
    MouseGetPos(&mx, &my)

    pt := Buffer(8)
    NumPut("Int", mx, pt, 0)
    NumPut("Int", my, pt, 4)
    DllCall("ScreenToClient", "Ptr", LV.Hwnd, "Ptr", pt)
    cx := NumGet(pt, 0, "Int")
    cy := NumGet(pt, 4, "Int")

    LVHTI := Buffer(24, 0)
    NumPut("Int", cx, LVHTI, 0)
    NumPut("Int", cy, LVHTI, 4)
    result := SendMessage(0x1012, 0, LVHTI.Ptr, LV.Hwnd)

    if !GetKeyState("LButton", "P") {
        SeqLVDragging      := false
        SeqLVDragTargetRow := 0
        SetTimer(SeqLVDragTimer, 0)
        ToolTip()
        DllCall("InvalidateRect", "Ptr", LV.Hwnd, "Ptr", 0, "Int", 1)

        if result < 0
            return
        targetRow := result + 1
        if targetRow = SeqLVDragRow || targetRow < 1 || targetRow > SeqList.Length
            return

        tmp := SeqList.RemoveAt(SeqLVDragRow)
        SeqList.InsertAt(targetRow, tmp)
        SeqRefreshList()
        LV.Modify(targetRow, "Select Focus")
        return
    }

    newTarget := (result >= 0) ? result + 1 : 0
    if newTarget != SeqLVDragTargetRow {
        SeqLVDragTargetRow := newTarget
        DllCall("InvalidateRect", "Ptr", LV.Hwnd, "Ptr", 0, "Int", 1)
    }

    if result >= 0 {
        targetRow := result + 1
        ToolTip("Verschiebe Zeile " SeqLVDragRow " → Position " targetRow, mx + 12, my + 12)
    }
}
