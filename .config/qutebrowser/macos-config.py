# get the python libraries on the file
import os
from urllib.request import urlopen
import catppuccin

# load your autoconfig
config.load_autoconfig()

# basic editing functionality


# media playback
c.content.autoplay = False

# downloads
c.downloads.location.directory = "~/Downloads"

# editor recognised

# Display PDFs within qutebrowser
c.content.pdfjs = True
c.scrolling.bar = 'always'
c.zoom.default = '150%'

config.bind('<Ctrl-=>', 'zoom-in')
config.bind('<Ctrl-->', 'zoom-out')

################################
######## SEARCH ENGINES ######## 
################################

c.url.searchengines = {
    "DEFAULT" : "https://duckduckgo.com/?q={}",
    "annas" : "https://annas-archive.org/search?q={}",
    "aur" : "https://aur.archlinux.org/packages/?O=0&K={}",
    "aw" : "https://wiki.archlinux.org/?search={}",
    "boxd" : "https://letterboxd.com/search/?q={}",
    "ddg" : "https://duckduckgo.com/?q={}",
    "dex" : "https://dexonline.ro/definitie/{}",
    "genius" : "https://genius.com/search?q={}",
    "gh" : "https://github.com/search?q={}",
    "gitlab" : "https://gitlab.com/explore/projects/trending?name={}",
    "olx" : "https://www.olx.ro/oferte/?q={}",
    "reddit" : "https://www.reddit.com/search/?q={}",
    "sch" : "https://scholar.google.com/scholar?hl=ro&as_sdt=0%2C5&q={}",
    "scihub" : "https://sci-hub.st/{}",
    "sep" : "https://plato.stanford.edu/search/searcher.py?query={}",
    "wiki" : "https://en.wikipedia.org/w/index.php?search={}",
}

################################
#### USER INTERFACE OF THE #####
######## BROWSER ITSELF ########
################################

# set the flavor you'd like to use
# valid options are 'mocha', 'macchiato', 'frappe', and 'latte'
# last argument (optional, default is False): enable the plain look for the menu rows
catppuccin.setup(c, 'mocha', True)

# set dark mode
config.set("colors.webpage.darkmode.enabled", True)
config.bind('td', 'config-cycle colors.webpage.darkmode.enabled true false')

################################
#### FONTS

c.fonts.default_family = '"Menlo"'
c.fonts.default_size = '18px'

c.fonts.completion.entry = "18px default_family"
c.fonts.completion.category = "18px default_family"
c.fonts.debug_console = "18px default_family"
c.fonts.downloads = "18px default_family"
c.fonts.hints = "18px default_family"
c.fonts.keyhint = "18px default_family"
c.fonts.messages.info = "18px default_family"
c.fonts.messages.error = "18px default_family"
c.fonts.prompts = "18px default_family"
c.fonts.statusbar = "18px default_family"

# the font size of the tabs
c.fonts.tabs.selected = '18pt default_family'
c.fonts.tabs.unselected = '18pt default_family'

################################
######### KEYBINDINGS ##########
################################

# c.bind('ds', 'spawn --userscript download-papers')

# bindings for the mpv mode
# c.bind('M', 'hint links spawn mpv {hint-url}')
# c.bind('Z', 'hint links spawn wezterm -e youtube-dl {hint-url}')

# going into compact mode
# c.bind('xb', 'config-cycle statusbar.show always never')
# c.bind('xt', 'config-cycle tabs.show always never')
# c.bind('xx', 'config-cycle statusbar.show always never;; config-cycle tabs.show always never')

