#Requires AutoHotkey v2.0

ShowPlaybackPreview(*) {
    global ActionsList, GuiMain, IsRecording, IsReplaying, IsSeqPlaying
    static activePreview := ""
    if IsRecording || IsReplaying || IsSeqPlaying {
        ShowWarning("Bitte zuerst die Aufnahme oder Wiedergabe beenden.")
        return
    }
    if !ActionsList.Length {
        ShowWarning("Keine Aktionen vorhanden!")
        return
    }

    preview := ""
    try {
        profile := CurrentScreenProfile()
        actions := PrepareScreenPlayback(ActionsList, profile)
        ; Die Abfrage einer fehlenden Aufnahmeauflösung kann unterbrochen werden.
        if IsRecording || IsReplaying || IsSeqPlaying
            return
        area := PreviewCaptureArea(profile["Target"])
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        scale := Min(1, (right - left - 75) / area["Width"], (bottom - top - 300) / area["Height"])
        width := Max(1, Round(area["Width"] * scale))
        height := Max(1, Round(area["Height"] * scale))
        rows := []
        pointer := ""
        for action in actions
            rows.Push(PreviewActionPoints(action, area, width, height, &pointer))
        markers := LayoutPreviewMarkers(rows, width, height)

        ; Eine ältere Vorschau darf nicht Teil der neuen Bildschirmaufnahme werden.
        if IsObject(activePreview) {
            try activePreview.Destroy()
            activePreview := ""
        }
        GuiMain.Hide()
        try {
            DllCall("dwmapi\DwmFlush", "Int")
            bitmap := CapturePreviewBitmap(area, width, height, markers)
        } finally {
            GuiMain.Show("NoActivate")
        }

        try {
            preview := Gui("-DPIScale +Owner" GuiMain.Hwnd " +AlwaysOnTop", "Screenshot-Vorschau")
            preview.MarginX := 10
            preview.MarginY := 10
            preview.SetFont("s9", "Segoe UI")
            preview.AddPicture("x10 y10 w" width " h" height, "HBITMAP:*" bitmap)
        } finally {
            DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        }
        preview.SetFont("bold cWhite")
        first := preview.AddText("x0 y0 w108 h18 Center +0x200 BackgroundA52A16 Hidden")
        second := preview.AddText("x0 y0 w108 h18 Center +0x200 BackgroundA52A16 Hidden")
        preview.SetFont("norm cDefault")
        preview.AddText("xm y" (height + 22),
            "Zeile auswählen, um ihren Punkt zu markieren. +N zeigt weitere Punkte in der Nähe.")
        list := preview.AddListView("xm w" Max(430, width) " r6 -Multi -SortHdr", ["Nr.", "Aktion", "Position"])
        for index, action in actions {
            points := rows[index]
            position := points.Length ? "" : "Keine feste Position"
            for point in points {
                position .= (position = "" ? "" : " → ") point.X ", " point.Y
                if !point.Visible
                    position .= " (außerhalb)"
                else if point.Marker.Points.Length > 1
                    position .= " (Gruppe " point.Marker.Label ")"
            }
            if points.Length && action["Type"] = "Scroll" && !HasScrollPosition(action)
                position .= " (zuletzt angesteuert)"
            list.Add("", index, FormatActionShort(action), position)
        }
        list.ModifyCol(1, 55)
        list.ModifyCol(2, 185)
        list.ModifyCol(3, "AutoHdr")
        list.OnEvent("ItemSelect", (ctrl, item, selected) =>
            HighlightPreviewAction(ctrl, rows, first, second, width, height))
        preview.OnEvent("Close", ClosePlaybackPreview)
        preview.OnEvent("Escape", ClosePlaybackPreview)
        preview.Show("x" (left + 15) " y" (top + 15))
        activePreview := preview
    } catch Error as err {
        if IsObject(preview)
            preview.Destroy()
        ShowWarning(err.Message)
    }
}

ClosePlaybackPreview(preview, *) {
    preview.Destroy()
}

PreviewCaptureArea(target) {
    if target != "" {
        for monitor in GetScreenMonitors() {
            if monitor["Name"] = target
                return monitor
        }
        throw Error("Der gewählte Zielbildschirm ist nicht angeschlossen.")
    }
    return Map("X", SysGet(76), "Y", SysGet(77), "Width", SysGet(78), "Height", SysGet(79))
}

PreviewActionPoints(action, area, width, height, &pointer) {
    kind := action["Type"]
    if kind = "Drag" {
        coordinates := [[action["X1"], action["Y1"]], [action["X2"], action["Y2"]]]
    } else if kind = "Scroll" && !HasScrollPosition(action) {
        coordinates := IsObject(pointer) ? [pointer] : []
    } else if action.Has("X") && action.Has("Y") {
        coordinates := [[action["X"], action["Y"]]]
    } else {
        return []
    }
    points := []
    for pair in coordinates {
        x := pair[1] - area["X"]
        y := pair[2] - area["Y"]
        visible := x >= 0 && x < area["Width"] && y >= 0 && y < area["Height"]
        points.Push({X: pair[1], Y: pair[2], Visible: visible,
            ImageX: Floor(x * width / area["Width"]), ImageY: Floor(y * height / area["Height"])})
    }
    if coordinates.Length
        pointer := coordinates[coordinates.Length]
    return points
}

HighlightPreviewAction(list, rows, first, second, width, height) {
    first.Visible := false
    second.Visible := false
    row := list.GetNext()
    if !row
        return

    points := rows[row]
    labelWidth := Min(width, 108)
    labelHeight := 18
    firstLeft := 0
    firstTop := 0
    for index, marker in [first, second] {
        if index > points.Length || !points[index].Visible
            continue

        point := points[index]
        left := Max(0, Min(width - labelWidth, point.ImageX - labelWidth // 2))
        top := Max(0, Min(height - labelHeight, point.ImageY - labelHeight // 2))
        if index = 1 {
            firstLeft := left
            firstTop := top
        } else if first.Visible && Abs(left - firstLeft) < labelWidth && Abs(top - firstTop) < labelHeight {
            if (point.ImageX = points[1].ImageX && point.ImageY = points[1].ImageY) || height < 2 * labelHeight {
                first.Text := row " Start/Ende"
                break
            }
            top := firstTop + labelHeight <= height - labelHeight
                ? firstTop + labelHeight : firstTop - labelHeight
            ; Liegt der erste Marker nahe der Mitte eines sehr flachen Bildes,
            ; verankere beide am oberen Rand.
            if top < 0 {
                first.Move(10 + firstLeft, 10)
                top := labelHeight
            }
        }

        marker.Text := row (points.Length = 2 ? (index = 1 ? " Start" : " Ende") : "")
        marker.Move(10 + left, 10 + top, labelWidth, labelHeight)
        marker.Visible := true
    }
}

LayoutPreviewMarkers(rows, width, height) {
    ; Platz für die längste mögliche Beschriftung (Nummer, Endpunkt und Anzahl).
    digits := StrLen(String(rows.Length))
    columns := Max(1, width // ((2 * digits + 4) * 9))
    bands := Max(1, height // 18)
    markers := Map()
    for index, points in rows {
        for endpoint, point in points {
            if !point.Visible
                continue
            column := point.ImageX * columns // width
            band := point.ImageY * bands // height
            key := band * columns + column
            if !markers.Has(key) {
                label := String(index) (points.Length = 2 ? (endpoint = 1 ? "a" : "b") : "")
                markers[key] := {Label: label, Points: [],
                    X: Ceil(column * width / columns), Y: Ceil(band * height / bands)}
            }
            marker := markers[key]
            marker.Points.Push([point.ImageX, point.ImageY])
            point.Marker := marker
        }
    }
    return markers
}

CapturePreviewBitmap(area, width, height, markers) {
    screenDC := DllCall("user32\GetDC", "Ptr", 0, "Ptr")
    memoryDC := 0
    bitmap := 0
    previous := 0
    completed := false
    try {
        if !screenDC
            throw Error("Der Desktop konnte nicht erfasst werden.")
        memoryDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
        ; 24-Bit-DIB: GDI setzt beim Zeichnen keinen verlässlichen Alphakanal.
        bitmapInfo := Buffer(40, 0)
        NumPut("UInt", 40, "Int", width, "Int", height, "UShort", 1, "UShort", 24, bitmapInfo)
        bitmap := DllCall("gdi32\CreateDIBSection", "Ptr", screenDC, "Ptr", bitmapInfo,
            "UInt", 0, "Ptr*", &pixels := 0, "Ptr", 0, "UInt", 0, "Ptr")
        if !memoryDC || !bitmap
            throw Error("Für die Screenshot-Vorschau steht kein Bildspeicher zur Verfügung.")
        previous := DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")
        DllCall("gdi32\SetStretchBltMode", "Ptr", memoryDC, "Int", 4)
        if !previous || !DllCall("gdi32\StretchBlt", "Ptr", memoryDC, "Int", 0, "Int", 0,
            "Int", width, "Int", height, "Ptr", screenDC, "Int", area["X"], "Int", area["Y"],
            "Int", area["Width"], "Int", area["Height"], "UInt", 0x40CC0020, "Int")
            throw Error("Der Bildschirm konnte nicht kopiert werden.")

        DllCall("gdi32\SetBkColor", "Ptr", memoryDC, "UInt", 0x874C17)
        DllCall("gdi32\SetTextColor", "Ptr", memoryDC, "UInt", 0xFFFFFF)
        for key, marker in markers {
            count := marker.Points.Length
            label := marker.Label (count > 1 ? "+" (count - 1) : "")
            DllCall("gdi32\TextOutW", "Ptr", memoryDC, "Int", marker.X, "Int", marker.Y,
                "WStr", label, "Int", StrLen(label))
        }
        for key, marker in markers {
            for point in marker.Points {
                DllCall("gdi32\SetPixelV", "Ptr", memoryDC, "Int", point[1], "Int", point[2],
                    "UInt", 0xFFFFFF, "Int")
            }
        }
        completed := true
        return bitmap
    } finally {
        if previous
            DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", previous)
        if memoryDC
            DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
        if bitmap && !completed
            DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        if screenDC
            DllCall("user32\ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    }
}
