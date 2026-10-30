# dmgbuild layout for Screenshotty.dmg (used by scripts/make-dmg.sh). dmgbuild writes the Finder
# window layout directly, so it works headless in CI without scripting Finder.
import os

app = defines["app"]
background = defines["background"]

files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {os.path.basename(app): (170, 160), "Applications": (490, 160)}

format = "UDZO"
filesystem = "HFS+"
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 13
