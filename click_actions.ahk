#Requires AutoHotkey v2.0

AddClickTimingSegment(timing, delay, intervalCount) {
    if intervalCount < 1
        return
    if timing.Length && timing[timing.Length]["Delay"] = delay
        timing[timing.Length]["Count"] += intervalCount
    else
        timing.Push(Map("Delay", delay, "Count", intervalCount))
}

AppendActionClickTiming(timing, action) {
    if action.Has("ClickTiming") {
        for segment in action["ClickTiming"]
            AddClickTimingSegment(timing, segment["Delay"], segment["Count"])
    } else {
        AddClickTimingSegment(timing, action.Get("ClickDelay", 0), action.Get("Count", 1) - 1)
    }
}

CombineClickRuns(actions, selected := unset) {
    combined := []
    i := 1
    while i <= actions.Length {
        first := actions[i]
        j := i + 1
        if first["Type"] != "Click" || (IsSet(selected) && !selected.Has(i)) {
            combined.Push(first)
            i := j
            continue
        }

        button := first.Get("Button", "Left")
        count := first.Get("Count", 1)
        timing := []
        AppendActionClickTiming(timing, first)
        while j <= actions.Length {
            hasDelay := actions[j]["Type"] = "Delay"
            nextIndex := j + hasDelay
            if nextIndex > actions.Length || (IsSet(selected) && !selected.Has(nextIndex))
                break
            next := actions[nextIndex]
            if next["Type"] != "Click" || next.Get("Button", "Left") != button
                || next["X"] != first["X"] || next["Y"] != first["Y"]
                || Jxon_Dump(next.Get("SourceScreen", "")) != Jxon_Dump(first.Get("SourceScreen", ""))
                break

            gap := hasDelay ? actions[j]["Time"] : 0
            nextCount := next.Get("Count", 1)
            if nextCount > 9223372036854775807 - count
                break
            AddClickTimingSegment(timing, gap, 1)
            AppendActionClickTiming(timing, next)
            count += nextCount
            j := nextIndex + 1
        }

        if j > i + 1 {
            first := first.Clone()
            first["Count"] := count
            if first.Has("ClickTiming")
                first.Delete("ClickTiming")
            if first.Has("ClickDelay")
                first.Delete("ClickDelay")
            if timing.Length = 1
                first["ClickDelay"] := timing[1]["Delay"]
            else
                first["ClickTiming"] := timing
        }
        combined.Push(first)
        i := j
    }
    return combined
}

ExpandClickRuns(actions, selected := unset) {
    restored := []
    for index, action in actions {
        if action["Type"] != "Click" || action.Get("Count", 1) <= 1
            || (IsSet(selected) && !selected.Has(index)) {
            restored.Push(action)
            continue
        }

        timing := []
        AppendActionClickTiming(timing, action)
        single := action.Clone()
        for field in ["Count", "ClickDelay", "ClickTiming"] {
            if single.Has(field)
                single.Delete(field)
        }
        for segment in timing {
            Loop segment["Count"] {
                restored.Push(single.Clone())
                if segment["Delay"] > 0
                    restored.Push(Map("Type", "Delay", "Time", segment["Delay"]))
            }
        }
        restored.Push(single)
    }
    return restored
}
