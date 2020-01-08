@echo off

REM Open VcxSrv if it isn't running

tasklist /FI "IMAGENAME eq vcxsrv.exe" 2>NUL | find /I /N "vcxsrv.exe">NUL
if "%ERRORLEVEL%"=="1" (
  cd /d "C:\Program Files\VcXsrv\"
  start vcxsrv.exe :0 -ac -terminate -lesspointer -multiwindow -clipboard -wgl
  timeout 2 > NUL
)

REM Open IntelliJ from shortcut using proper DISPLAY ip

bash ~ -c "DISPLAY=\"$(grep -oP \"(?<=nameserver ).+\" /etc/resolv.conf):0.0\" $HOME/bin/idea"
