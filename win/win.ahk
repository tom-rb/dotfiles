; AutoHotKey script with shortcuts (mostly Window 10)

; Win+Shift+R reloads running script
#+r::Reload

; Remaps CapsLock -> Esc
CapsLock::ESC

; Useful list:
; https://4sysops.com/wiki/list-of-ms-settings-uri-commands-to-open-specific-settings-in-windows-10/
; To discover apps UID: Win+R shell:Appsfolder

; Win+B opens bluetooth settings
#b::Run ms-settings:bluetooth

; Win+T opens To-Do
#t::Run ms-to-do:
return

; Win+O opens OneNote
#o::Run onenote:
return

; ==================================
; Change external monitor brightness
; https://superuser.com/a/1532135/1050438

; [Win] [Shift] [-] to lower
#+_::
  brightness := changeMonitorBrightness(-10)
  show_brightness_bar(brightness)
return

; [Win] [Shift] [+] to higher
#+=::
  brightness := changeMonitorBrightness(10)
  show_brightness_bar(brightness)
return

; [Win] [Shift] [n] to toogle night mode
#+N::
  brightness := toggleMonitorBrightness(20, 100)
  show_brightness_bar(brightness, brightness == 20 ? "🌙" : "🔆")
return

; Control functions
;___________________________________________

getMonitorHandle()
{
  MouseGetPos, xpos, ypos
  point := ( ( xpos ) & 0xFFFFFFFF ) | ( ( ypos ) << 32 )

  hMon := DllCall("MonitorFromPoint" ; Initialize Monitor handle
  , "int64", point ; point on monitor
  , "uint", 1) ; flag to return primary monitor on failure

  VarSetCapacity(Physical_Monitor, 8 + 256, 0)
  DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR" ; Get Physical Monitor from handle
  , "int", hMon ; monitor handle
  , "uint", 1 ; monitor array size
  , "int", &Physical_Monitor) ; point to array with monitor

return hPhysMon := NumGet(Physical_Monitor)
}

destroyMonitorHandle(handle)
{
  DllCall("dxva2\DestroyPhysicalMonitor", "int", handle)
}

toggleMonitorBrightness(lower, upper)
{
  vcpLuminance := 0x10 ; code for brightness
  handle := getMonitorHandle()

  DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply"
  , "int", handle
  , "char", vcpLuminance
  , "Ptr", 0
  , "uint*", luminance
  , "uint*", maximumValue)

  if (luminance >= upper) {
    luminance := lower
  } else if (luminance <= lower) {
    luminance := upper
  } else if (luminance <= Floor((upper+lower)/2)) {
    luminance := upper
  } else {
    luminance := lower
  }

  if (luminance > maximumValue) {
    luminance := maximumValue
  } else if (luminance < 0) {
    luminance := 0
  }

  DllCall("dxva2\SetVCPFeature"
  , "int", handle
  , "char", vcpLuminance
  , "uint", luminance)
  destroyMonitorHandle(handle)
return luminance
}

changeMonitorBrightness(delta)
{
  vcpLuminance := 0x10
  handle := getMonitorHandle()

  DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply"
  , "int", handle
  , "char", vcpLuminance
  , "Ptr", 0
  , "uint*", luminance
  , "uint*", maximumValue)

  luminance += delta

  if (luminance > maximumValue) {
    luminance := maximumValue
  } else if (luminance < 0) {
    luminance := 0
  }

  DllCall("dxva2\SetVCPFeature"
  , "int", handle
  , "char", vcpLuminance
  , "uint", luminance)
  destroyMonitorHandle(handle)
return luminance
}

; Brightness UI
;___________________________________________

BrightnessBar := ""
BrightnessText := ""
show_brightness_bar(brightness, overwriteLabel := "")
{
  ; https://www.autohotkey.com/docs/commands/Progress.htm
  IfWinNotExist, BrightnessWindow
  {
    Gui, bbar:Font, , Verdana
    Gui, bbar:Margin , 20, 20
    Gui, bbar:Add, Progress, w13 x26 h80 Background333333 c46A0A0 Vertical vBrightnessBar, %brightness%
    Gui, bbar:Add, Text, Center xp-4 yp90 cEEEEEE vBrightnessText, 100 ; start with full width
    Gui, bbar:Color, 0C0C0C
    Gui, bbar:-Caption +ToolWindow
    Gui, bbar:Show, % "w65 h140 x50 y60", BrightnessWindow
  }
  GuiControl, bbar:, BrightnessBar, %brightness%
  GuiControl, bbar:, BrightnessText, % (overwriteLabel != "" ? overwriteLabel : brightness)
  SetTimer, hide_brightness_bar, 2000
}

hide_brightness_bar:
  SetTimer, hide_brightness_bar, Off
  Gui, bbar:Destroy
return
