;=========================
; Datei: gui.ahk (angepasst)
;=========================
#Requires AutoHotkey v2.0
CoordMode("ToolTip", "Screen")

global GuiMain := ""
global GuiActionInsert := ""
global dropdown
global StopRecordingBtn
global actionTypes := ["Mausklick", "Zeitverzögerung", "Drag & Drop"]

; Buttons, die während Aufnahme deaktiviert werden sollen (wird in ShowGui initialisiert)
global BtnsDisableOnRecord := []
; Buttons, die während Aufnahme aktiv bleiben dürfen (aber Klicks nicht aufnehmen)
global BtnsAllowedOnRecord := []
; Original-Buttontexte zum Wiederherstellen
global OriginalBtnText := Map()

ShowGui() {
    global GuiMain, ActionsList, GuiButtonsList, StopRecordingBtn
    global StartRecordingBtn, PlayOnceBtn, ToggleRepeatBtn, AbortBtn, ExitBtn, InsertBtn, DeleteBtn, SaveBtn, LoadBtn
    global OriginalBtnText
    if !IsObject(ActionsList)
        ActionsList := []  ; Initialisiere das Array, falls noch nicht geschehen

    if !IsObject(GuiMain) {
        ; =========================
        ; GUI Setup
        ; =========================
        GuiMain := Gui("+Resize +AlwaysOnTop", "🎬 AHK Recorder by EmJay v01")
        GuiMain.SetFont("s10")
        GuiMain.OnEvent("Close", ExitScript)

        ; --- Statuszeile oben ---
        GuiMain.AddText("vStatusText w460", "Status: 🟢 Idle...On :P")
        GuiMain.AddText("vLoopStatus", "🔁 Loop: 🔴 Inaktiv")
        GuiMain.AddText("vMousePos w200", "🖱️ Maus: X=0 Y=0")
        GuiMain.AddText("vDelayDisplay w200", "⏱️ Zeitverzögerung: 0 ms")

        GuiMain.AddText("y+10", "") ; Abstand nach Statuszeile

        ; --- Obere Aktionsbuttons ---
        ButtonSpacing := 10
        ButtonWidthTop := 115
        ; ButtonObjekte erstellen (erst zuweisen, dann Events binden)
        InsertBtn := GuiMain.AddButton("x" ButtonSpacing " w" ButtonWidthTop " h35 Background0x00CC00 cWhite", "➕ Einfügen")
        DeleteBtn := GuiMain.AddButton("x+5 yp w" ButtonWidthTop " h35 Background0xCC0000 cWhite", "🗑️ Löschen")
        SaveBtn := GuiMain.AddButton("x+5 yp w" ButtonWidthTop " h35 Background0x0080FF cWhite", "💾 Speichern")
        LoadBtn := GuiMain.AddButton("x+5 yp w" ButtonWidthTop " h35 Background0xFFA500 cWhite", "📂 Laden")

        ; Events binden (getrennt)
        InsertBtn.OnEvent("Click", AddAction)
        DeleteBtn.OnEvent("Click", DelAction)
        SaveBtn.OnEvent("Click", SaveActions)
        LoadBtn.OnEvent("Click", LoadActions)

        GuiMain.AddText("y+10", "") ; Abstand vor ListView

        ; --- ListView links ---
        LVWidth := 480
        LVHeight := 250
        LV := GuiMain.AddListView("vActionList w" LVWidth " h" LVHeight " Grid x10", ["Nummer", "Aktion", "Wert"])
        LV.ModifyCol(1, "100")
        LV.ModifyCol(2, "150")
        LV.ModifyCol(3, "200")

        GuiMain.AddText("y+10", "") ; Abstand vor Steuerbuttons

        ; =========================
        ; Steuerbuttons unten
        ; =========================
        GuiWidth := 500  ; Gesamtbreite des Fensters
        ButtonSpacing := 10
        ButtonWidth := (GuiWidth - 3*ButtonSpacing) // 2  ; 2 Buttons pro Reihe
        ButtonHeight := 40

        ; Reihe 1: Aufnahme starten / stoppen (erst zuweisen)
        StartRecordingBtn := GuiMain.AddButton("x" ButtonSpacing " y+10 w" ButtonWidth " h" ButtonHeight " Background0x00CC00 cWhite", "▶️ Aufnahme starten (F9)")
        StopRecordingBtn := GuiMain.AddButton("x" (2*ButtonSpacing + ButtonWidth) " yp w" ButtonWidth " h" ButtonHeight " Background0xCC0000 cWhite", "⏹️ Aufnahme stoppen (F10)")

        ; Events binden
        StartRecordingBtn.OnEvent("Click", BtnStartRecording)
        StopRecordingBtn.OnEvent("Click", BtnStopRecording)

        ; Reihe 2: Einmal abspielen / Loop
        PlayOnceBtn := GuiMain.AddButton("x" ButtonSpacing " y+10 w" ButtonWidth " h" ButtonHeight " Background0x0080FF cWhite", "▶️ Einmal abspielen (F11)")
        ToggleRepeatBtn := GuiMain.AddButton("x" (2*ButtonSpacing + ButtonWidth) " yp w" ButtonWidth " h" ButtonHeight " Background0xFFA500 cWhite", "🔁 Loop umschalten (F12)")

        ; Events binden
        PlayOnceBtn.OnEvent("Click", BtnPlayOnce)
        ToggleRepeatBtn.OnEvent("Click", BtnPlayLoop)

        ; Reihe 3: Abbrechen / Beenden (erst zuweisen)
        AbortBtn := GuiMain.AddButton("x" ButtonSpacing " y+10 w" ButtonWidth " h" ButtonHeight " Background0x800080 cWhite", "⛔ Abbrechen (Pause)")
        ExitBtn := GuiMain.AddButton("x" (2*ButtonSpacing + ButtonWidth) " yp w" ButtonWidth " h" ButtonHeight " Background0x555555 cWhite", "❌ Beenden")

        ; Events binden
        AbortBtn.OnEvent("Click", BtnAbortAll)
        ExitBtn.OnEvent("Click", ExitScript)

        ; --- Hotkey-Hinweise unten links ---
        GuiMain.AddText("x10 y+15", "🎹 Hotkeys:")
        GuiMain.AddText("x10", "F9  = Aufnahme starten")
        GuiMain.AddText("x10", "F10 = Aufnahme stoppen")
        GuiMain.AddText("x10", "F11 = Einmal abspielen")
        GuiMain.AddText("x10", "F12 = Loop an/aus")
        GuiMain.AddText("x10", "ESC/Pause = Notfall-Abbruch")

        ; Buttons, die während Aufnahme deaktiviert werden sollen
        BtnsDisableOnRecord := [ StartRecordingBtn, InsertBtn, SaveBtn, LoadBtn, PlayOnceBtn, ToggleRepeatBtn ]
        ; Buttons, die während Aufnahme aktiv bleiben dürfen (aber Klicks werden nicht aufgenommen)
        BtnsAllowedOnRecord := [ StopRecordingBtn, AbortBtn, ExitBtn, DeleteBtn ]

        ; Originaltexte speichern (zum Wiederherstellen nach Ende der Aufnahme)
        OriginalBtnText[StartRecordingBtn.Hwnd] := StartRecordingBtn.Text
        OriginalBtnText[StopRecordingBtn.Hwnd]  := StopRecordingBtn.Text
        OriginalBtnText[PlayOnceBtn.Hwnd]      := PlayOnceBtn.Text
        OriginalBtnText[ToggleRepeatBtn.Hwnd]  := ToggleRepeatBtn.Text
        OriginalBtnText[AbortBtn.Hwnd]         := AbortBtn.Text
        OriginalBtnText[ExitBtn.Hwnd]          := ExitBtn.Text
        OriginalBtnText[InsertBtn.Hwnd]        := InsertBtn.Text
        OriginalBtnText[DeleteBtn.Hwnd]        := DeleteBtn.Text
        OriginalBtnText[SaveBtn.Hwnd]          := SaveBtn.Text
        OriginalBtnText[LoadBtn.Hwnd]          := LoadBtn.Text

        ; GUI anzeigen
        GuiMain.Show()
        return
    } else {
        GuiMain.Show()
    }
}

UpdateGui() {
    global GuiMain, LastDelay, RepeatMode, IsRecording
    global BtnsDisableOnRecord, BtnsAllowedOnRecord, OriginalBtnText
    if !IsObject(GuiMain)
        return

    MouseGetPos(&x, &y)
    GuiMain["MousePos"].Value := "🖱️ Maus: X=" x " Y=" y
    GuiMain["DelayDisplay"].Value := "⏱️ Zeitverzögerung: " LastDelay " ms"
    GuiMain["LoopStatus"].Value := "🔁 Loop: " (RepeatMode ? "🟢 Aktiv" : "🔴 Inaktiv")

    ; Buttons während Aufnahme deaktivieren / einfärben; erlaubte Buttons aktiv lassen
    for btn in BtnsDisableOnRecord {
        try {
            if IsRecording {
                btn.Disable()
                btn.Modify("Background0xA0A0A0 cBlack") ; graue Hintergrundfarbe
                ; Stelle sicher, dass Text nicht "gehighlightet" bleibt
                if OriginalBtnText.HasKey(btn.Hwnd)
                    btn.Text := OriginalBtnText[btn.Hwnd]
            } else {
                btn.Enable()
                ; Originalfarben wiederherstellen (je nach Button)
                if (btn = StartRecordingBtn)
                    btn.Modify("Background0x00CC00 cWhite")
                else if (btn = InsertBtn)
                    btn.Modify("Background0x00CC00 cWhite")
                else if (btn = SaveBtn)
                    btn.Modify("Background0x0080FF cWhite")
                else if (btn = LoadBtn)
                    btn.Modify("Background0xFFA500 cWhite")
                else if (btn = PlayOnceBtn)
                    btn.Modify("Background0x0080FF cWhite")
                else if (btn = ToggleRepeatBtn)
                    btn.Modify("Background0xFFA500 cWhite")
                ; Text zurücksetzen
                if OriginalBtnText.HasKey(btn.Hwnd)
                    btn.Text := OriginalBtnText[btn.Hwnd]
            }
        } catch {
            ; ignore
        }
    }

    ; Hervorhebung für erlaubte Buttons während Aufnahme:
    for btn in BtnsAllowedOnRecord {
        try {
            if IsRecording {
                btn.Enable() ; diese Buttons sollen benutzt werden
                if OriginalBtnText.HasKey(btn.Hwnd) {
                    orig := OriginalBtnText[btn.Hwnd]
                    highlighted := "» " orig " «"
                    btn.Text := highlighted
                    btn.Modify("cWhite")
                }
            } else {
                ; Wiederherstellen
                if OriginalBtnText.HasKey(btn.Hwnd) {
                    btn.Text := OriginalBtnText[btn.Hwnd]
                }
            }
        } catch {
            ; ignore
        }
    }
}

UpdateActionsList() {
    global GuiMain, ActionsList
    LV := GuiMain["ActionList"]
    LV.Delete()

    if !(IsObject(ActionsList) && ActionsList.Length > 0)
        return

    maxIndex := ActionsList.Length
    digits := StrLen(maxIndex)

    for i, a in ActionsList {
        if !(IsObject(a) && a is Map)
            continue
        if !a.Has("Type")
            continue

        displayIndex := Format("{:0" digits "}", i)

        type := a["Type"]
        if type = "Click"
            LV.Add("", displayIndex, "Mausklick", "X=" a["X"] " Y=" a["Y"])
        else if type = "Delay"
            LV.Add("", displayIndex, "Zeitverzögerung", a["Time"] " ms")
        else if type = "Drag"
            LV.Add("", displayIndex, "Drag & Drop", "X1=" a["X1"] " Y1=" a["Y1"] " → X2=" a["X2"] " Y2=" a["Y2"])
    }

    rowCount := LV.GetCount()
    if rowCount > 0
        LV.Modify(rowCount, "Vis")
}
AddAction(*) {
    global ActionsList, actionTypes, GuiActionInsert, dropdown
    GuiActionInsert := Gui("+ToolWindow +AlwaysOnTop", "➕ Aktion hinzufügen")
    GuiActionInsert.SetFont("s9")

    ; Dropdown
    GuiActionInsert.AddText(, "Aktionstyp:")
    dropdown := GuiActionInsert.AddDropDownList("vActionType w150", actionTypes)
    dropdown.Value := 2  ; Standard = "Zeitverzögerung"

    ; Felder für Klick
    GuiActionInsert.AddCheckBox("vUseCurrentPos Hidden", "Aktuelle Mausposition verwenden")
	
	GuiMain.AddText("y+30", "") ; Abstand vor Steuerbuttons
	
    GuiActionInsert.AddText("vPosLabel", "Letzte Mauskoordinaten (X,Y):")
	
	; X-Koordinate
	GuiActionInsert.AddText("vXLabel", "x-Koordinate:")
	GuiActionInsert.AddEdit("vPosX w60")

	GuiMain.AddText("y+10", "") ; Abstand vor Steuerbuttons

	; Y-Koordinate, nebeneinander setzen
	GuiActionInsert.AddText("vYLabel", "y-Koordinate:")  ; y bleibt gleich wie vorher
	GuiActionInsert.AddEdit("vPosY w60")


    ; Felder für Zeitverzögerung
    GuiActionInsert.AddText("vDelayLabel", "Zeit (ms):")
    GuiActionInsert.AddEdit("vDelayValue w100")

    ; Felder für Drag & Drop
    GuiActionInsert.AddText("vDragLabel", "Start- und Zielposition (X1,Y1 -> X2,Y2):")
    GuiActionInsert.AddEdit("vDragX1 w50")
    GuiActionInsert.AddEdit("vDragY1 w50")
    GuiActionInsert.AddEdit("vDragX2 w50")
    GuiActionInsert.AddEdit("vDragY2 w50")

    ; Einfügeposition
    GuiActionInsert.AddText(, "Einfügeposition:")
    GuiActionInsert.AddEdit("vInsertIndex w60", ActionsList.Length+1)

    ; Buttons
    GuiActionInsert.AddButton("w80 Default", "OK").OnEvent("Click", (*) => InsertConfirm(GuiActionInsert))
    GuiActionInsert.AddButton("w80", "Abbrechen").OnEvent("Click", (*) => GuiActionInsert.Destroy())

    ; Event: Dropdown ändern
    dropdown.OnEvent("Change", InsertDropdownChanged)
	
	; Checkbox-Event binden
	GuiActionInsert["UseCurrentPos"].OnEvent("Click", InsertUseCurrentPosChanged)

    ; GUI anzeigen & initial Sichtbarkeit setzen
    GuiActionInsert.Show()
    UpdateInsertOptions(GuiActionInsert, actionTypes[dropdown.Value])
}

DelAction(*) {
    global GuiMain, ActionsList, LastDelay
    LV := GuiMain["ActionList"]
	; Hole das nächste selektierte Element
    selectedItem := LV.GetNext()
		if !selectedItem {
			count := ActionsList.Length
			if (count > 0) {
				result := ShowYesNo("Es sind " count " Aktionen vorhanden.`n`nZum Löschen einzelner Aktionen, müssen die Aktionen im Fenster markiert werden!`n`nWirklich alle Aktionen löschen?")
			
				if (result != "Yes")
					return
			}
			; Alles löschen
			ActionsList := []
			LV.Delete()
			UpdateActionsList()
			return
		}

	 ; Schleife durch alle selektierten Elemente
    Loop {
        ; Hole das nächste selektierte Element
        selectedItem := LV.GetNext()

        ; Wenn kein weiteres selektiertes Element gefunden wird, beende die Schleife
        if !selectedItem {
            break
        }
    ; Löschen des selektierten Elements aus der ListView
    LV.Delete(selectedItem)
	; Entferne das Element aus dem ActionsList-Array (Den Index anpassen, da der ListView-Index 1-basiert ist)
    itemIndex := selectedItem   ; Korrigiere den Index für das Array (0-basiert)
    ; Entferne das Element aus dem ActionsList-Array
    ActionsList := RemoveAction(ActionsList, itemIndex)
	}
    UpdateActionsList()  ; ListView nach dem Löschen neu aufbauen
}

; --- GuiActionInsert - Aktion hinzufügen --- 
InsertConfirm(GuiActionInsert) {
    global ActionsList, LastDelay

    type := GuiActionInsert["ActionType"].Text
    insertIndex := GuiActionInsert["InsertIndex"].Value

    ; Index prüfen
    if (insertIndex = "" || insertIndex < 1 || insertIndex > ActionsList.Length + 1)
        insertIndex := ActionsList.Length + 1

    ; Zeitverzögerung zuerst einfügen, falls vorhanden
    if LastDelay > 0 {
        delayMap := Map()
        delayMap["Type"] := "Delay"
        delayMap["Time"] := LastDelay
        ActionsList.InsertAt(insertIndex, delayMap)
        insertIndex++
        LastDelay := 0
    }

    if type = "Mausklick" {
        ; Mausposition prüfen
        if GuiActionInsert["UseCurrentPos"].Value {
            MouseGetPos &x, &y
        } else {
            x := GuiActionInsert["PosX"].Value
            y := GuiActionInsert["PosY"].Value
            if (Trim(x) = "" || Trim(y) = "" || !IsNumber(x) || !IsNumber(y)) {
                ShowWarning("Bitte gültige X/Y-Koordinaten eingeben!")
                return
            }
       
        }
        clickMap 			:= Map()
        clickMap["Type"] 	:= "Click"
        clickMap["X"] 		:= x
        clickMap["Y"] 		:= y
        ActionsList.InsertAt(insertIndex, clickMap)

    } else if type = "Zeitverzögerung" {
        delay := GuiActionInsert["DelayValue"].Value
        if (Trim(delay) = "" || !IsNumber(delay) || delay <= 0) {
            ShowWarning("Bitte gültige Zeitverzögerung eingeben!")
            return
        }
        delayMap 			:= Map()
        delayMap["Type"] 	:= "Delay"
        delayMap["Time"] 	:= delay
        ActionsList.InsertAt(insertIndex, delayMap)

    } else if type = "Drag & Drop" {
        x1 := GuiActionInsert["DragX1"].Value
        y1 := GuiActionInsert["DragY1"].Value
        x2 := GuiActionInsert["DragX2"].Value
        y2 := GuiActionInsert["DragY2"].Value

        if !(IsNumber(x1) && IsNumber(y1) && IsNumber(x2) && IsNumber(y2)) {
            ShowWarning("Bitte gültige Drag & Drop-Koordinaten eingeben!")
            return
        }

        dragMap 			:= Map()
        dragMap["Type"] 	:= "Drag"
        dragMap["X1"] 		:= x1
        dragMap["Y1"] 		:= y1
        dragMap["X2"] 		:= x2
        dragMap["Y2"] 		:= y2
        ActionsList.InsertAt(insertIndex, dragMap)
    }

    ; GUI schließen & ListView aktualisieren
    GuiActionInsert.Destroy()
    UpdateActionsList()
}


InsertDropdownChanged(*) {
   global GuiActionInsert, dropdown, actionTypes
    type := actionTypes[dropdown.Value]
    UpdateInsertOptions(GuiActionInsert, type)

    ; Wenn Klick & Checkbox aktiv, aktuelle Mausposition eintragen
    if (type = "Mausklick" && GuiActionInsert["UseCurrentPos"].Value) {
        MouseGetPos &x, &y
        GuiActionInsert["PosX"].Value := x
        GuiActionInsert["PosY"].Value := y
    }
}
InsertUseCurrentPosChanged(*) {
    global GuiActionInsert
    if !IsObject(GuiActionInsert)
        return

    if GuiActionInsert["UseCurrentPos"].Value {
        ; Timer starten, um Mausposition zu aktualisieren
        SetTimer(UpdateInsertMousePos, 50)
    } else {
        ; Timer stoppen & Tooltip entfernen
        SetTimer(UpdateInsertMousePos, 0)
        ToolTip("")
    }
}

UpdateInsertMousePos(*) {
    global GuiActionInsert

    if !IsObject(GuiActionInsert)
        return

    ; Checkbox deaktiviert → Timer stoppen, Tooltip entfernen
    if !GuiActionInsert["UseCurrentPos"].Value {
        SetTimer(UpdateInsertMousePos, 0)
        ToolTip()
        return
    }

    ; Aktuelle Mausposition
    MouseGetPos &x, &y
    GuiActionInsert["PosX"].Value := x
    GuiActionInsert["PosY"].Value := y

    ToolTip("X=" x " Y=" y " - Klicke zum Speichern", x+20, y+20)

    ; Position der Checkbox abrufen
    ctrl := GuiActionInsert["UseCurrentPos"]
    ctrl.GetPos(&cx, &cy, &cw, &ch)

    ; Prüfen, ob ein Mausklick erfolgt
    if GetKeyState("LButton", "P") || GetKeyState("RButton", "P") {
        ; Wenn Klick **nicht auf der Checkbox** war → einfrieren
        if !(x >= cx && x <= cx+cw && y >= cy && y <= cy+ch) {
            GuiActionInsert["PosX"].Value := x
            GuiActionInsert["PosY"].Value := y

            ; Checkbox deaktivieren **nur hier**
            GuiActionInsert["UseCurrentPos"].Value := false

            ; Timer stoppen & Tooltip entfernen
            SetTimer(UpdateInsertMousePos, 0)
            ToolTip()
        }
        ; Klick auf Checkbox ignorieren → GUI verarbeitet ihn normal
    }
}

UpdateInsertOptions(Gui, type := "") {
    if (type = "")
        type := Gui["ActionType"].Value

    ; Alles ausblenden
    for name in ["UseCurrentPos","PosLabel","PosX","PosY","XLabel","YLabel","DelayLabel","DelayValue","DragLabel","DragX1","DragY1","DragX2","DragY2"]
        Gui[name].Visible := false

    ; Sichtbarkeit nach Typ
    if type = "Mausklick" {
        for name in ["UseCurrentPos","PosLabel","PosX","PosY","XLabel","YLabel"]
            Gui[name].Visible := true
    } else if type = "Zeitverzögerung" {
        for name in ["DelayLabel","DelayValue"]
            Gui[name].Visible := true
    } else if type = "Drag & Drop" {
        for name in ["DragLabel","DragX1","DragY1","DragX2","DragY2"]
            Gui[name].Visible := true
    }
}
; STRG+A (Ctrl+A) - Alle Einträge in der ListView auswählen, NUR wenn die ListView den Fokus hat
SelectAllInListView() {
    global GuiMain
    LV := GuiMain["ActionList"]
    if !IsObject(LV)
        return

    count := Floor(LV.GetCount() + 0)
    if (count <= 0)
        return

    Loop count {
        LV.Modify(A_Index, "Select")
    }
    LV.Modify(count, "Vis")
}
; Kontext‑sensitiver STRG+A-Hotkey (AHK v2)
IsListViewFocused() {
    global GuiMain

    ; GuiMain muss existieren
    if !IsObject(GuiMain)
        return false

    ; Unser GUI muss aktiv sein
    if !WinActive("ahk_id " GuiMain.Hwnd)
        return false

    ; Aktuell fokussiertes HWND ermitteln
    focusedHwnd := DllCall("GetFocus", "Ptr")

    ; ListView-Objekt holen
    lv := GuiMain["ActionList"]
    if !IsObject(lv)
        return false

    ; Vergleichen: Focused HWND == ListView HWND ?
    return (focusedHwnd = lv.Hwnd)
}

; Hilfsfunktion, um ein Element aus dem Array zu entfernen
RemoveAction(array, index) {
    if (index > 0 and index <= array.Length) {
        array.RemoveAt(index)  ; Entferne das Element aus dem Array
    }
    return array
}
; =========================
; Einheitliche Meldungsfunktionen
; =========================

; Info-Meldung (grünes Info-Icon, TopMost)
ShowInfo(Text, Title := "Info") {
    MsgBox(Text, Title, 0x40 | 0x40000)
}

; Warnung (gelbes Warnungs-Icon, TopMost)
ShowWarning(Text, Title := "Warnung") {
    MsgBox(Text, Title, 0x30 | 0x40000)
}

; Fehler (gelbes Warnungs-Icon, TopMost)
ShowError(Text, Title := "Fehler") {
    MsgBox(Text, Title, 0x10 | 0x40000)
}
; Frage Ja Nein, ShowYesNo
ShowYesNo(Text, Title := "Frage") {
    result:= MsgBox(Text, Title, 0x34 | 0x40000) ; 0x34 = Ja/Nein + Fragezeichen
    return (result = "Yes") ? "Yes" : "No"
}

; Debug-Meldung (graues Info-Icon, TopMost, optional)
ShowDebug(Text, Title := "Debug") {
    ; MB_OK = 0x0, Info-Icon = 0x40, TopMost = 0x40000
    MsgBox(Text, Title, 0x40 | 0x40000)
}