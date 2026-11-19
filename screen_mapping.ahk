#Requires AutoHotkey v2.0

global MainScreenProfiles := [NewScreenProfile(), NewScreenProfile(), NewScreenProfile()]
global ScreenUIChanging := false
global ScreenMonitorChoices := []

NewScreenProfile() {
    return Map("Target", "", "Mode", 2, "Source", "")
}

CurrentScreenProfile() {
    global MainScreenProfiles, MainCurrentTab
    return MainScreenProfiles[MainCurrentTab]
}

GetScreenMonitors() {
    monitors := []
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        monitors.Push(Map("Name", MonitorGetName(A_Index), "Index", A_Index,
            "X", left, "Y", top, "Width", right - left, "Height", bottom - top))
    }
    return monitors
}

ScreenForPoint(x, y) {
    monitors := GetScreenMonitors()
    for monitor in monitors {
        if x >= monitor["X"] && x < monitor["X"] + monitor["Width"]
            && y >= monitor["Y"] && y < monitor["Y"] + monitor["Height"]
            return ScreenRect(monitor)
    }
    return ScreenRect(monitors[MonitorGetPrimary()])
}

ScreenRect(monitor) {
    return Map("X", monitor["X"], "Y", monitor["Y"],
        "Width", monitor["Width"], "Height", monitor["Height"])
}

TagActionScreen(action) {
    if action.Has("X") && action.Has("Y")
        action["SourceScreen"] := ScreenForPoint(action["X"], action["Y"])
    else if action["Type"] = "Drag"
        action["SourceScreen"] := ScreenForPoint(action["X1"], action["Y1"])
    return action
}

InitializeRecordingScreen() {
    global ActionsList
    if ActionsList.Length
        return
    MouseGetPos(&x, &y)
    CurrentScreenProfile()["Source"] := ScreenForPoint(x, y)
}

AppendRecordedAction(action) {
    global ActionsList
    ActionsList.Push(TagActionScreen(action))
}

RefreshScreenProfileUI() {
    global ActionsList, GuiMain, MainScreenProfiles, MainCurrentTab, ScreenUIChanging, ScreenMonitorChoices
    if ActionsList.HasOwnProp("RecorderScreenProfile") {
        MainScreenProfiles[MainCurrentTab] := ActionsList.RecorderScreenProfile
        ActionsList.DeleteProp("RecorderScreenProfile")
    }
    if !IsObject(GuiMain)
        return
    profile := CurrentScreenProfile()
    static displayedProfile := ""
    if displayedProfile = profile
        return
    displayedProfile := profile
    ScreenUIChanging := true
    try {
        ScreenMonitorChoices := GetScreenMonitors()
        labels := ["Originalpositionen"]
        selected := 1
        for monitor in ScreenMonitorChoices {
            labels.Push("Bildschirm " monitor["Index"] " – " monitor["Width"] " × " monitor["Height"]
                (monitor["Index"] = MonitorGetPrimary() ? " (Hauptbildschirm)" : ""))
            if monitor["Name"] = profile["Target"]
                selected := labels.Length
        }
        if profile["Target"] != "" && selected = 1 {
            labels.Push("Gewählter Bildschirm nicht angeschlossen")
            selected := labels.Length
        }
        GuiMain["TargetScreen"].Delete()
        GuiMain["TargetScreen"].Add(labels)
        GuiMain["TargetScreen"].Value := selected
        GuiMain["ScreenScale"].Value := profile["Mode"]
        GuiMain["ScreenScale"].Enabled := profile["Target"] != ""
    } finally {
        ScreenUIChanging := false
    }
}

ScreenProfileChanged(*) {
    global GuiMain, ScreenUIChanging, ScreenMonitorChoices
    if ScreenUIChanging
        return
    profile := CurrentScreenProfile()
    index := GuiMain["TargetScreen"].Value - 1
    if index = 0
        profile["Target"] := ""
    else if index <= ScreenMonitorChoices.Length
        profile["Target"] := ScreenMonitorChoices[index]["Name"]
    profile["Mode"] := GuiMain["ScreenScale"].Value
    GuiMain["ScreenScale"].Enabled := profile["Target"] != ""
}

AskSourceScreen(profile) {
    global GuiMain, GuiSeqManager
    previous := profile["Source"]
    initial := IsObject(previous) ? previous["Width"] "x" previous["Height"] : "1920x1080"
    sequenceVisible := IsObject(GuiSeqManager) && DllCall("IsWindowVisible", "Ptr", GuiSeqManager.Hwnd, "Int")
    SeqSuspendTopmost()
    try result := InputBox("Aufnahmeauflösung eingeben, z. B. 1920x1080."
        Chr(10) "Für ältere Aufnahmen wird der Ursprung X=0, Y=0 verwendet.",
        "Aufnahmeauflösung", "w390 h150", initial)
    finally {
        if sequenceVisible
            SeqRestoreTopmost()
        else
            GuiMain.Opt("+AlwaysOnTop")
    }
    if result.Result != "OK"
        return false
    if !RegExMatch(Trim(result.Value), "^([1-9][0-9]{0,5})\s*[xX×]\s*([1-9][0-9]{0,5})$", &size) {
        ShowWarning("Bitte eine Auflösung wie 1920x1080 eingeben.")
        return false
    }
    profile["Source"] := Map("X", 0, "Y", 0, "Width", Integer(size[1]), "Height", Integer(size[2]))
    return true
}

SetSourceScreen(*) {
    AskSourceScreen(CurrentScreenProfile())
}

ShowTargetScreen(*) {
    profile := CurrentScreenProfile()
    monitors := GetScreenMonitors()
    for monitor in monitors {
        if (profile["Target"] = "" && monitor["Index"] = MonitorGetPrimary()) || monitor["Name"] = profile["Target"] {
            marker := Gui("-DPIScale +AlwaysOnTop -Caption +ToolWindow +E0x20")
            marker.BackColor := "174C87"
            marker.SetFont("s32 cWhite", "Segoe UI")
            marker.AddText("w380 h80 Center +0x200", "Bildschirm " monitor["Index"])
            marker.Show("NoActivate x" (monitor["X"] + (monitor["Width"] - 400) // 2)
                " y" (monitor["Y"] + (monitor["Height"] - 100) // 2) " w400 h100")
            SetTimer(() => marker.Destroy(), -1500)
            return
        }
    }
    ShowWarning("Der gewählte Bildschirm ist nicht angeschlossen.")
}

ScreenProfileForFile(path, actions) {
    global MainAllTabPaths, MainScreenProfiles
    for index, openPath in MainAllTabPaths {
        if openPath != "" && StrLower(openPath) = StrLower(path)
            return MainScreenProfiles[index]
    }
    return actions.HasOwnProp("RecorderScreenProfile") ? actions.RecorderScreenProfile : NewScreenProfile()
}

PrepareScreenPlayback(actions, profile) {
    if profile["Target"] = ""
        return actions
    target := ""
    for monitor in GetScreenMonitors() {
        if monitor["Name"] = profile["Target"] {
            target := monitor
            break
        }
    }
    if !IsObject(target)
        throw Error("Der gewählte Zielbildschirm ist nicht angeschlossen.")
    for action in actions {
        if (action.Has("X") || action["Type"] = "Drag")
            && profile["Mode"] = 2 && !action.Has("SourceScreen") && !IsObject(profile["Source"]) {
            if !AskSourceScreen(profile)
                throw Error("Die Bildschirmzuordnung wurde abgebrochen.")
            break
        }
    }
    prepared := []
    for action in actions
        prepared.Push(MapActionToScreen(action, profile, target))
    return prepared
}

MapActionToScreen(action, profile, target) {
    mapped := action.Clone()
    pairs := action["Type"] = "Drag" ? [["X1", "Y1"], ["X2", "Y2"]] : [["X", "Y"]]
    source := action.Get("SourceScreen", profile["Source"])
    if !IsObject(source) {
        if profile["Mode"] != 1
            return mapped
        source := Map("X", 0, "Y", 0, "Width", target["Width"], "Height", target["Height"])
    }
    for pair in pairs {
        if !action.Has(pair[1]) || !action.Has(pair[2])
            continue
        x := action[pair[1]] - source["X"]
        y := action[pair[2]] - source["Y"]
        if profile["Mode"] = 2 {
            x := source["Width"] > 1 ? x * (target["Width"] - 1) / (source["Width"] - 1) : 0
            y := source["Height"] > 1 ? y * (target["Height"] - 1) / (source["Height"] - 1) : 0
        }
        mapped[pair[1]] := target["X"] + Max(0, Min(target["Width"] - 1, Round(x)))
        mapped[pair[2]] := target["Y"] + Max(0, Min(target["Height"] - 1, Round(y)))
    }
    return mapped
}
