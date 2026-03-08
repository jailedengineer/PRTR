local drawer = require("drawer")

local prtr = {
"  ____   _____ _____  ____  ____            ",
" |  _ \\ / ____|  __ \\|  _ \\|  _ \\           ",
" | |_) | (___ | |  | | |_) | |_) |          ",
" |  _ < \\___ \\| |  | |    /|  __/           ",
" | |_) |____) | |__| | |\\ \\| |              ",
" |     |      |      | | | | |              ",
" |____/|_____/|_____/|_| |_|_| PRTR_VERSION"
}

drawer.addBrand("prtr", {
        graphic = prtr,
})

return true
