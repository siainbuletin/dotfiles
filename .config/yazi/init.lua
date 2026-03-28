require("git"):setup()

require("yatline-githead"):setup()
require("yatline-symlink"):setup()

require("full-border"):setup({
	-- Available values: ui.Border.PLAIN, ui.Border.ROUNDED
	type = ui.Border.ROUNDED,
})

-- Double status lines for yazi.
