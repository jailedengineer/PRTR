local drawer = require("drawer")

local prtr = {
"  ____  ____  _______ ____               ",
" |  _ \\|  _ \\|__   __|  _ \\              ",
" | |_) | |_) |  | |  | |_) |             ",
" |  __/|    /   | |  |    /              ",
" | |   | |\\ \\   | |  | |\\ \\              ",
" | |   | | | |  | |  | | | | NLINK       ",
" |_|   |_| |_|  |_|  |_| |_| PRTR_VERSION"
}

drawer.addBrand("prtr", {
        graphic = prtr,
})

return true
