; AutoHotKey script with shortcuts (mostly Window 10)

; Auto-execute session here (top of the script until the first label)
; Load available monitors in another thread (one shot, in 10ms)
SetTimer, GetAllMonitors, -10
; Then, refresh the list at every 10 minutes
RefreshAllMonitors := Func("GetAllMonitors").Bind(true)
SetTimer, %RefreshAllMonitors%, 600000

; [Win] [Shift] [R] reloads running script
#+r::Reload

; Remaps CapsLock -> Esc
CapsLock::ESC

; [Win] [-] writes – (large dash)
#-::Send –

; [Ctrl] [Win] [space] writes non-breaking space
^#space::Send % Chr(160)

; Useful list of Windows executables:
; https://4sysops.com/wiki/list-of-ms-settings-uri-commands-to-open-specific-settings-in-windows-10/
; https://stackoverflow.com/questions/64078529/how-can-i-get-an-overview-of-uwp-registered-uris-and-aliases
; To discover apps UID: [Win] [R] shell:Appsfolder

; [Win] [B] opens bluetooth settings
#b::Run ms-settings:bluetooth

; [Win] [Shift] [T] opens To-Do
#+t::Run ms-to-do:

; [Win] [O] opens OneNote
#o::Run onenote:

; [Win] [T] toggles Windows Terminal
#t::LaunchOrToggleWindow("ahk_exe WindowsTerminal.exe", "wt")

; Launch or focus an application; or send to bottom if already on focus.
LaunchOrToggleWindow(ahkWinTitle, launchCmd)
{
  windowHandle := WinExist(ahkWinTitle)
  if (windowHandle > 0) {
    activeWindowHandle := WinExist("A")
    if (activeWindowHandle == windowHandle) {
      Send, !{ESC}
    } else {
      WinActivate, "ahk_id %windowHandle%"
      WinShow, "ahk_id %windowHandle%"
    }
  } else {
    Run, %launchCmd%
  }
}


; ====================================
; Change all monitors brightness
; ====================================

; [Win] [Shift] [-] to lower
#+_::
  For i, monitor in GetAllMonitors() {
    brightness := monitor.ChangeBrightness(-20)
  }
  ShowBrightnessBar(brightness)
return

; [Win] [Shift] [+] to higher
#+=::
  For i, monitor in GetAllMonitors() {
    brightness := monitor.ChangeBrightness(20)
  }
  ShowBrightnessBar(brightness)
return

; [Win] [Shift] [n] to toggle night mode
#+N::
  toggledToLighter := false
  For i, monitor in GetAllMonitors() {
    if (i == 1)
      toggledToLighter := monitor.ToggleBrightness(0, 100)
    else
      monitor.ToggleBrightness(0, 100, toggledToLighter)
  }
  ShowBrightnessBar(toggledToLighter ? 100 : 0, toggledToLighter ? "🔆" : "🌙")
return


; Control functions and classes
;__________________________________________________

; Abstract class for manipulating monitors (brightness level)
class GenericMonitor {
  ; Change the brightness by delta amount (range [-100, 100])
  ; Return new brightness level (range 0-100)
  ChangeBrightness(delta) {
    bright := this.GetBrightnessInfo()
    monitorDelta := Floor(delta * (bright.maximum - bright.minimum) / 100)
    newBright := this.SanitizeBrightnessLevel(bright.current + monitorDelta, delta > 0)
    this.SetBrightness(newBright)
    return Floor(100 * (newBright - bright.minimum) / (bright.maximum - bright.minimum))
  }

  ; Toggle brightness between lower and upper levels (range 0-100)
  ; Return true when toggled to upperLevel and false to lowerLevel
  ToggleBrightness(lowerLevel, upperLevel, overwriteDirection := "no") {
    bright := this.GetBrightnessInfo()
    monitorUpper := Ceil(bright.minimum + upperLevel * (bright.maximum - bright.minimum) / 100)
    monitorLower := Floor(bright.minimum + lowerLevel * (bright.maximum - bright.minimum) / 100)

    if (overwriteDirection != "no")
      changeToUpper := (overwriteDirection == "true" || overwriteDirection)  ; "bool conversion"
    else
      changeToUpper := bright.current <= Floor((monitorUpper + monitorLower) / 2)

    this.SetBrightness(changeToUpper ? monitorUpper : monitorLower)
    return changeToUpper
  }

  ; Return object with {minimum, current, maximum} levels of brightness
  GetBrightnessInfo()
  {
    ; Derived should implement
  }

  ; Return a valid brightness level
  SanitizeBrightnessLevel(level, roundUp := true)
  {
    ; Derived should implement
  }

  ; Set a brightness level (assuming its valid)
  SetBrightness(validLevel)
  {
    ; Derived should implement
  }
}

class WmiMonitor extends GenericMonitor {
  wmiObject := {}
  wmiMethods := {}
  brightnessInfo := {minimum: 0, current: 50, maximum: 100}

  __New(wmiObject, wmiMethods)
  {
    this.wmiObject := wmiObject
    this.wmiMethods := wmiMethods
  }

  GetBrightnessInfo()
  {
    service := "winmgmts:{impersonationLevel=impersonate}!\\.\root\WMI"
    escapedName := StrReplace(this.wmiObject.InstanceName, "\", "\\")
    query := "SELECT * FROM WmiMonitorBrightness WHERE InstanceName='" . escapedName . "'"
    for wmiObject in ComObjGet(service).ExecQuery(query) {
      this.wmiObject := wmiObject
      break  ; expecting one result only
    }

    info := {current: this.wmiObject.CurrentBrightness}
    for level in this.wmiObject.Level {
      if !info.HasKey("minimum")
        info.minimum := level
      info.maximum := level
    }
    this.brightnessInfo := info
    return this.brightnessInfo
  }

  SanitizeBrightnessLevel(level, roundUp := true)
  {
    previousLevel := -1
    for validLevel in this.wmiObject.Level {
      if (previousLevel < 0) {
        previousLevel := validLevel
      }
      if (level == validLevel) {
        return validLevel
      } else if (level > previousLevel && level < validLevel) {
        return roundUp ? validLevel : previousLevel
      }
      previousLevel := validLevel
    }
    return roundUp ? this.brightnessInfo.maximum : this.brightnessInfo.minimum
  }

  SetBrightness(validLevel)
  {
    this.wmiMethods.WmiSetBrightness(1, validLevel)
  }
}

; More inspiration in: https://github.com/tigerlily-dev/tigerlilys-Screen-Dimmer
class PhysicalMonitor extends GenericMonitor {
  physicalHandler := 0
  description := ""
  brightnessInfo := {minimum: 0, current: 50, maximum: 100}

  __New(physicalHandler, description := "")
  {
    this.physicalHandler := physicalHandler
    this.description := description
  }

  __Delete()
  {
    If !DllCall("dxva2\DestroyPhysicalMonitor", "ptr", this.physicalHandler)
      throw Exception("Unable to destroy monitor handle.`n`nError code: " Format("0x{:X}", A_LastError))
  }

  GetBrightnessInfo()
  {
    if DllCall("dxva2\GetMonitorBrightness", "ptr", this.physicalHandler
        , "uint*", minimum, "uint*", current, "uint*", maximum) {
      this.brightnessInfo := {minimum: minimum, current: current, maximum: maximum}
      return this.brightnessInfo
    }
    throw Exception("Unable to retrieve values.`n`nError code: " Format("0x{:X}", A_LastError))
  }

  SanitizeBrightnessLevel(level, roundUp := true)
  {
    level := (level > this.brightnessInfo.maximum) ? this.brightnessInfo.maximum : level
    level := (level < this.brightnessInfo.minimum) ? this.brightnessInfo.minimum : level
    return roundUp ? Ceil(level) : Floor(level)
  }

  SetBrightness(validLevel)
  {
    if !DllCall("dxva2\SetMonitorBrightness", "ptr", this.physicalHandler, "uint", validLevel)
      throw Exception("Unable to set value.`n`nError code: " Format("0x{:X}", A_LastError))
  }
}

; Get array of available GenericMonitor instances
GetAllMonitors(refresh := false)
{
  static monitors := []
  static isProcessing := false

  if (!monitors.Length() || refresh) && !isProcessing {
    isProcessing := true
    newMonitors := []
    for i, wmiMon in GetWMIMonitors() {
      newMonitors.Push(wmiMon)
    }
    for i, hMonitor in GetDisplayMonitorHandles(refresh) {
      for j, physMonitor in GetPhysicalMonitors(hMonitor) {
        if IsMonitorSupported(physMonitor.physicalHandler) {
          newMonitors.Push(physMonitor)
        }
      }
    }
    monitors := newMonitors
    isProcessing := false
  }

  return monitors
}

; Get array of WmiMonitor objects available in the system
GetWMIMonitors() {
  wmiMonitors := []
  service := "winmgmts:{impersonationLevel=impersonate}!\\.\root\WMI"
  for wmiObject in ComObjGet(service).ExecQuery("SELECT * FROM WmiMonitorBrightness WHERE Active=TRUE") {
    escapedName := StrReplace(wmiObject.InstanceName, "\", "\\")
    query := "SELECT * FROM wmiMonitorBrightNessMethods WHERE InstanceName='" . escapedName . "'"
    for wmiMethods in ComObjGet(service).ExecQuery(query) {
      wmiMonitors.Push(new WmiMonitor(wmiObject, wmiMethods))
      break  ; expecting one result only
    }
  }
  return wmiMonitors
}

; Get array of display monitor handles (not physical monitors)
GetDisplayMonitorHandles(refresh := false)
{
  static enumCallback := RegisterCallback("MonitorEnumCallback")
  static displayMonitors := []
  static isProcessing := false

  if (!displayMonitors.Length() || refresh) && !isProcessing
  {
    isProcessing := true
    if !DllCall("user32\EnumDisplayMonitors"
        , "ptr", 0
        , "ptr", 0
        , "ptr", enumCallback
        , "ptr", Object(displayMonitors)
        , "uint") {
      displayMonitors := []  ; error
    }
    isProcessing := false
  }
  return displayMonitors
}

; Callback from Win32 API, get one handle at a time.
MonitorEnumCallback(hMonitor, hDC, pRECT, userObjectAddr)
{
  displayMonitors := Object(userObjectAddr)
  displayMonitors.Push(hMonitor)
  return true  ; get next
}

; Get array of PhysicalMonitor instances from a display monitor handle
GetPhysicalMonitors(hMonitor)
{
  physicalMonitors := []
  if DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "ptr", hMonitor, "uint*", MONITOR_COUNT)
  {
    itemSize := A_PtrSize + 256  ; = 128 (sizeof string field) * 2 (WCHAR)
    VarSetCapacity(PHYSICAL_MONITORS, itemSize * MONITOR_COUNT)
    if DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR"
        , "int", hMonitor
        , "uint", MONITOR_COUNT
        , "ptr", &PHYSICAL_MONITORS)
    {
      Loop, %MONITOR_COUNT% {
        offset := (A_Index - 1) * itemSize
        hPhysMon := NumGet(PHYSICAL_MONITORS, offset, "ptr")
        description := StrGet(&PHYSICAL_MONITORS + offset + A_PtrSize)
        physicalMonitors.Push(new PhysicalMonitor(hPhysMon, description))
      }
    }
  }
  return physicalMonitors
}

IsMonitorSupported(hPhysMon)
{
  if !DllCall("dxva2\GetMonitorCapabilities", "int", hPhysMon, "uint*", monCaps, "uint*", monColorTemps) {
    return false  ; Monitor does not support DDC/CI
  } else if (monCaps & 0x2 = 0) {  ; MC_CAPS_BRIGHTNESS
    return false  ; Monitor does not support Get/SetMonitorBrightness functions
  }
  return true
}


; Brightness UI
;___________________________________________
; Instead of this faked bar, the real one can be invoked https://gist.github.com/krrr/3c3f1747480189dbb71f

BrightnessBar := ""
BrightnessText := ""
ShowBrightnessBar(brightness, overwriteLabel := "")
{
  ; https://www.autohotkey.com/docs/commands/Progress.htm
  IfWinNotExist, BrightnessWindow
  {
    Gui, bbar:Font, , Verdana
    Gui, bbar:Margin, 20, 20
    Gui, bbar:Add, Progress, w13 x26 h80 Background333333 c46A0A0 Vertical vBrightnessBar, %brightness%
    Gui, bbar:Add, Text, Center xp-4 yp90 cEEEEEE vBrightnessText, 100 ; start with full width
    Gui, bbar:Color, 0C0C0C
    Gui, bbar:-Caption +ToolWindow
    Gui, bbar:Show, % "w65 h140 x50 y60", BrightnessWindow
  }
  GuiControl, bbar:, BrightnessBar, %brightness%
  GuiControl, bbar:, BrightnessText, % (overwriteLabel != "" ? overwriteLabel : brightness)
  SetTimer, HideBrightnessBar, 2000
}

HideBrightnessBar()
{
  SetTimer, , Off
  Gui, bbar:Destroy
}
