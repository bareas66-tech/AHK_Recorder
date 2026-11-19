#Requires AutoHotkey v2.0
#SingleInstance Off
#Include json_utils_v03.ahk
#Include click_actions.ahk

; Ohne Aufnahme, Wiedergabe oder Änderung der Recorder-Einstellungen ausführen.
testPath := A_Temp "AHKRecorder-Selbsttest-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount ".json"
exitCode := 0
try {
    clickAction := Map("Type", "Click", "X", -12, "Y", 30)
    actions := [clickAction, Map("Type", "Delay", "Time", 3), clickAction.Clone(),
        Map("Type", "Delay", "Time", 8), clickAction.Clone()]
    combined := CombineClickRuns(actions)
    Check(combined.Length = 1 && combined[1]["Count"] = 3, "Klickanzahl beim Zusammenfassen")
    Check(combined[1]["ClickTiming"].Length = 2, "Individuelle Klickabstände")
    WriteActionFile(testPath, combined)
    restored := ExpandClickRuns(ReadActionFile(testPath))
    Check(Jxon_Dump(restored) = Jxon_Dump(actions), "JSON-Rundlauf und Wiederherstellung")
    selected := Map(1, true, 3, true)
    partial := CombineClickRuns(actions, selected)
    Check(partial.Length = 3 && partial[1]["Count"] = 2, "Selektives Zusammenfassen")
    Check(Jxon_Dump(ExpandClickRuns(partial)) = Jxon_Dump(actions), "Selektive Wiederherstellung")
    Check(CombineClickRuns(combined)[1] = combined[1], "Erneutes Zusammenfassen")
    meta := Map("", "Leer", "Unicode", "Grüße Ω 😀")
    metaJson := Jxon_Dump(meta)
    roundTrip := Jxon_Load(&metaJson)
    Check(roundTrip[""] = "Leer" && roundTrip["Unicode"] = meta["Unicode"], "Unicode und leere JSON-Schlüssel")
    for invalidJson in ['[{"Type":"Delay","Time":-1}]',
        '[{"Type":"Click","X":2147483648,"Y":0}]',
        '[{"Type":"Delay","Time":"18446744073709551618"}]',
        '[{"Type":"Click","X":0,"Y":0,"Count":3,"ClickTiming":[{"Count":1,"Delay":5}]}]'] {
        stream := FileOpen(testPath, "w", "UTF-8")
        try stream.Write(invalidJson)
        finally stream.Close()
        rejected := false
        try ReadActionFile(testPath)
        catch ValueError
            rejected := true
        Check(rejected, "Ungültige Aktionsdatei wird abgewiesen")
    }
    FileAppend("Selbsttest erfolgreich. 11 Prüfungen bestanden." Chr(10), "*", "UTF-8-RAW")
} catch Error as err {
    exitCode := 1
    FileAppend("Selbsttest fehlgeschlagen. " err.Message Chr(10), "**", "UTF-8-RAW")
} finally {
    if FileExist(testPath)
        FileDelete(testPath)
}
ExitApp(exitCode)

Check(condition, description) {
    if !condition
        throw Error(description)
}