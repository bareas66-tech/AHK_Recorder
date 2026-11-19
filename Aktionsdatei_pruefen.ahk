#Requires AutoHotkey v2.0

paths := A_Args.Clone()
jsonOutput := paths.Length && paths[1] == "--json"
if jsonOutput
    paths.RemoveAt(1)
if !paths.Length {
    FileAppend("Aufruf: AutoHotkey64.exe Aktionsdatei_pruefen.ahk [--json] <Datei.json> [weitere Dateien ...]`n", "**", "UTF-8-RAW")
    ExitApp(2)
}

failed := false
results := []
for path in paths {
    try {
        actions := ReadActionFile(path)
    } catch as err {
        failed := true
        if jsonOutput
            results.Push(Map("path", path, "status", "error", "message", err.Message))
        else
            FileAppend(path " – " err.Message "`n", "**", "UTF-8-RAW")
        continue
    }

    if jsonOutput {
        results.Push(Map("path", path, "status", "ok", "actionCount", actions.Length))
    } else {
        message := "Gültige Aktionsdatei. Aktionen: " actions.Length
        if paths.Length > 1
            message := path " – " message
        FileAppend(message "`n", "*", "UTF-8-RAW")
    }
}

if jsonOutput
    FileAppend(Jxon_Dump(results) "`n", "*", "UTF-8-RAW")
ExitApp(failed ? 1 : 0)

#Include json_utils_v03.ahk
