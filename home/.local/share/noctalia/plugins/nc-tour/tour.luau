--!nonstrict
-- nc/tour : la pilule Tour de la barre, à côté de la pilule VPN.
--   Contenu : écran MAISON (dessiné en SVG) ;
--     - en stream : écran plein bleu + « Stream »
--     - en ligne  : écran plein vert + « XX ms »
--     - éteinte   : écran contour gris (comme le bouclier VPN déconnecté), toujours cliquable pour ouvrir la fenêtre et réveiller la tour (WoL).
--   Clic : la fenêtre Tour de l'île (qs -c nc-ile ipc call ile tour).
--   État poussé par l'île : $XDG_RUNTIME_DIR/nc-tour-barre.json {en_ligne, en_stream, ping_ms, masque_partage}.

local function env(nom)
  local v = noctalia.getenv and noctalia.getenv(nom)
  return (v and v ~= "") and v or nil
end
local RUN = env("XDG_RUNTIME_DIR") or "/tmp"
local ETAT = RUN .. "/nc-tour-barre.json"
local ETEINT = RUN .. "/nc-ecran-eteint"
local VERT, BLEU, GRIS = "#30d158", "#0a84ff", "#98989d"
local INTERVALLE = 3000

local etat = { en_ligne = false, en_stream = false, ping_ms = -1, masque_partage = false }
local signature = ""
local visible = nil
local dernierRendu = nil
local dossier = nil

local function montrer(v)
  if v ~= visible then visible = v; barWidget.setVisible(v) end
end

local function iconeEcran(mode)
  if not dossier then
    dossier = (noctalia.pluginDataDir and noctalia.pluginDataDir() or (RUN .. "/nc-tour-plugin")) .. "/ecran-v1"
    noctalia.mkdirAll(dossier)
  end
  local f = dossier .. "/" .. mode .. ".svg"
  if not noctalia.fileExists(f) then
    local corps
    if mode == "stream" then
      corps = '<rect x="2.5" y="3.5" width="19" height="13" rx="2.4" fill="' .. BLEU .. '"/>'
        .. '<path fill="#000000" fill-opacity=".6" d="M10 7.3v5.4l4.6-2.7L10 7.3Z"/>'
        .. '<path stroke="' .. BLEU .. '" stroke-width="2.2" stroke-linecap="round" d="M8.5 20h7M12 16.5V20"/>'
    elseif mode == "enligne" then
      corps = '<rect x="2.5" y="3.5" width="19" height="13" rx="2.4" fill="' .. VERT .. '"/>'
        .. '<path fill="none" stroke="#000000" stroke-opacity=".55" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M8.8 10.2l2.2 2.2 4.2-4.4"/>'
        .. '<path stroke="' .. VERT .. '" stroke-width="2.2" stroke-linecap="round" d="M8.5 20h7M12 16.5V20"/>'
    else
      corps = '<rect x="2.5" y="3.5" width="19" height="13" rx="2.4" fill="none" stroke="' .. GRIS .. '" stroke-width="2.1"/>'
        .. '<path stroke="' .. GRIS .. '" stroke-width="2.1" stroke-linecap="round" d="M8.5 20h7M12 16.5V20"/>'
    end
    noctalia.writeFile(f, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">' .. corps .. "</svg>")
  end
  return f
end

local function texte(e)
  if not e then return "" end
  if e.masque_partage == true then return (e.en_ligne or e.en_stream) and "Tour" or "" end
  if e.en_stream == true then return "Stream" end
  if e.en_ligne == true then
    if type(e.ping_ms) == "number" and e.ping_ms > 0 then
      return tostring(e.ping_ms) .. " ms"
    end
    return "Tour"
  end
  return ""
end

function rendre()
  local e = etat or { en_ligne = false, en_stream = false, ping_ms = -1 }
  local mode = e.en_stream == true and "stream" or (e.en_ligne == true and "enligne" or "eteint")
  local t = texte(e)
  local sig = mode .. "|" .. t
  montrer(true)
  if sig == dernierRendu then return end
  dernierRendu = sig
  local enfants = { ui.image({ key = "ecran:" .. mode, path = iconeEcran(mode), width = 17, height = 17, fit = "contain" }) }
  if t ~= "" then
    table.insert(enfants, ui.label({ text = t, maxLines = 1, fontWeight = "semibold", color = "on_surface" }))
  end
  barWidget.render(ui.row({ gap = 6, align = "center" }, enfants))
  local tip = mode == "stream" and "Tour Exemple · En stream" or (mode == "enligne" and ("Tour Exemple · " .. (t ~= "" and t or "En ligne")) or "Tour Exemple · Éteinte (cliquer pour ouvrir)")
  barWidget.setTooltip(tip)
end

local function lire()
  local info = noctalia.fileInfo(ETAT)
  if not info then
    etat = { en_ligne = false, en_stream = false, ping_ms = -1 }
    rendre()
    return
  end
  local sig = tostring(info.size) .. ":" .. tostring(info.mtime)
  if sig == signature then return end
  signature = sig
  local brut = noctalia.readFile(ETAT)
  local d = brut and noctalia.json.decode(brut) or nil
  if type(d) == "table" then etat = d else etat = { en_ligne = false, en_stream = false, ping_ms = -1 } end
  rendre()
end

function update()
  if noctalia.fileExists(ETEINT) then return end
  lire()
end

function onClick()
  if not visible then return end
  noctalia.runAsync({ "qs", "-c", "nc-ile", "ipc", "call", "ile", "tour" }, function() end, 3000)
end

noctalia.setUpdateInterval(INTERVALLE)
rendre()
lire()
