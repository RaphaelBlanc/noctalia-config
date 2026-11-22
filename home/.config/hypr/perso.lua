-- Tes réglages Hyprland personnels : chargés en dernier, jamais remplacés par install.sh ni nc-maj.
-- Format Lua de Hyprland 0.55+ (https://wiki.hypr.land). Enlève « -- » devant une ligne pour l'activer.
--
-- Raccourcis sans éditer de fichier : nc-raccourci (ajouter, changer ou désactiver ceux de la config).
-- Réglages courants (espaces, bordures, pavé tactile, écran…) : nc-reglages.
--
-- hl.bind("SUPER + B", hl.dsp.exec_cmd("firefox"), { description = "Mes raccourcis|Navigateur" })
-- hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1 })
-- hl.config({ general = { gaps_out = 6 }, decoration = { rounding = 10 } })
-- hl.on("hyprland.start", function() hl.exec_cmd("discord --start-minimized") end)

-- Écran de bureau via le dock : conserver le mode 1440p à 60 Hz au rebranchement.
-- Le modèle reste reconnu même si le numéro de la sortie DisplayPort change.
hl.monitor({
    output = "desc:Example Display Bureau 0x00000001",
    mode = "2560x1440@59.95",
    position = "auto-right",
    scale = 1,
})

-- ── Mode Tour Distante (Moonlight) ──────────────────────────────────────────
-- Quand Moonlight est au premier plan (ou avec F12 / Super+Ctrl+Alt+M) :
--   1. Tous les raccourcis Super+... du portable sont ignorés et envoyés directement à la tour
--   2. Les gestes 3/4 doigts du pavé tactile du portable sont coupés pour ne pas changer de bureau local
local mode_tour_actif = false

local function gestes_portable(activer)
    if not nc.reglage("GESTES", true) then return end
    if activer then
        pcall(hl.gesture, { fingers = 3, direction = "horizontal", action = "workspace" })
        pcall(hl.gesture, { fingers = 4, direction = "swipe", action = "move" })
        pcall(hl.gesture, { fingers = 4, direction = "swipe", mods = "ALT", action = "resize" })
        pcall(hl.gesture, { fingers = 4, direction = "pinch", action = "float" })
        pcall(hl.gesture, { fingers = 3, direction = "up", action = function() hl.exec_cmd("qs -c nc-ile ipc call ile vueOuvrir") end })
        pcall(hl.gesture, { fingers = 3, direction = "down", action = function() hl.exec_cmd("qs -c nc-ile ipc call ile vueFermer") end })
    else
        pcall(hl.gesture, { fingers = 3, direction = "horizontal", action = "unset" })
        pcall(hl.gesture, { fingers = 4, direction = "swipe", action = "unset" })
        pcall(hl.gesture, { fingers = 4, direction = "swipe", mods = "ALT", action = "unset" })
        pcall(hl.gesture, { fingers = 4, direction = "pinch", action = "unset" })
        pcall(hl.gesture, { fingers = 3, direction = "up", action = "unset" })
        pcall(hl.gesture, { fingers = 3, direction = "down", action = "unset" })
    end
end

local function basculer_mode_tour(activer, silencieux)
    if activer == mode_tour_actif then return end
    mode_tour_actif = activer
    if activer then
        gestes_portable(false)
        hl.dispatch(hl.dsp.submap("tour-distante"))
        if not silencieux then
            hl.exec_cmd("notify-send -a 'Moonlight' -t 2000 'Mode Tour activé' 'Clavier et pavé tactile dédiés à la tour (Super+Ctrl+Alt+M pour sortir)'")
        end
    else
        hl.dispatch(hl.dsp.submap("reset"))
        gestes_portable(true)
        if not silencieux then
            hl.exec_cmd("notify-send -a 'Moonlight' -t 2000 'Mode Portable rétabli' 'Raccourcis et gestes du portable réactivés'")
        end
    end
end

hl.window_rule({
    name = "nc-moonlight-fullscreen",
    match = { class = "^(.*[Mm]oonlight.*)$" },
    fullscreen = true,
    idle_inhibit = "always",
})

hl.define_submap("tour-distante", function()
    hl.bind("SUPER + CTRL + ALT + M", function() basculer_mode_tour(false, false) end, { ignore_inhibitors = true })
    hl.bind("CTRL + ALT + SHIFT + Q", function()
        basculer_mode_tour(false, true)
        hl.exec_cmd("~/.local/bin/nc-tour couper-stream")
    end, { ignore_inhibitors = true })
    hl.bind("SUPER + CTRL + ALT + Q", function()
        basculer_mode_tour(false, true)
        hl.exec_cmd("~/.local/bin/nc-tour couper-stream")
    end, { ignore_inhibitors = true })
end)

hl.bind("SUPER + CTRL + ALT + M", function() basculer_mode_tour(true, false) end, {
    description = "Système|Basculer le mode Tour Distante (clavier/trackpad dédiés à Moonlight)",
    ignore_inhibitors = true,
})

local function est_moonlight(w)
    if not w then return false end
    local c = (w.class or ""):lower()
    local t = (w.title or ""):lower()
    return c:find("moonlight", 1, true) ~= nil or t:find("moonlight", 1, true) ~= nil
end

hl.on("window.active", function(w)
    if est_moonlight(w) then
        basculer_mode_tour(true, true)
    elseif mode_tour_actif then
        basculer_mode_tour(false, true)
    end
end)

hl.on("window.close", function(w)
    if mode_tour_actif and est_moonlight(w) then
        basculer_mode_tour(false, true)
    end
end)
