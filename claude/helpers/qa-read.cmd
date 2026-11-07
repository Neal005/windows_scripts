@echo off
set "HERE=%~dp0"
set "PY=%HERE%.venv\Scripts\python.exe"

if not exist "%PY%" (
    echo qa-read: helpers venv not found at %PY% >&2
    exit /b 2
)

set "KIND=%~1"

if "%KIND%"=="docx" (
    "%PY%" "%HERE%docx_dump.py" %2 %3 %4 %5 %6 %7 %8 %9
) else if "%KIND%"=="pdf" (
    "%PY%" "%HERE%pdf_dump.py" %2 %3 %4 %5 %6 %7 %8 %9
) else (
    echo usage: qa-read docx^|pdf ^<file^> ^<mode^> [args] >&2
    exit /b 2
)
