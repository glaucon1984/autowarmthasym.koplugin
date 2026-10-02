local _ = require("gettext")
return {
    name = "autowarmthasym",
    fullname = _("Auto warmth: separate sunrise and sunset values"),
    version = "1.0.0",
    description = _([[Lets the Auto warmth plugin use a different warmth and night mode value for every sun event, e.g. cold at sunrise and warm at sunset. Requires the Auto warmth plugin.]]),
}
