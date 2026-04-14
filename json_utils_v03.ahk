;=========================
; Datei: json_utils_v03.ahk
; Neu: SetCurrentFile() wird nach Laden/Speichern aufgerufen
;=========================

#Requires AutoHotkey v2.0

SaveActions(*) {
    global ActionsList, GuiMain

    if !(ActionsList is Array) {
        ShowError("ActionsList ist kein Array!")
        return
    }

    try {
        WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    file := FileSelect("S16", A_ScriptDir "\actions.json", "JSON speichern unter...", "JSON-Dateien (*.json)")

    try {
        WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    if !file {
        ShowInfo("Speichern abgebrochen.")
        return
    }

    if !InStr(file, ".json", false)
        file .= ".json"

    try {
        serial := ToJsonCompatible(ActionsList)
        json   := Jxon_Dump(serial, 0)
        f      := FileOpen(file, "w", "UTF-8")
        if !f {
            ShowError("Datei konnte nicht geoeffnet werden: " file)
            return
        }
        f.Write(json)
        f.Close()
        SetCurrentFile(file)
        AddToRecentFiles(file)
        ShowInfo("Aktionen gespeichert in:`n" file)
    } catch as err {
        ShowError("Fehler beim Speichern:`n" err.Message)
    }
}

LoadActions(*) {
    global ActionsList, GuiMain

    try {
        WinSetAlwaysOnTop(0, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    file := FileSelect("3", A_ScriptDir, "JSON-Datei laden", "JSON-Dateien (*.json)")

    try {
        WinSetAlwaysOnTop(1, "ahk_id " GuiMain.Hwnd)
    } catch {
    }

    if !file {
        ShowInfo("Laden abgebrochen.")
        return
    }

    if !FileExist(file) {
        ShowError("Datei nicht gefunden:`n" file)
        return
    }

    try {
        json        := FileRead(file, "UTF-8")
        ActionsList := Jxon_Load(&json)
        if !(ActionsList is Array) {
            ShowWarning("Datei enthaelt keine gueltige Aktionsliste!")
            return
        }
        UpdateActionsList()
        SetCurrentFile(file)
        AddToRecentFiles(file)
        ShowInfo("Aktionen geladen aus:`n" file)
    } catch as err {
        ShowError("Fehler beim Laden:`n" err.Message)
    }
}

; ==== JSON Parser (Jxon) ====

Jxon_Load(&src, args*) {
    key := "", is_key := false
    stack := [ tree := [] ]
    next := '"{[01234567890-tfn'
    pos := 0
    while ( (ch := SubStr(src, ++pos, 1)) != "" ) {
        if InStr(" `t`n`r", ch)
            continue
        if !InStr(next, ch, true) {
            testArr := StrSplit(SubStr(src, 1, pos), "`n")
            ln  := testArr.Length
            col := pos - InStr(src, "`n",, -(StrLen(src)-pos+1))
            msg := Format("{}: line {} col {} (char {})"
                , (next == "") ? ["Extra data", ch := SubStr(src, pos)][1]
                : (next == "'") ? "Unterminated string starting at"
                : (next == "\") ? "Invalid \escape"
                : (next == ":") ? "Expecting ':' delimiter"
                : (next == '"') ? "Expecting object key enclosed in double quotes"
                : (next == '"}') ? "Expecting object key enclosed in double quotes or object closing '}'"
                : (next == ",}") ? "Expecting ',' delimiter or object closing '}'"
                : (next == ",]") ? "Expecting ',' delimiter or array closing ']'"
                : [ "Expecting JSON value(string, number, [true, false, null], object or array)"
                  , ch := SubStr(src, pos, (SubStr(src, pos)~="[\]\},\s]|$")-1) ][1]
                , ln, col, pos)
            throw Error(msg, -1, ch)
        }
        obj      := stack[1]
        is_array := (obj is Array)
        if i := InStr("{[", ch) {
            val := (i = 1) ? Map() : Array()
            is_array ? obj.Push(val) : obj[key] := val
            stack.InsertAt(1, val)
            next := '"' ((is_key := (ch == "{")) ? "}" : "{[]0123456789-tfn")
        } else if InStr("}]", ch) {
            stack.RemoveAt(1)
            next := (stack[1]==tree) ? "" : (stack[1] is Array) ? ",]" : ",}"
        } else if InStr(",:", ch) {
            is_key := (!is_array && ch == ",")
            next   := is_key ? '"' : '"{[0123456789-tfn'
        } else {
            if (ch == '"') {
                i := pos
                while i := InStr(src, '"',, i+1) {
                    val := StrReplace(SubStr(src, pos+1, i-pos-1), "\\", "\u005C")
                    if (SubStr(val, -1) != "\")
                        break
                }
                if !i ? (pos--, next := "'") : 0
                    continue
                pos := i
                val := StrReplace(val, "\/",  "/")
                val := StrReplace(val, '\"',  '"')
                val := StrReplace(val, "\b",  "`b")
                val := StrReplace(val, "\f",  "`f")
                val := StrReplace(val, "\n",  "`n")
                val := StrReplace(val, "\r",  "`r")
                val := StrReplace(val, "\t",  "`t")
                i := 0
                while i := InStr(val, "\",, i+1) {
                    if (SubStr(val, i+1, 1) != "u") ? (pos -= StrLen(SubStr(val, i)), next := "\") : 0
                        continue 2
                    xxxx := Abs("0x" . SubStr(val, i+2, 4))
                    if (xxxx < 0x100)
                        val := SubStr(val, 1, i-1) . Chr(xxxx) . SubStr(val, i+6)
                }
                if is_key {
                    key := val, next := ":"
                    continue
                }
            } else {
                val := SubStr(src, pos, i := RegExMatch(src, "[\]\},\s]|$",, pos)-pos)
                if IsInteger(val)
                    val += 0
                else if IsFloat(val)
                    val += 0
                else if (val == "true" || val == "false")
                    val := (val == "true")
                else if (val == "null")
                    val := ""
                else if is_key {
                    pos--, next := "#"
                    continue
                }
                pos += i-1
            }
            is_array ? obj.Push(val) : obj[key] := val
            next := obj == tree ? "" : is_array ? ",]" : ",}"
        }
    }
    return tree[1]
}

Jxon_Dump(obj, indent := "", lvl := 1) {
    if IsObject(obj) {
        if !(obj is Array || obj is Map || obj is String || obj is Number)
            throw Error("Object type not supported.", -1, Format("<Object at 0x{:p}>", ObjPtr(obj)))
        if IsInteger(indent) {
            if (indent < 0)
                throw Error("Indent parameter must be a positive integer.", -1, indent)
            spaces := indent, indent := ""
            Loop spaces
                indent .= " "
        }
        indt := ""
        Loop indent ? lvl : 0
            indt .= indent
        is_array := (obj is Array)
        lvl += 1, out := ""
        for k, v in obj {
            if IsObject(k) || (k == "")
                throw Error("Invalid object key.", -1, k ? Format("<Object at 0x{:p}>", ObjPtr(obj)) : "<blank>")
            if !is_array
                out .= (ObjGetCapacity([k]) ? Jxon_Dump(k) : escape_str(k)) (indent ? ": " : ":")
            out .= Jxon_Dump(v, indent, lvl)
                . ( indent ? ",`n" . indt : "," )
        }
        if (out != "") {
            out := Trim(out, ",`n" . indent)
            if (indent != "")
                out := "`n" . indt . out . "`n" . SubStr(indt, StrLen(indent)+1)
        }
        return is_array ? "[" . out . "]" : "{" . out . "}"
    } else if (obj is Number)
        return obj
    else
        return escape_str(obj)

    escape_str(obj) {
        obj := StrReplace(obj, "\",  "\\")
        obj := StrReplace(obj, "`t", "\t")
        obj := StrReplace(obj, "`r", "\r")
        obj := StrReplace(obj, "`n", "\n")
        obj := StrReplace(obj, "`b", "\b")
        obj := StrReplace(obj, "`f", "\f")
        obj := StrReplace(obj, "/",  "\/")
        obj := StrReplace(obj, '"',  '\"')
        return '"' obj '"'
    }
}

; ─────────────────────────────────────────────
; JSON-Kompatibilitaet
; ─────────────────────────────────────────────
IsJsonCompatible(val) {
    if val is String || val is Number || val is Integer || val is Float
        return true
    if val is Array {
        for item in val {
            if !IsJsonCompatible(item)
                return false
        }
        return true
    }
    if val is Map {
        for k, v in val {
            if !(IsJsonCompatible(k) && IsJsonCompatible(v))
                return false
        }
        return true
    }
    return false
}

ToJsonCompatible(obj) {
    if Type(obj) = "Array" {
        out := []
        for item in obj
            out.Push(ToJsonCompatible(item))
        return out
    }
    if Type(obj) = "Map" {
        m := Map()
        for k, v in obj
            m[k] := ToJsonCompatible(v)
        return m
    }
    if IsObject(obj) && !(Type(obj) = "Array" || Type(obj) = "Map") {
        m := Map()
        for k, v in obj.OwnProps()
            m[k] := ToJsonCompatible(v)
        return m
    }
    return obj
}
