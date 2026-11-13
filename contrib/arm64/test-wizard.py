"""Drive the visible English Inno wizard on a GitHub-hosted Windows Arm desktop."""
import ctypes
import re
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

user = ctypes.windll.user32
callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
user.SendMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user.PostMessageW.argtypes = user.SendMessageW.argtypes


def windows(parent=None):
    found = []

    @callback_type
    def collect(hwnd, unused):
        if user.IsWindowVisible(hwnd):
            cls = ctypes.create_unicode_buffer(128)
            title = ctypes.create_unicode_buffer(1024)
            user.GetClassNameW(hwnd, cls, len(cls))
            user.GetWindowTextW(hwnd, title, len(title))
            if cls.value.endswith('Edit'):
                user.SendMessageW(hwnd, 0x000D, len(title), ctypes.addressof(title))
            found.append((hwnd, cls.value, title.value.replace('&', '').strip()))
        return True

    if parent is None:
        user.EnumWindows(collect, 0)
    else:
        user.EnumChildWindows(parent, collect, 0)
    return found


def click(hwnd):
    if not user.IsWindowEnabled(hwnd):
        raise RuntimeError('Wizard button is disabled')
    user.PostMessageW(hwnd, 0x00F5, 0, 0)  # BM_CLICK


setup = Path(sys.argv[1]).resolve()
log = Path('interactive.log').resolve()
process = subprocess.Popen([str(setup), '/NORESTART', '/LOG=' + str(log)])
seen = set()
deadline = time.monotonic() + 150
previous = None
last_clicked = 0
while process.poll() is None and time.monotonic() < deadline:
    time.sleep(.3)
    for hwnd, cls, title in windows():
        if cls == 'TSelectLanguageForm':
            ok = next((h for h, _, t in windows(hwnd) if t == 'OK'), None)
            if ok:
                seen.add('language')
                click(ok)
            continue
        if cls != 'TWizardForm' or 'MPC-BE' not in title:
            continue
        controls = windows(hwnd)
        labels = [t for _, _, t in controls if t]
        signature = tuple((c, t) for _, c, t in controls)
        if signature != previous:
            print('Wizard:', labels, flush=True)
            previous = signature
        if time.monotonic() - last_clicked < .8:
            continue
        for handle, ctrl, label in controls:
            if ctrl.endswith('RadioButton') and re.search(r'I accept', label, re.I):
                seen.add('license')
                if not user.SendMessageW(handle, 0x00F0, 0, 0):
                    click(handle)
                    time.sleep(.3)
            if ctrl.endswith('Edit') and label.lower().endswith(r'\mpc-be'):
                seen.add('destination')
            if ctrl == 'TNewComboBox':
                seen.add('components')
        action = next(((h, t) for h, c, t in controls if c.endswith('Button') and t in ('Next >', 'Next', 'Install', 'Finish') and user.IsWindowEnabled(h)), None)
        if action:
            handle, label = action
            seen.add(label)
            click(handle)
            last_clicked = time.monotonic()

if process.poll() != 0:
    print('Visible windows:', windows(), flush=True)
    if log.exists():
        print(log.read_text(encoding='utf-8-sig', errors='replace')[-6000:])
    raise RuntimeError(f'Interactive setup did not finish successfully ({process.poll()})')
required = {'language', 'license', 'destination', 'components', 'Install', 'Finish'}
if not required.issubset(seen):
    raise RuntimeError(f'Missing wizard interactions: {required - seen}')
print('Verified interactive setup pages and completed installation:', sorted(seen))
