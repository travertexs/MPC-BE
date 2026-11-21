"""Check the renderer names and availability in the installed player's Video options."""
import ctypes
from ctypes import wintypes
from pathlib import Path
import subprocess
import sys
import time

ui = ctypes.windll.user32
visit = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
ui.SendMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
player = Path(sys.argv[1])
ini = player.with_suffix('.ini')
prior = ini.read_bytes() if ini.exists() else None
ini.write_text('[Dialogs\\Options]\nLastUsedPage=10114\n[Settings]\nLanguage=en\n', encoding='utf-16')
proc = subprocess.Popen([str(player), '/new'])

def windows(parent=None):
    handles = []
    @visit
    def collect(hwnd, unused):
        pid = wintypes.DWORD()
        ui.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == proc.pid and ui.IsWindowVisible(hwnd):
            handles.append(hwnd)
        return True
    if parent:
        ui.EnumChildWindows(parent,collect,0)
    else:
        ui.EnumWindows(collect,0)
    return handles

try:
    until = time.monotonic() + 45
    opened = False
    while time.monotonic() < until:
        time.sleep(.4)
        for window in windows():
            cls = ctypes.create_unicode_buffer(128)
            ui.GetClassNameW(window,cls,len(cls))
            if not opened and cls.value == 'MPC-BE':
                ui.PostMessageW(window,0x111,815,0)
                opened = True
            for hwnd in windows(window):
                if ui.GetDlgCtrlID(hwnd) != 10753:
                    continue
                options = {}
                for i in range(ui.SendMessageW(hwnd,0x146,0,0)):  # CB_GETCOUNT
                    buf = ctypes.create_unicode_buffer(ui.SendMessageW(hwnd,0x149,i,0)+1)
                    ui.SendMessageW(hwnd,0x148,i,ctypes.addressof(buf))
                    options[ui.SendMessageW(hwnd,0x150,i,0)] = buf.value
                print('Renderer options:',options,flush=True)
                if options.get(5) != 'MPC Video Renderer':
                    raise RuntimeError('MPC Video Renderer unavailable in Video options')
                if any(i not in options for i in (2,3,4,6,7,8,10,11)):
                    raise RuntimeError('Missing upstream renderer entry')
                sys.exit(0)
    raise RuntimeError('Could not open the Video options page')
finally:
    proc.kill()
    proc.wait()
    if prior is None:
        ini.unlink(missing_ok=True)
    else:
        ini.write_bytes(prior)
