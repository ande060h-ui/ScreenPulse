# Layout of the installer window, read by dmgbuild (see scripts/make-dmg.sh).
# Run with: dmgbuild -s app/dmg/settings.py -D app=build/ScreenPulse.app -D bg=build/dmg/background.png -D icon=… "ScreenPulse" out.dmg
import os

app = defines.get("app", "build/ScreenPulse.app")  # noqa: F821  (`defines` is provided by dmgbuild)
app_name = os.path.basename(app)

files = [app]
symlinks = {"Applications": "/Applications"}

format = "UDZO"
filesystem = "HFS+"
size = None

background = defines.get("bg")  # noqa: F821
badge_icon = None
icon = defines.get("icon")  # noqa: F821  (volume icon)

window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {app_name: (180, 190), "Applications": (480, 190)}
