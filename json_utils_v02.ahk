;=========================
; Datei: json_utils.ahk
;=========================
#Requires AutoHotkey v2.0

SaveActions(*) {
    global ActionsList, GuiMain

    if !(ActionsList is Array) {
        ShowError("❌ ActionsList ist kein Array!")
        return
    }

    ; Temporär AlwaysOnTop ausschalten, damit der FileSelect-Dialog im Vordergrund ist
    WinSetAlwaysOnTop -1, GuiMain

    ; Dateidialog öffnen
    file := FileSelect("S16", A_ScriptDir "\actions.json", "JSON speichern unter...", "JSON-Dateien (*.json)")

    ; AlwaysOnTop wieder einschalten
    WinSetAlwaysOnTop -1, GuiMain

    if !file {
        ShowInfo("Speichern abgebrochen.")
        return
    }

    if !InStr(file, ".json", false)
        file .= ".json"

    ; Datei schreiben
    try {
        serial := ToJsonCompatible(ActionsList)
        json := Jxon_Dump(serial, indent:=0)

        f := FileOpen(file, "w", "UTF-8") ; 'w' = write/overwrite
        if !f {
            ShowError("❌ Datei konnte nicht geöffnet werden: " file)
            return
        }
        f.Write(json)
        f.Close()

        ShowInfo("✅ Aktionen gespeichert in:`n" file)
    } catch as err {
        ShowError("❌ Fehler beim Speichern:`n" err.Message)
    }
}

LoadActions(*) {
    global ActionsList

    file := FileSelect("3", A_ScriptDir, "JSON-Datei laden", "JSON-Dateien (*.json)")
    if !file {
        ShowInfo("Laden abgebrochen.")
        return
    }

    if !FileExist(file) {
        ShowError("❌ Datei nicht gefunden:`n" file)
        return
    }

    try {
        json := FileRead(file, "UTF-8")
        ActionsList := Jxon_Load(&json)
        if !(ActionsList is Array) {
            ShowWarning("⚠️ Datei enthält keine gültige Aktionsliste!")
            return
        }

        UpdateActionsList()
        ShowInfo("✅ Aktionen geladen aus:`n" file)
    } catch as err {
        ShowError("❌ Fehler beim Laden der Datei:`n" err.Message)
    }
}



; ==== JSON Parser (Jxon) ====
; (Nur die JSON-Funktionen aus deinem alten Script)
; ---- hier bleibt deine Jxon_Load() und Jxon_Dump() Funktion unverändert ----
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
			ln := testArr.Length
			col := pos - InStr(src, "`n",, -(StrLen(src)-pos+1))
			msg := Format("{}: line {} col {} (char {})"
			,   (next == "")      ? ["Extra data", ch := SubStr(src, pos)][1]
			  : (next == "'")     ? "Unterminated string starting at"
			  : (next == "\")     ? "Invalid \escape"
			  : (next == ":")     ? "Expecting ':' delimiter"
			  : (next == '"')     ? "Expecting object key enclosed in double quotes"
			  : (next == '"}')    ? "Expecting object key enclosed in double quotes or object closing '}'"
			  : (next == ",}")    ? "Expecting ',' delimiter or object closing '}'"
			  : (next == ",]")    ? "Expecting ',' delimiter or array closing ']'"
			  : [ "Expecting JSON value(string, number, [true, false, null], object or array)"
			    , ch := SubStr(src, pos, (SubStr(src, pos)~="[\]\},\s]|$")-1) ][1]
			, ln, col, pos)
			throw Error(msg, -1, ch)
		}
		obj := stack[1]
        is_array := (obj is Array)
		if i := InStr("{[", ch) { ; start new object / map?
			val := (i = 1) ? Map() : Array()	; ahk v2
			is_array ? obj.Push(val) : obj[key] := val
			stack.InsertAt(1,val)
			next := '"' ((is_key := (ch == "{")) ? "}" : "{[]0123456789-tfn")
		} else if InStr("}]", ch) {
			stack.RemoveAt(1)
            next := (stack[1]==tree) ? "" : (stack[1] is Array) ? ",]" : ",}"
		} else if InStr(",:", ch) {
			is_key := (!is_array && ch == ",")
			next := is_key ? '"' : '"{[0123456789-tfn'
		} else { ; string | number | true | false | null
			if (ch == '"') { ; string
				i := pos
				while i := InStr(src, '"',, i+1) {
					val := StrReplace(SubStr(src, pos+1, i-pos-1), "\\", "\u005C")
					if (SubStr(val, -1) != "\")
						break
				}
				if !i ? (pos--, next := "'") : 0
					continue
				pos := i ; update pos
				val := StrReplace(val, "\/", "/")
				val := StrReplace(val, '\"', '"')
				, val := StrReplace(val, "\b", "`b")
				, val := StrReplace(val, "\f", "`f")
				, val := StrReplace(val, "\n", "`n")
				, val := StrReplace(val, "\r", "`r")
				, val := StrReplace(val, "\t", "`t")
				i := 0
				while i := InStr(val, "\",, i+1) {
					if (SubStr(val, i+1, 1) != "u") ? (pos -= StrLen(SubStr(val, i)), next := "\") : 0
						continue 2
					xxxx := Abs("0x" . SubStr(val, i+2, 4)) ; \uXXXX - JSON unicode escape sequence
					if (xxxx < 0x100)
						val := SubStr(val, 1, i-1) . Chr(xxxx) . SubStr(val, i+6)
				}
				if is_key {
					key := val, next := ":"
					continue
				}
			} else { ; number | true | false | null
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
Jxon_Dump(obj, indent:="", lvl:=1) {
	if IsObject(obj) {
        If !(obj is Array || obj is Map || obj is String || obj is Number)
			throw Error("Object type not supported.", -1, Format("<Object at 0x{:p}>", ObjPtr(obj)))
		if IsInteger(indent)
		{
			if (indent < 0)
				throw Error("Indent parameter must be a postive integer.", -1, indent)
			spaces := indent, indent := ""
			
			Loop spaces ; ===> changed
				indent .= " "
		}
		indt := ""
		Loop indent ? lvl : 0
			indt .= indent
        is_array := (obj is Array)
		lvl += 1, out := "" ; Make #Warn happy
		for k, v in obj {
			if IsObject(k) || (k == "")
				throw Error("Invalid object key.", -1, k ? Format("<Object at 0x{:p}>", ObjPtr(obj)) : "<blank>")
			if !is_array ;// key ; ObjGetCapacity([k], 1)
				out .= (ObjGetCapacity([k]) ? Jxon_Dump(k) : escape_str(k)) (indent ? ": " : ":") ; token + padding
			out .= Jxon_Dump(v, indent, lvl) ; value
				.  ( indent ? ",`n" . indt : "," ) ; token + indent
		}
		if (out != "") {
			out := Trim(out, ",`n" . indent)
			if (indent != "")
				out := "`n" . indt . out . "`n" . SubStr(indt, StrLen(indent)+1)
		}
		return is_array ? "[" . out . "]" : "{" . out . "}"
    } Else If (obj is Number)
        return obj
    
    Else ; String
        return escape_str(obj)
    escape_str(obj) {
        obj := StrReplace(obj,"\","\\")
        obj := StrReplace(obj,"`t","\t")
        obj := StrReplace(obj,"`r","\r")
        obj := StrReplace(obj,"`n","\n")
        obj := StrReplace(obj,"`b","\b")
        obj := StrReplace(obj,"`f","\f")
        obj := StrReplace(obj,"/","\/")
        obj := StrReplace(obj,'"','\"')
        return '"' obj '"'
    }
}

; ============================================================
; Hilfsfunktionen für Save/Load (AutoHotkey v2 kompatibel)
; ============================================================

; --- Prüft, ob ein Wert JSON-kompatibel ist ---
IsJsonCompatible(val) {
    if val is String || val is Number || val is Integer || val is Float
        return true
    if val is Array {
        for item in val
            if !IsJsonCompatible(item)
                return false
        return true
    }
    if val is Map {
        for k, v in val
            if !(IsJsonCompatible(k) && IsJsonCompatible(v))
                return false
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










