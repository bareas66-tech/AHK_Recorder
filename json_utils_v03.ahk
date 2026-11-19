;=========================
; Datei: json_utils_v03.ahk
; Neu: SetCurrentFile() wird nach Laden/Speichern aufgerufen
;=========================

#Requires AutoHotkey v2.0

WriteActionFile(path, actions, profile := unset) {
    if !IsSet(profile) && actions.HasOwnProp("RecorderScreenProfile")
        profile := actions.RecorderScreenProfile
    if !IsSet(profile) {
        for action in actions {
            if action.Has("SourceScreen") {
                profile := Map("Target", "", "Mode", 2, "Source", action["SourceScreen"])
                break
            }
        }
    }
    if IsSet(profile) {
        profile := profile.Clone()
        if !IsObject(profile["Source"]) {
            for action in actions {
                if action.Has("SourceScreen") {
                    profile["Source"] := action["SourceScreen"]
                    break
                }
            }
        }
        payload := Map("Format", "AHKRecorder", "Version", 1, "PlaybackScreen", profile, "Actions", actions)
        if IsObject(profile["Source"])
            payload["RecordingScreen"] := profile["Source"].Clone()
    } else {
        payload := actions
    }
    json := Jxon_Dump(ToJsonCompatible(payload), 0)
    expectedBytes := StrPut(json, "UTF-8") - 1
    tempPath := path ".tmp-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount
    try {
        file := FileOpen(tempPath, "w", "UTF-8")
        try {
            if file.Write(json) != expectedBytes
                throw Error("Die temporäre JSON-Datei konnte nicht vollständig geschrieben werden.")
        } finally {
            file.Close()
        }
        if FileGetSize(tempPath) != expectedBytes + 3  ; UTF-8-BOM
            throw Error("Die Größe der temporären JSON-Datei stimmt nicht mit den geschriebenen Daten überein.")
        try FileMove(tempPath, path, 1)
        catch Error as err
            throw Error("Die Zieldatei konnte nicht ersetzt werden: " path Chr(10) err.Message)
    } finally {
        if FileExist(tempPath)
            try FileDelete(tempPath)
    }
}

ReadActionFile(path) {
    json := FileRead(path, "UTF-8")
    actions := Jxon_Load(&json, &literalFields)
    profile := ""
    if actions is Map {
        if actions.Get("Format", "") != "AHKRecorder" || actions.Get("Version", 0) != 1
            throw ValueError("Unbekanntes Aktionsdateiformat.")
        profile := ValidatePlaybackScreen(actions.Get("PlaybackScreen", ""))
        if actions.Has("RecordingScreen") {
            recordedScreen := ValidateSourceScreen(actions["RecordingScreen"])
            if !IsObject(profile["Source"])
                profile["Source"] := recordedScreen
        }
        actions := actions.Get("Actions", "")
    }
    if !(actions is Array)
        throw ValueError("Die Datei muss eine Liste von Aktionen enthalten.")

    static fields := Map(
        "Click", ["X", "Y"], "LongClick", ["X", "Y", "Duration"],
        "Drag", ["X1", "Y1", "X2", "Y2"], "MouseMove", ["X", "Y"],
        "Delay", ["Time"], "Scroll", ["Direction", "Amount"],
        "KeyPress", ["Key"], "Comment", ["Text"], "TextInput", ["Text"])
    static minimums := Map("Duration", 0, "Time", 0, "Amount", 1,
        "Count", 1, "ClickDelay", 0, "BgColor", -1, "TextColor", -1)

    for index, action in actions {
        prefix := "Aktion " index " – "
        if !(action is Map) || !action.Has("Type") || Type(action["Type"]) != "String"
            throw ValueError(prefix "Aktionstyp fehlt oder ist ungültig.")
        kind := action["Type"]
        if !fields.Has(kind)
            throw ValueError(prefix "Unbekannter Typ: " kind)
        literals := literalFields.Get(action, Map())
        for field in fields[kind] {
            if !action.Has(field)
                throw ValueError(prefix "Feld fehlt: " field)
            if literals.Has(field)
                throw ValueError(prefix "Wahrheitswert oder null in: " field)
            value := action[field]
            if field = "Text" || field = "Key" || field = "Direction" {
                if Type(value) != "String"
                    throw ValueError(prefix "Text erwartet in: " field)
            } else {
                action[field] := ReadActionInteger(value, minimums.Get(field, -9223372036854775808), prefix, field)
                if RegExMatch(field, "^[XY][12]?$")
                    ValidateActionCoordinate(action[field], prefix, field)
            }
        }
        for field in ["Count", "ClickDelay", "BgColor", "TextColor"] {
            if !action.Has(field)
                continue
            if literals.Has(field)
                throw ValueError(prefix "Wahrheitswert oder null in: " field)
            action[field] := ReadActionInteger(action[field], minimums[field], prefix, field)
        }
        if action.Has("SourceScreen")
            ValidateSourceScreen(action["SourceScreen"])
        if action.Has("ClickTiming")
            ValidateClickTiming(action, literalFields, prefix)
        if kind = "KeyPress" && Trim(action["Key"]) = ""
            throw ValueError(prefix "Tasteneingabe fehlt.")
        for field in ["BgColor", "TextColor"] {
            if action.Has(field) && action[field] > 0xFFFFFF
                throw ValueError(prefix "Ungültiger Farbwert in: " field)
        }
        if kind = "Scroll" && (action.Has("X") || action.Has("Y")) {
            for field in ["X", "Y"] {
                if !action.Has(field) || literals.Has(field)
                    throw ValueError(prefix "Ungültige Scrollkoordinate: " field)
                action[field] := ReadActionInteger(action[field], -9223372036854775808, prefix, field)
                ValidateActionCoordinate(action[field], prefix, field)
            }
        }
        if kind = "Scroll" && action["Direction"] != "Up" && action["Direction"] != "Down"
            throw ValueError(prefix "Ungültige Scrollrichtung.")
        if action.Has("Button") && (Type(action["Button"]) != "String" || (action["Button"] != "Left" && action["Button"] != "Right"))
            throw ValueError(prefix "Ungültige Maustaste.")
    }
    if IsObject(profile)
        actions.DefineProp("RecorderScreenProfile", {Value: profile})
    return actions
}

; ==== JSON Parser (Jxon) ====

ValidateSourceScreen(rect) {
    if !(rect is Map)
        throw ValueError("Die Aufnahmefläche ist ungültig.")
    for field in ["X", "Y", "Width", "Height"] {
        if !rect.Has(field) || !(rect[field] is Integer)
            throw ValueError("Die Aufnahmefläche enthält ungültige Werte.")
    }
    if rect["Width"] < 1 || rect["Height"] < 1 || rect["Width"] > 2147483647 || rect["Height"] > 2147483647
        throw ValueError("Die Aufnahmeauflösung ist ungültig.")
    ValidateActionCoordinate(rect["X"], "", "X")
    ValidateActionCoordinate(rect["Y"], "", "Y")
    return rect
}

ValidatePlaybackScreen(profile) {
    if !(profile is Map) || !(profile.Get("Target", "") is String)
        throw ValueError("Die Bildschirmeinstellung ist ungültig.")
    mode := profile.Get("Mode", 2)
    if !(mode is Integer) || (mode != 1 && mode != 2)
        throw ValueError("Die Bildschirm-Anpassung ist ungültig.")
    source := profile.Get("Source", "")
    if IsObject(source)
        ValidateSourceScreen(source)
    else if !(source == "")
        throw ValueError("Die Aufnahmefläche ist ungültig.")
    return Map("Target", profile.Get("Target", ""), "Mode", mode, "Source", source)
}
ValidateActionCoordinate(value, prefix, field) {
    if value < -2147483648 || value > 2147483647
        throw ValueError(prefix "Koordinate außerhalb des Windows-Zahlenbereichs in: " field)
}

ReadActionInteger(value, minimum, prefix, field) {
    overflow := prefix "Zahl außerhalb des 64-Bit-Bereichs in: " field
    if value is String {
        value := Trim(value)
        if RegExMatch(value, "i)^([+-]?)0x([0-9a-f]+)$", &parts) {
            digits := LTrim(parts[2], "0")
            negative := parts[1] = "-"
            if StrLen(digits) > 16 || (StrLen(digits) = 16 && SubStr(digits, 1, 1) ~= "i)[89a-f]"
                && !(negative && digits = "8000000000000000"))
                throw ValueError(overflow)
            value := digits = "" ? 0 : Integer((negative ? "-" : "") "0x" digits)
        } else if RegExMatch(value, "^([+-]?)([0-9]+)$", &parts) {
            digits := LTrim(parts[2], "0")
            normalized := digits = "" ? "0" : (parts[1] = "-" ? "-" : "") digits
            value := Integer(normalized)
            if !(String(value) == normalized)
                throw ValueError(overflow)
        }
    }
    if !(value is Integer) || value < minimum
        throw ValueError(prefix "Ungültige Zahl in: " field)
    return value
}

ValidateClickTiming(action, literalFields, prefix) {
    timing := action["ClickTiming"]
    if action["Type"] != "Click" || action.Has("ClickDelay") || !(timing is Array) || !timing.Length
        throw ValueError(prefix "Ungültige Klickabstände.")
    remaining := action.Get("Count", 1) - 1
    for segment in timing {
        if !(segment is Map)
            throw ValueError(prefix "Ungültiger Abschnitt in Klickabständen.")
        flags := literalFields.Get(segment, Map())
        count := segment.Get("Count", 0)
        delay := segment.Get("Delay", -1)
        if !(count is Integer) || count < 1 || count > remaining || flags.Has("Count")
            || !(delay is Integer) || delay < 0 || flags.Has("Delay")
            throw ValueError(prefix "Ungültiger Abschnitt in Klickabständen.")
        remaining -= count
    }
    if remaining != 0
        throw ValueError(prefix "Die Klickabstände passen nicht zur Klickanzahl.")
}

Jxon_Load(&src, &literalFields := unset) {
    literalFields := Map()
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
                if !RegExMatch(src, 'A)"((?:[^"\\\x00-\x1F]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*)"', &match, pos)
                    throw ValueError("Ungültige JSON-Zeichenkette an Zeichen " pos ".")
                pos += match.Len - 1
                val := DecodeJsonString(match[1])
                if is_key {
                    if obj.Has(val)
                        throw ValueError("Doppelter JSON-Schlüssel: " val " (Zeichen " pos ").")
                    key := val, next := ":"
                    continue
                }
            } else {
                val := SubStr(src, pos, i := RegExMatch(src, "[\]\},\s]|$",, pos)-pos)
                if RegExMatch(val, "^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$") && IsNumber(val) {
                    number := val + 0
                    if RegExMatch(val, "^-?[0-9]+$") {
                        if val != "-0" && !(String(number) == val)
                            throw ValueError("JSON-Ganzzahl außerhalb des 64-Bit-Bereichs an Zeichen " pos ".")
                    } else if Abs(number) > 1.7976931348623157e308 {
                        throw ValueError("JSON-Zahl außerhalb des darstellbaren Bereichs an Zeichen " pos ".")
                    }
                    val := number
                } else if (val == "true" || val == "false" || val == "null") {
                    if !is_array {
                        if !literalFields.Has(obj)
                            literalFields[obj] := Map()
                        literalFields[obj][key] := true
                    }
                    val := val == "null" ? "" : val == "true"
                }
                else
                    throw ValueError("Ungültiger JSON-Wert an Zeichen " pos ".")
                pos += i-1
            }
            is_array ? obj.Push(val) : obj[key] := val
            next := obj == tree ? "" : is_array ? ",]" : ",}"
        }
    }
    if stack.Length != 1 || tree.Length != 1 || next != ""
        throw ValueError("Die JSON-Datei ist leer oder unvollständig.")
    return tree[1]
}

DecodeJsonString(encoded) {
    static escapes := Map('"', '"', "\", "\", "/", "/", "b", "`b", "f", "`f", "n", "`n", "r", "`r", "t", "`t")
    decoded := ""
    cursor := 1
    while start := InStr(encoded, "\",, cursor) {
        decoded .= SubStr(encoded, cursor, start - cursor)
        kind := SubStr(encoded, start + 1, 1)
        cursor := start + 2
        if kind != "u" {
            decoded .= escapes[kind]
            continue
        }
        code := Integer("0x" SubStr(encoded, cursor, 4))
        cursor += 4
        if code >= 0xD800 && code <= 0xDBFF {
            if SubStr(encoded, cursor, 2) != "\u"
                throw ValueError("Unvollständiges Unicode-Surrogatpaar.")
            low := Integer("0x" SubStr(encoded, cursor + 2, 4))
            if low < 0xDC00 || low > 0xDFFF
                throw ValueError("Ungültiges Unicode-Surrogatpaar.")
            code := 0x10000 + ((code - 0xD800) << 10) + low - 0xDC00
            cursor += 6
        } else if code >= 0xDC00 && code <= 0xDFFF {
            throw ValueError("Ungültiges Unicode-Surrogatpaar.")
        }
        if code = 0
            throw ValueError("Nullzeichen werden in Aktionsdateien nicht unterstützt.")
        decoded .= Chr(code)
    }
    return decoded SubStr(encoded, cursor)
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
            if !is_array {
                if IsObject(k)
                    throw TypeError("JSON-Objektschlüssel muss Text oder eine Zahl sein.")
                out .= escape_str(String(k)) (indent ? ": " : ":")
            }
            out .= Jxon_Dump(v, indent, lvl)
                . ( indent ? ",`n" . indt : "," )
        }
        if (out != "") {
            out := Trim(out, ",`n" . indent)
            if (indent != "")
                out := "`n" . indt . out . "`n" . SubStr(indt, StrLen(indent)+1)
        }
        return is_array ? "[" . out . "]" : "{" . out . "}"
    } else if (obj is Number) {
        if obj is Float && !(Abs(obj) <= 1.7976931348623157e308)
            throw ValueError("Nicht endliche Zahlen können nicht als JSON gespeichert werden.")
        return obj
    } else
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
        cursor := 1
        while found := RegExMatch(obj, "[\x00-\x1F]", &control, cursor) {
            escape := Format("\u{:04X}", Ord(control[0]))
            obj := SubStr(obj, 1, found - 1) escape SubStr(obj, found + 1)
            cursor := found + StrLen(escape)
        }
        return '"' obj '"'
    }
}

; ─────────────────────────────────────────────
; Aufnahme-Kommentare mit Dateiname versehen.
; Aktualisiert genau zwei Einträge:
;   - Den allerersten  Kommentar, dessen Text mit "Aufnahme gestartet" beginnt
;   - Den allerletzten Kommentar, dessen Text mit "Aufnahme beendet"  beginnt
; Andere Kommentare (z.B. vom User manuell eingefügt) werden nicht verändert.
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
