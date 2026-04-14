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
global SeqList          := []
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
    global GuiSeqManager, GuiMain

    if IsObject(GuiMain)
        WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)

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

    ; ── GroupBox: Sequenzliste ──
    GuiSeqManager.SetFont("s10")
    GuiSeqManager.AddGroupBox("x8 y+8 w594 h308 Section cBlue", "Sequenzliste")
    GuiSeqManager.SetFont("s9")

    GuiSeqManager.AddText("xs+8 ys+20 w576 cGray",
        "Checkbox = SET  |  Rechtsklick = Kontextmenü  |  Entf = Entfernen  |  Enter = Einzeln abspielen  |  Drag & Drop = Reihenfolge ändern")

    LV := GuiSeqManager.AddListView(
        "vSeqListView xs+8 y+4 w576 h200 Grid Multi Checked",
        ["Nr", "Dateiname", "Aktionen", "Status"])
    LV.ModifyCol(1, "40")
    LV.ModifyCol(2, "270")
    LV.ModifyCol(3, "80")
    LV.ModifyCol(4, "130")
    LV.OnEvent("ContextMenu", (lv,r,rc,x,y) => ShowSeqLVContextMenu(lv,r,rc,x,y))
    SetupSeqLVDragDrop()

    GuiSeqManager.AddButton("xs+8 y+8 w115 h28 Background0xCC0000 cWhite", "✖ Entfernen")
        .OnEvent("Click", SeqRemove)
    GuiSeqManager.AddButton("x+5 yp w90 h28 Background0x444444 cWhite", "⬆ Hoch")
        .OnEvent("Click", SeqMoveUp)
    GuiSeqManager.AddButton("x+5 yp w90 h28 Background0x444444 cWhite", "⬇ Runter")
        .OnEvent("Click", SeqMoveDown)
    GuiSeqManager.AddButton("x+5 yp w196 h28 Background0x804000 cWhite", "Zu SET zusammenfassen")
        .OnEvent("Click", SeqMergeToSet)

    ; ── GroupBox: Sequenz-Steuerung ──
    GuiSeqManager.SetFont("s10")
    GuiSeqManager.AddGroupBox("x8 y+8 w594 h112 Section cBlue", "Sequenz-Steuerung")
    GuiSeqManager.SetFont("s9")

    GuiSeqManager.AddButton("xs+8 ys+22 w160 h36 Background0x0080FF cWhite", "▶ Alle abspielen")
        .OnEvent("Click", SeqPlayAll)
    GuiSeqManager.AddButton("x+5 yp w130 h36 Background0xCC7700 cWhite", "⟳ Loop an/aus")
        .OnEvent("Click", SeqToggleLoop)
    GuiSeqManager.AddButton("x+5 yp w100 h36 Background0x800080 cWhite", "■ Stop")
        .OnEvent("Click", (*) => SeqAbort())

    GuiSeqManager.AddText("xs+8 y+10 vSeqStatus w576", "Bereit.")
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
    SeqSaveList()
    GuiSeqManager.Hide()
    if IsObject(GuiMain)
        WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
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

    SeqSuspendTopmost()
    files := FileSelect("M3", A_ScriptDir, "JSON-Sequenzen auswählen", "JSON-Dateien (*.json)")
    SeqRestoreTopmost()

    if !files
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
            if s["file"] = file {
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
            "file",   file,
            "name",   name,
            "count",  count,
            "status", "Wartet"
        ))
    }

    SeqRefreshList()
    SeqSaveList()
}

; ─────────────────────────────────────────────
; Ordner auswählen und alle JSONs laden
; ─────────────────────────────────────────────
SeqLoadFolder(*) {
    global SeqFolder, SeqIniFile, GuiSeqManager

    SeqSuspendTopmost()
    folder := DirSelect(A_ScriptDir, 3, "Ordner mit JSON-Sequenzen auswählen")
    SeqRestoreTopmost()

    if !folder
        return

    SeqFolder := folder

    try {
        IniWrite(SeqFolder, SeqIniFile, "SeqManager", "LastFolder")
    } catch {
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
    global SeqList, SeqIniFile, SeqFolder

    SeqRestoreFolder()
    SeqLoadSavedList()

    if SeqList.Length = 0 && SeqFolder != "" {
        SeqLoadAllFromFolder(SeqFolder)
    }
}

; ─────────────────────────────────────────────
; Geordnete Sequenzliste im INI speichern
; ─────────────────────────────────────────────
SeqSaveList() {
    global SeqList, SeqIniFile

    try {
        IniDelete(SeqIniFile, "SeqList")
        IniWrite(SeqList.Length, SeqIniFile, "SeqList", "Count")
        i := 1
        while i <= SeqList.Length {
            IniWrite(SeqList[i]["file"], SeqIniFile, "SeqList", "File" i)
            i++
        }
    } catch {
    }
}

; ─────────────────────────────────────────────
; Gespeicherte Sequenzliste beim Start laden
; ─────────────────────────────────────────────
SeqLoadSavedList() {
    global SeqList, SeqIniFile, GuiSeqManager

    count := 0
    try {
        count := Integer(IniRead(SeqIniFile, "SeqList", "Count", "0"))
    } catch {
    }

    if count <= 0
        return

    files := []
    i := 1
    while i <= count {
        try {
            file := IniRead(SeqIniFile, "SeqList", "File" i, "")
            if file != "" && FileExist(file)
                files.Push(file)
        } catch {
        }
        i++
    }

    if files.Length = 0
        return

    for file in files {
        skip := false
        for s in SeqList {
            if s["file"] = file {
                skip := true
                break
            }
        }
        if skip
            continue

        count2 := SeqGetActionCount(file)
        name   := SeqBasename(file)
        SeqList.Push(Map(
            "file",   file,
            "name",   name,
            "count",  count2,
            "status", "Wartet"
        ))
    }

    SeqRefreshList()
    SeqSaveList()
}

; ─────────────────────────────────────────────
; Selektierte Sequenz(en) entfernen
; ─────────────────────────────────────────────
SeqRemove(*) {
    global GuiSeqManager, SeqList

    LV := GuiSeqManager["SeqListView"]
    indices := []
    row := 0
    loop {
        row := LV.GetNext(row)
        if !row
            break
        indices.Push(row)
    }

    if indices.Length = 0 {
        ShowWarning("Bitte eine oder mehrere Sequenzen auswählen.")
        return
    }

    i := indices.Length
    while i >= 1 {
        SeqList.RemoveAt(indices[i])
        i--
    }

    SeqRefreshList()
    SeqSaveList()
}

; ─────────────────────────────────────────────
; Sequenz nach oben
; ─────────────────────────────────────────────
SeqMoveUp(*) {
    global GuiSeqManager, SeqList

    LV  := GuiSeqManager["SeqListView"]
    row := LV.GetNext(0)
    if !row || row <= 1
        return

    tmp              := SeqList[row - 1]
    SeqList[row - 1] := SeqList[row]
    SeqList[row]     := tmp

    SeqRefreshList()
    SeqSaveList()
    LV.Modify(row - 1, "Select Focus Vis")
}

; ─────────────────────────────────────────────
; Sequenz nach unten
; ─────────────────────────────────────────────
SeqMoveDown(*) {
    global GuiSeqManager, SeqList

    LV  := GuiSeqManager["SeqListView"]
    row := LV.GetNext(0)
    if !row || row >= SeqList.Length
        return

    tmp              := SeqList[row + 1]
    SeqList[row + 1] := SeqList[row]
    SeqList[row]     := tmp

    SeqRefreshList()
    LV.Modify(row + 1, "Select Focus Vis")
}

; ─────────────────────────────────────────────
; Markierte Sequenzen zu einem SET zusammenfassen
; ─────────────────────────────────────────────
SeqMergeToSet(*) {
    global GuiSeqManager, SeqList, SeqIniFile

    LV := GuiSeqManager["SeqListView"]

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

    mergedActions := []
    for idx in selectedIndices {
        s := SeqList[idx]
        try {
            json    := FileRead(s["file"], "UTF-8")
            actions := Jxon_Load(&json)
            if actions is Array {
                for act in actions {
                    mergedActions.Push(act)
                }
            }
        } catch as err {
            ShowWarning("Fehler beim Lesen von " s["name"] ":`n" err.Message)
            return
        }
    }

    if mergedActions.Length = 0 {
        ShowWarning("Keine Aktionen gefunden.")
        return
    }

    firstFile   := SeqList[selectedIndices[1]]["file"]
    defaultDir  := RegExReplace(firstFile, "\\[^\\]+$", "")
    defaultName := defaultDir "\SET_" FormatTime(, "yyyyMMdd_HHmmss") ".json"

    SeqSuspendTopmost()
    outFile := FileSelect("S16", defaultName, "SET speichern unter...", "JSON-Dateien (*.json)")
    SeqRestoreTopmost()

    if !outFile
        return

    if !InStr(outFile, ".json")
        outFile .= ".json"

    try {
        serial := ToJsonCompatible(mergedActions)
        json   := Jxon_Dump(serial, 0)
        f      := FileOpen(outFile, "w", "UTF-8")
        if !f {
            ShowError("Datei konnte nicht geöffnet werden:`n" outFile)
            return
        }
        f.Write(json)
        f.Close()
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
    ShowInfo("SET erstellt: " setName "`n" count " Aktionen aus " selectedIndices.Length " Sequenzen.")
}

; ─────────────────────────────────────────────
; Alle Sequenzen abspielen
; ─────────────────────────────────────────────
SeqPlayAll(*) {
    global SeqList, IsSeqPlaying, SeqCurrentIndex, IsReplaying, IsRecording

    if IsRecording {
        ShowWarning("Aufnahme läuft — bitte zuerst stoppen.")
        return
    }

    if SeqList.Length = 0 {
        ShowWarning("Keine Sequenzen geladen.")
        return
    }

    if IsSeqPlaying || IsReplaying {
        ShowInfo("Wiedergabe läuft bereits!")
        return
    }

    i := 1
    while i <= SeqList.Length {
        SeqList[i]["status"] := "Wartet"
        i++
    }

    IsSeqPlaying    := true
    SeqCurrentIndex := 0
    SeqRefreshList()
    SeqSaveList()
    SeqLoadNext()
}

; ─────────────────────────────────────────────
; Nächste Sequenz laden und starten
; ─────────────────────────────────────────────
SeqLoadNext() {
    global SeqList, SeqCurrentIndex, IsSeqPlaying, SeqRepeatMode
    global ActionsList, GuiSeqManager

    SeqCurrentIndex += 1

    if SeqCurrentIndex > SeqList.Length {
        if SeqRepeatMode {
            i := 1
            while i <= SeqList.Length {
                SeqList[i]["status"] := "Wartet"
                i++
            }
            SeqCurrentIndex := 0
            SeqRefreshList()
            SeqLoadNext()
            return
        }
        IsSeqPlaying    := false
        SeqCurrentIndex := 0
        SeqUpdateStatus("Alle Sequenzen abgespielt.")
        SeqRefreshList()
        SoundBeep(800, 200)
        return
    }

    s := SeqList[SeqCurrentIndex]

    try {
        json        := FileRead(s["file"], "UTF-8")
        ActionsList := Jxon_Load(&json)
        if !(ActionsList is Array) {
            SeqList[SeqCurrentIndex]["status"] := "Fehler"
            SeqRefreshList()
            SeqOnSequenceFinished()
            return
        }
    } catch {
        SeqList[SeqCurrentIndex]["status"] := "Fehler"
        SeqRefreshList()
        SeqOnSequenceFinished()
        return
    }

    SeqList[SeqCurrentIndex]["status"] := "Läuft..."
    SeqUpdateStatus("Sequenz " SeqCurrentIndex "/" SeqList.Length ": " s["name"])
    SeqRefreshList()
    SetCurrentFile(s["file"])
    StartPlayback()
}

; ─────────────────────────────────────────────
; Wird von PlaybackTimer aufgerufen wenn fertig
; ─────────────────────────────────────────────
SeqOnSequenceFinished() {
    global SeqList, SeqCurrentIndex

    if SeqCurrentIndex >= 1 && SeqCurrentIndex <= SeqList.Length {
        SeqList[SeqCurrentIndex]["status"] := "Fertig"
        SeqRefreshList()
    }

    SeqLoadNext()
}

; ─────────────────────────────────────────────
; Wiedergabe abbrechen
; ─────────────────────────────────────────────
SeqAbort() {
    global IsSeqPlaying, SeqCurrentIndex, SeqList, StopRequested, IsReplaying

    if !IsSeqPlaying
        return

    StopRequested := true
    IsReplaying   := false
    IsSeqPlaying  := false

    if SeqCurrentIndex >= 1 && SeqCurrentIndex <= SeqList.Length {
        SeqList[SeqCurrentIndex]["status"] := "Abgebrochen"
        SeqRefreshList()
    }

    SeqCurrentIndex := 0
    SeqUpdateStatus("Abgebrochen.")
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
SeqRefreshList() {
    global GuiSeqManager, SeqList, SeqCurrentIndex

    if !IsObject(GuiSeqManager)
        return

    LV := GuiSeqManager["SeqListView"]

    checkedFiles := Map()
    row := 0
    loop {
        row := LV.GetNext(row, "Checked")
        if !row
            break
        if row <= SeqList.Length
            checkedFiles[SeqList[row]["file"]] := true
    }

    LV.Delete()

    i := 1
    while i <= SeqList.Length {
        s := SeqList[i]

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

        LV.Add("", i, s["name"], s["count"], statusIcon)

        if checkedFiles.Has(s["file"])
            LV.Modify(i, "Check")

        if i = SeqCurrentIndex
            LV.Modify(i, "Select")

        i++
    }
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
SeqGetActionCount(file) {
    count := 0
    try {
        json := FileRead(file, "UTF-8")
        data := Jxon_Load(&json)
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
        ctx.Add("Entfernen`tEntf",           (*) => SeqRemoveSingle(rowIndex))
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
    } else {
        ctx.Add("Dateien hinzufügen...",     SeqAdd)
        ctx.Add("Ordner laden...",           SeqLoadFolder)
    }

    ctx.Show(x, y)
}

; Einzelne Sequenz per Kontextmenü entfernen
SeqRemoveSingle(rowIndex) {
    global SeqList
    if rowIndex >= 1 && rowIndex <= SeqList.Length {
        SeqList.RemoveAt(rowIndex)
        SeqRefreshList()
        SeqSaveList()
    }
}

; Zeile direkt verschieben (für Kontextmenü)
SeqMoveRowDirect(rowIndex, direction) {
    global SeqList, GuiSeqManager
    newIndex := rowIndex + direction
    if newIndex < 1 || newIndex > SeqList.Length
        return
    tmp               := SeqList[newIndex]
    SeqList[newIndex] := SeqList[rowIndex]
    SeqList[rowIndex] := tmp
    SeqRefreshList()
    SeqSaveList()
    GuiSeqManager["SeqListView"].Modify(newIndex, "Select Focus Vis")
}

; Einzelne Sequenz abspielen (Enter oder Kontextmenü)
SeqPlaySingle(rowIndex) {
    global SeqList, IsRecording, IsReplaying, IsSeqPlaying, ActionsList

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

    s := SeqList[rowIndex]
    try {
        json        := FileRead(s["file"], "UTF-8")
        ActionsList := Jxon_Load(&json)
        if !(ActionsList is Array) {
            ShowWarning("Datei enthält keine gültige Aktionsliste!")
            return
        }
    } catch as err {
        ShowError("Fehler beim Laden:`n" err.Message)
        return
    }

    SetCurrentFile(s["file"])
    StartPlayback()
    SeqUpdateStatus("Einzelwiedergabe: " s["name"])
}

; Entf-Taste: alle selektierten Zeilen löschen
SeqDelSelected() {
    global GuiSeqManager, SeqList
    LV := GuiSeqManager["SeqListView"]
    indices := []
    row := 0
    loop {
        row := LV.GetNext(row)
        if !row
            break
        indices.Push(row)
    }
    if indices.Length = 0
        return
    i := indices.Length
    while i >= 1 {
        SeqList.RemoveAt(indices[i])
        i--
    }
    SeqRefreshList()
    SeqSaveList()
}

; Prüft ob die SeqManager-ListView den Fokus hat
IsSeqLVFocused() {
    global GuiSeqManager
    if !IsObject(GuiSeqManager)
        return false
    if !WinActive("ahk_id " GuiSeqManager.Hwnd)
        return false
    focusedHwnd := DllCall("GetFocus", "Ptr")
    lv := GuiSeqManager["SeqListView"]
    if !IsObject(lv)
        return false
    return (focusedHwnd = lv.Hwnd)
}

; ─────────────────────────────────────────────
; Drag & Drop für SeqListView
; ─────────────────────────────────────────────
SetupSeqLVDragDrop() {
    OnMessage(0x004E, SeqLV_OnNotify_Drag)
    OnMessage(0x004E, SeqLV_CustomDraw)
}

SeqLV_CustomDraw(wParam, lParam, msg, hwnd) {
    global GuiSeqManager, SeqLVDragging, SeqLVDragRow, SeqLVDragTargetRow

    static NM_CUSTOMDRAW        := -12
    static CDDS_PREPAINT        := 0x1
    static CDDS_ITEMPREPAINT    := 0x10001
    static CDRF_DODEFAULT       := 0x0
    static CDRF_NOTIFYITEMDRAW  := 0x20
    static CDRF_NEWFONT         := 0x2

    if !IsObject(GuiSeqManager)
        return
    try LV := GuiSeqManager["SeqListView"]
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
    global GuiSeqManager, SeqLVDragRow, SeqLVDragging
    static LVN_BEGINDRAG := -109

    if !IsObject(GuiSeqManager)
        return
    try LV := GuiSeqManager["SeqListView"]
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

    SeqLVDragRow  := NumGet(lParam, 24, "Int") + 1
    SeqLVDragging := true
    SetTimer(SeqLVDragTimer, 16)
    return 0
}

SeqLVDragTimer(*) {
    global GuiSeqManager, SeqList, SeqLVDragRow, SeqLVDragTargetRow, SeqLVDragging

    if !SeqLVDragging
        return

    LV := GuiSeqManager["SeqListView"]
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
        SeqSaveList()
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
