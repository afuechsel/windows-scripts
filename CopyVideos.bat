@echo off
set quelle="D:\afuec\Pictures\iCloud Photos\Photos"
set ziel="D:\afuec\Videos"
set startJahr=2022
set startMonat=10
for %%i in (%quelle%\*.mov) do @for /f "tokens=1-3 delims=. " %%a in ("%%~ti") do (
	if %%c geq %startJahr% (
		if %%b geq %startMonat% (
			if not exist %ziel%\%%c md %ziel%\%%c
			if not exist %ziel%\%%c\%%c-%%b md %ziel%\%%c\%%c-%%b
			echo move "%%~fi" %ziel%\%%c\%%c-%%b
			echo n | copy /-y "%%~fi" %ziel%\%%c\%%c-%%b
			del "%%~fi"
		)	
	)
)
for %%i in (%quelle%\*.mp4) do @for /f "tokens=1-3 delims=. " %%a in ("%%~ti") do (
	if %%c geq %startJahr% (
		if %%b geq %startMonat% (
			if not exist %ziel%\%%c md %ziel%\%%c
			if not exist %ziel%\%%c\%%c-%%b md %ziel%\%%c\%%c-%%b
			echo move "%%~fi" %ziel%\%%c\%%c-%%b
			echo n | copy /-y "%%~fi" %ziel%\%%c\%%c-%%b
			del "%%~fi"
		)
	)
)