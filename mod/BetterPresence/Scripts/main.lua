--[[
    GTA SA DE Better Presence — mod UE4SS (Lua)

    Lit l'état du jeu via la réflexion Unreal et l'écrit toutes les secondes dans
        %LOCALAPPDATA%\GTASADEBetterPresence\state.json
    Le client Python (client/presence.py) lit ce fichier et met à jour Discord.

    Sources (découvertes via le dump d'objets UE4SS, validées en jeu sur la 1.0.112) :
      - BP_SanAndreasInterface_C (Gameterface)
          IsPlayingGame()            → en jeu / menu principal
          GetGTAPlayerPosition()     → position (cm Unreal ; SA_x = x/100, SA_y = -y/100)
          GetAppropriateGamepadTab() → 0 à pied, 1 en véhicule
          CurrentMenu                → menu pause ouvert
          CurrentHudDrawer / CurrentPriorityHudDrawer → drawers HUD
      - UI_HUDItem_PlayerInfo_SA_C : Star1..Star6 (Brush.TintColor clair = étoile active,
        WantedStarsBox caché = 0 étoile), MoneyText, TimeText
      - Titres HUD (enfants de MainCanvas des drawers, présents seulement à l'affichage) :
          UI_HUDItem_TitleText_Area_C (quartier), _Vehicle_C (nom du véhicule),
          _Mission_C (titre de mission), _MissionFailed_C, _SA_C (Mission passed…),
          _Radio_SA_C (station), UI_HUDItem_Wasted_SA_C / Busted_SA_C

    À NE PAS FAIRE (plantent le jeu avec UE4SS 3.0.1) :
      - Gameterface:GetMapAreaName(...)            → crash dans UE4SS
      - appeler une méthode sur un UObject sans IsValid() (pointeur nul → crash, pcall inutile)

    Fichiers de contrôle (même dossier que state.json) :
      - flags.txt     : "clé=0|1" par ligne, relu toutes les 2 s → active/désactive chaque source
      - dump.request  : fichier vide → génère dump_objects.txt et dump_widgets.txt
]]

local MOD_TAG   = "[BetterPresence]"
local VERSION   = "0.5.3"
local SCHEMA    = 1
local POLL_MS   = 1000

-- ---------------------------------------------------------------------------
-- Utilitaires
-- ---------------------------------------------------------------------------
local function log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(MOD_TAG .. " " .. (ok and msg or tostring(fmt)) .. "\n")
end

local function dirname()
    local base = os.getenv("LOCALAPPDATA")
    if not base or base == "" then
        base = (os.getenv("USERPROFILE") or "C:") .. "\\AppData\\Local"
    end
    return base .. "\\GTASADEBetterPresence"
end

local STATE_DIR    = dirname()
local STATE_PATH   = STATE_DIR .. "\\state.json"
local STATE_TMP    = STATE_DIR .. "\\state.json.tmp"
local FLAGS_PATH   = STATE_DIR .. "\\flags.txt"
local DUMP_REQUEST = STATE_DIR .. "\\dump.request"
local DUMP_OBJECTS = STATE_DIR .. "\\dump_objects.txt"
local DUMP_WIDGETS = STATE_DIR .. "\\dump_widgets.txt"

local function fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

-- Encodeur JSON minimal : scalaires, objets (tables à clés) et tableaux.
local function jsonEscape(s)
    s = s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. s .. '"'
end

local jsonValue
local function jsonTable(tbl)
    local n = #tbl
    if n > 0 then
        local parts = {}
        for i = 1, n do parts[i] = jsonValue(tbl[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = jsonEscape(k) .. ":" .. jsonValue(tbl[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

jsonValue = function(v)
    local t = type(v)
    if t == "string" then return jsonEscape(v)
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if math.type(v) == "integer" then return tostring(v) end
        return string.format("%.3f", v)
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "table" then return jsonTable(v)
    else return "null" end
end

-- Écriture atomique : tmp puis rename (os.rename échoue sur Windows si la
-- cible existe, d'où le os.remove avant).
local function writeFileAtomic(path, tmp, content)
    local f, err = io.open(tmp, "wb")
    if not f then return false, err end
    f:write(content)
    f:close()
    os.remove(path)
    local ok, rerr = os.rename(tmp, path)
    if not ok then return false, rerr end
    return true
end

-- Accès défensif : la réflexion lève une erreur Lua si l'objet est invalide.
local function try(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil, res
end

-- IsValid() gère les pointeurs nuls ; toute autre méthode sur un objet nul PLANTE le jeu.
local function isValid(obj)
    return obj ~= nil and try(function() return obj:IsValid() end) == true
end

local function safeFullName(obj)
    if not isValid(obj) then return "<invalid>" end
    return try(function() return obj:GetFullName() end) or "<?>"
end

local function safeClassName(obj)
    if not isValid(obj) then return "<invalid>" end
    return try(function() return obj:GetClass():GetFName():ToString() end) or "<?>"
end

local function textToString(txt)
    if txt == nil then return nil end
    local s = try(function() return txt:ToString() end)
    if s == nil or s == "" then return nil end
    return s
end

local function isCDO(obj)
    return safeFullName(obj):find("Default__", 1, true) ~= nil
end

local function trim(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Toutes les instances vivantes (hors CDO) d'une classe. Coûteux (parcourt
-- GUObjectArray) : réservé aux objets persistants, mis en cache ensuite.
local function findLiveInstances(className)
    local all = try(function() return FindAllOf(className) end)
    local out = {}
    if type(all) ~= "table" then return out end
    for _, obj in ipairs(all) do
        if isValid(obj) and not isCDO(obj) then out[#out + 1] = obj end
    end
    return out
end

local function findLiveInstance(className)
    return findLiveInstances(className)[1]
end

-- Visibilité Slate : 0 Visible, 1 Collapsed, 2 Hidden, 3 HitTestInvisible, 4 SelfHitTestInvisible
local function isShown(vis)
    return vis == 0 or vis == 3 or vis == 4
end

-- Déballe un élément de tableau UE4SS : UObject direct, ou RemoteUnrealParam avec :get().
local function unwrap(e)
    if e == nil then return nil end
    if try(function() return e:IsValid() end) ~= nil then return e end
    local g = try(function() return e:get() end)
    if g ~= nil then return g end
    return e
end

-- Convertit un TArray UE4SS (userdata ou table de wrappers) en table Lua d'objets.
local function arrayToTable(arr)
    local out = {}
    if arr == nil then return out end
    if type(arr) == "table" then
        for _, e in ipairs(arr) do
            local u = unwrap(e)
            if u ~= nil then out[#out + 1] = u end
        end
        return out
    end
    local n = try(function() return arr:GetArrayNum() end)
    if type(n) == "number" then
        for i = 1, n do
            local u = unwrap(try(function() return arr[i] end))
            if u ~= nil then out[#out + 1] = u end
        end
        return out
    end
    try(function()
        arr:ForEach(function(_, elem)
            local u = unwrap(elem)
            if u ~= nil then out[#out + 1] = u end
        end)
    end)
    return out
end

-- Suffixe numérique du nom d'objet (les objets récents ont un suffixe plus petit).
local function nameSuffix(obj)
    local n = safeFullName(obj):match("_(%d+)$")
    return n and tonumber(n) or 0
end

-- ---------------------------------------------------------------------------
-- Drapeaux de fonctionnalités (flags.txt, rechargé à chaud)
-- ---------------------------------------------------------------------------
local flags = {
    position    = true,   -- GetGTAPlayerPosition
    gamepad     = true,   -- GetAppropriateGamepadTab (0 à pied, 1 en véhicule)
    playerinfo  = true,   -- widgets étoiles / argent / heure
    titles      = true,   -- titres HUD (zone, véhicule, mission) via les drawers
    titles_scan = false,  -- forcer le repli FindAllOf (coûteux, ~80 ms/tick)
    menu        = true,   -- Gameterface.CurrentMenu (pause)
    camera      = false,  -- distance caméra-joueur + vitesse (diagnostic)
    misc        = false,  -- GetTimeOfDay, GetRadioStationOffset (diagnostic)
    area        = false,  -- GetMapAreaName(table UE) — PLANTE LE JEU, tests uniquement
    area_ud     = false,  -- variante : struct FVector de GetGTAPlayerPosition
    area_sa     = false,  -- variante : coordonnées SA (x/100, -y/100, z/100)
    debug       = false,  -- détails bruts dans state.json (titres, étoiles, drawers…)
    stars_tree  = false,  -- diagnostic : arbre complet de WantedStarsBox
    timing      = false,  -- mesure du coût des lectures HUD
}

local function loadFlags()
    local content = readFile(FLAGS_PATH)
    if not content then return end
    local changed = {}
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*([01])%s*$")
        if k and flags[k] ~= nil then
            local nv = (v == "1")
            if flags[k] ~= nv then
                flags[k] = nv
                changed[#changed + 1] = k .. "=" .. v
            end
        end
    end
    if #changed > 0 then log("flags modifiés : %s", table.concat(changed, " ")) end
end

-- ---------------------------------------------------------------------------
-- Accès aux objets du jeu (avec cache et revalidation)
-- ---------------------------------------------------------------------------
local cache = { gameterface = nil, playerInfo = nil, playerController = nil, drawers = nil }

local function getGameterface()
    if isValid(cache.gameterface) then return cache.gameterface end
    cache.gameterface = findLiveInstance("BP_SanAndreasInterface_C")
        or findLiveInstance("SanAndreasInterface")
        or findLiveInstance("Gameterface")
    if cache.gameterface then
        log("Gameterface trouvé : %s", safeFullName(cache.gameterface))
    end
    return cache.gameterface
end

local function getPlayerInfoWidget()
    if isValid(cache.playerInfo) then return cache.playerInfo end
    cache.playerInfo = findLiveInstance("UI_HUDItem_PlayerInfo_SA_C")
    if cache.playerInfo then
        log("Widget PlayerInfo trouvé : %s", safeFullName(cache.playerInfo))
    end
    return cache.playerInfo
end

local function getPlayerController()
    if isValid(cache.playerController) then return cache.playerController end
    cache.playerController = findLiveInstance("GTAPlayerController") or findLiveInstance("PlayerController")
    if cache.playerController then
        log("PlayerController trouvé : %s", safeFullName(cache.playerController))
    end
    return cache.playerController
end

-- Les deux drawers HUD (normal + prioritaire), via le Gameterface.
local function getDrawers(gi)
    if cache.drawers and #cache.drawers > 0 then
        local ok = true
        for _, d in ipairs(cache.drawers) do if not isValid(d) then ok = false end end
        if ok then return cache.drawers end
    end
    local list = {}
    for _, prop in ipairs({ "CurrentHudDrawer", "CurrentPriorityHudDrawer" }) do
        local d = try(function() return gi[prop] end)
        if isValid(d) then list[#list + 1] = d end
    end
    if #list == 0 then
        for _, cls in ipairs({ "HUDDrawer_SA_C", "PriorityHUDDrawer_SA_C" }) do
            local d = findLiveInstance(cls)
            if d then list[#list + 1] = d end
        end
    end
    for _, d in ipairs(list) do log("HUD drawer : %s", safeFullName(d)) end
    cache.drawers = list
    return list
end

-- ---------------------------------------------------------------------------
-- Titres HUD (zone, véhicule, mission, …)
-- ---------------------------------------------------------------------------
local TITLE_CLASSES = {
    { class = "UI_HUDItem_TitleText_Area_C",          kind = "area" },
    { class = "UI_HUDItem_TitleText_Vehicle_C",       kind = "vehicle" },
    { class = "UI_HUDItem_TitleText_Mission_C",       kind = "mission" },
    { class = "UI_HUDItem_TitleText_MissionFailed_C", kind = "failed" },
    { class = "UI_HUDItem_TitleText_SA_C",            kind = "big" },
    { class = "UI_HUDItem_TitleText_Radio_SA_C",      kind = "radio" },
    { class = "UI_HUDItem_Mission_SA_C",              kind = "missionbox" },
}
local KIND_BY_CLASS = {}
for _, t in ipairs(TITLE_CLASSES) do KIND_BY_CLASS[t.class] = t.kind end
KIND_BY_CLASS["UI_HUDItem_Wasted_SA_C"] = "wasted"
KIND_BY_CLASS["UI_HUDItem_Busted_SA_C"] = "busted"

local PANEL_CLASSES = {
    CanvasPanel = true, Overlay = true, VerticalBox = true, HorizontalBox = true,
    ScaleBox = true, SizeBox = true, Border = true, WidgetSwitcher = true, GridPanel = true,
    UniformGridPanel = true, WrapBox = true, ScrollBox = true, BackgroundBlur = true,
}
local seenHudClasses = {} -- classes d'items HUD non classées déjà journalisées

-- Dernier texte vu par famille + horodatages (dernier changement, dernière fois visible).
local hud = {}
for _, t in ipairs(TITLE_CLASSES) do
    hud[t.kind] = { text = nil, changed_at = 0, seen_at = 0, visible = false }
end

-- Mission courante (heuristique : posée au titre de mission, effacée sur
-- échec / réussite / wasted / busted).
local currentMission = nil

-- Mots-clés de fin de mission (jeu en français ou en anglais).
local PASSED_WORDS = { "pass", "réussi", "reussi", "accompli", "complet", "termin" }
local FAILED_WORDS = { "fail", "échou", "echou", "raté", "rate", "interromp", "annul", "abandon", "cancel" }

local function containsAny(t, words)
    for _, w in ipairs(words) do
        if t:find(w, 1, true) then return true end
    end
    return false
end

local function looksLikeMissionPassed(text)
    local t = text:lower()
    return t:find("mission", 1, true) ~= nil and containsAny(t, PASSED_WORDS)
end

local function looksLikeMissionFailed(text)
    local t = text:lower()
    return t:find("mission", 1, true) ~= nil and containsAny(t, FAILED_WORDS)
end

-- Le widget "titre de mission" sert aussi à des messages système (achat de
-- propriété, etc.). On écarte ceux-là : liste d'exclusion + typographie des
-- messages localisés (espace avant ! ? : ; ou point final), absente des noms de missions.
local NOT_A_MISSION = {
    "propri", "property", "planque", "safehouse", "sauvegard", "saved", "point de passage",
    "checkpoint", "achet", "acquired", "purchased", "bienvenue", "welcome",
}

local function isMissionName(text)
    local t = text:lower()
    if containsAny(t, NOT_A_MISSION) then return false end
    if looksLikeMissionPassed(text) or looksLikeMissionFailed(text) then return false end
    if text:find(" [!?:;]") then return false end
    -- Point final = phrase système ("Checkpoint saved."), sauf points de
    -- suspension ("Farewell, My Love...") et acronymes ("N.O.E.").
    if text:find("%.$") and not text:find("%.%.%.$") and not text:find("%u%.$") then return false end
    return true
end

local function onTitle(kind, text)
    local now = os.time()
    local h = hud[kind]
    if h.text ~= text then
        h.text = text
        h.changed_at = now
        log("HUD %s : %s", kind, text)
        if kind == "mission" then
            if isMissionName(text) then
                currentMission = text
            else
                log("Titre ignoré (pas un nom de mission) : %s", text)
            end
        elseif kind == "failed" then
            currentMission = nil
        elseif kind == "big" or kind == "missionbox" then
            if looksLikeMissionPassed(text) or looksLikeMissionFailed(text) then
                currentMission = nil
            end
        end
    end
    h.seen_at = now
end

local TEXT_CLASSES = { TextBlock = true, RichTextBlock = true, GTAScalableRichTextBlock = true, MultiLineEditableText = true }

-- Premier texte non vide trouvé dans un widget et ses descendants (panels et
-- sous-UserWidgets via leur WidgetTree). Profondeur limitée.
local function readAnyText(widget, depth)
    if depth > 6 or not isValid(widget) then return nil end
    local cls = safeClassName(widget)
    if TEXT_CLASSES[cls] then
        return textToString(try(function() return widget:GetText() end))
    end
    local children = {}
    if PANEL_CLASSES[cls] then
        children = arrayToTable(try(function() return widget:GetAllChildren() end))
    else
        local root = try(function() return widget.WidgetTree.RootWidget end)
        if isValid(root) then children = { root } end
        local content = try(function() return widget:GetContent() end) -- ContentWidget (Border, SizeBox…)
        if isValid(content) then children[#children + 1] = content end
    end
    for _, c in ipairs(children) do
        local vis = try(function() return c:GetVisibility() end)
        if vis == nil or vis ~= 1 then -- on ignore les sous-arbres Collapsed
            local text = readAnyText(c, depth + 1)
            if text and trim(text) ~= "" then return text end
        end
    end
    return nil
end

-- Texte d'un item titre : propriété RichText (UI_HUDItem_TitleText_C), fonction
-- GetRichText (UI_HUDItem_Mission_SA_C), sinon recherche récursive.
local function readTitleText(widget)
    local rich = try(function() return widget.RichText end)
    if not isValid(rich) then
        rich = try(function() return widget:GetRichText() end)
    end
    if isValid(rich) then
        local text = textToString(try(function() return rich:GetText() end))
        if text and trim(text) ~= "" then return text end
    end
    return readAnyText(widget, 0)
end

-- Parcours récursif des enfants d'un panel (profondeur limitée).
local function collectPanelChildren(panel, items, diag, depth)
    if depth > 3 or not isValid(panel) then return end
    local children = arrayToTable(try(function() return panel:GetAllChildren() end))
    if #children == 0 then
        local n = try(function() return panel:GetChildrenCount() end)
        if type(n) == "number" then
            for i = 0, n - 1 do
                local w = try(function() return panel:GetChildAt(i) end)
                if w ~= nil then children[#children + 1] = w end
            end
        end
    end
    for _, w in ipairs(children) do
        if isValid(w) then
            local cls = safeClassName(w)
            if diag then diag.classes[#diag.classes + 1] = string.rep(" ", depth) .. cls end
            local kind = KIND_BY_CLASS[cls]
            if kind then
                items[#items + 1] = { widget = w, kind = kind }
            elseif PANEL_CLASSES[cls] then
                collectPanelChildren(w, items, diag, depth + 1)
            elseif not seenHudClasses[cls] then
                -- Item HUD que l'on ne classe pas encore : journalisé une fois (diagnostic).
                seenHudClasses[cls] = true
                local vis = try(function() return w:GetVisibility() end)
                log("Item HUD non classé : %s (vis=%s) texte=%s", cls, tostring(vis), tostring(readAnyText(w, 0)))
            end
        end
    end
end

-- Énumère les items HUD (widgets enfants des drawers). Renvoie une liste de
-- { widget=, kind= } dans l'ordre d'ajout (le dernier est le plus récent).
local function enumerateHudItems(gi, dbg)
    local items = {}
    if not flags.titles_scan then
        local drawers = getDrawers(gi)
        for _, drawer in ipairs(drawers) do
            local canvas = try(function() return drawer.MainCanvas end)
            local diag = dbg and { drawer = safeClassName(drawer), classes = {} } or nil
            collectPanelChildren(canvas, items, diag, 0)
            if dbg then dbg.drawers = dbg.drawers or {}; dbg.drawers[#dbg.drawers + 1] = diag end
        end
        if dbg then dbg.hud_source = "drawers" end
        if #drawers > 0 then return items end
    end
    -- Repli : scan complet (coûteux)
    for cls, kind in pairs(KIND_BY_CLASS) do
        for _, w in ipairs(findLiveInstances(cls)) do
            items[#items + 1] = { widget = w, kind = kind }
        end
    end
    if dbg then dbg.hud_source = "scan" end
    return items
end

local function pollTitles(gi, dbg)
    local t0 = flags.timing and os.clock() or nil
    for _, h in pairs(hud) do h.visible = false end
    local deathVisible = nil

    -- Par famille : on retient le widget visible le plus récent (opacité la plus
    -- forte, puis dernier créé) pour éviter l'alternance ancien/nouveau titre.
    local best = {}
    local missionBoxShown = false
    for _, it in ipairs(enumerateHudItems(gi, dbg)) do
        local w, kind = it.widget, it.kind
        local vis = try(function() return w:GetVisibility() end)
        if kind == "wasted" or kind == "busted" then
            if isShown(vis) then deathVisible = kind end
        else
            if kind == "missionbox" and isShown(vis) then missionBoxShown = true end
            local text = readTitleText(w)
            if text then text = trim(text) end
            local opacity = try(function() return w:GetRenderOpacity() end) or 1
            local id = nameSuffix(w)
            if dbg then
                dbg.titles = dbg.titles or {}
                dbg.titles[#dbg.titles + 1] = { kind = kind, vis = vis, text = text, opacity = opacity, id = id }
            end
            if isShown(vis) and text and text ~= "" then
                local cur = best[kind]
                if not cur or opacity > cur.opacity + 0.05
                   or (math.abs(opacity - cur.opacity) <= 0.05 and id < cur.id) then
                    best[kind] = { text = text, opacity = opacity, id = id }
                end
            end
        end
    end
    for kind, b in pairs(best) do
        hud[kind].visible = true
        onTitle(kind, b.text)
    end
    -- L'écran de fin de mission (UI_HUDItem_Mission_SA_C) vaut fin de mission,
    -- même si son texte n'est pas lisible.
    if missionBoxShown and currentMission then
        log("Écran de mission affiché → fin de mission (%s)", currentMission)
        currentMission = nil
    end
    if deathVisible then
        if currentMission then log("%s visible → fin de mission", deathVisible) end
        currentMission = nil
        if dbg then dbg.death_screen = deathVisible end
    end
    if t0 and dbg then dbg.titles_ms = math.floor((os.clock() - t0) * 1000) end
    return deathVisible
end

-- ---------------------------------------------------------------------------
-- HUD PlayerInfo (étoiles, argent, heure)
-- ---------------------------------------------------------------------------
local STAR_LIT_THRESHOLD = 0.10 -- composante R de Brush.TintColor : ~0.27 allumée, ~0.02 éteinte

local function readStarWidget(star)
    if not isValid(star) then return nil end
    local info = {}
    info.vis = try(function() return star:GetVisibility() end)
    info.tint_r = try(function()
        local r = star.Brush.TintColor.SpecifiedColor.R
        if type(r) ~= "number" then return nil end
        return r
    end)
    return info
end

local function readPlayerInfo()
    local w = getPlayerInfoWidget()
    if not w then return nil end
    local out = { stars = {} }
    for i = 1, 6 do
        local star = try(function() return w["Star" .. i] end)
        out.stars[i] = readStarWidget(star) or {}
    end
    local box = try(function() return w.WantedStarsBox end)
    out.box_vis = isValid(box) and try(function() return box:GetVisibility() end) or nil
    local money = try(function() return w.MoneyText end)
    out.money = isValid(money) and textToString(try(function() return money:GetText() end)) or nil
    local timeText = try(function() return w.TimeText end)
    out.time = isValid(timeText) and textToString(try(function() return timeText:GetText() end)) or nil

    -- Diagnostic : arbre complet de la boîte d'étoiles
    if flags.stars_tree and isValid(box) then
        out.tree = {}
        local function walk(panel, depth)
            if depth > 4 then return end
            for _, c in ipairs(arrayToTable(try(function() return panel:GetAllChildren() end))) do
                if isValid(c) then
                    local e = { d = depth, cls = safeClassName(c), name = safeFullName(c):match("([^%.:]+)$"),
                        vis = try(function() return c:GetVisibility() end),
                        op = try(function() return c:GetRenderOpacity() end) }
                    if e.cls == "Image" then
                        e.tint = try(function()
                            local tc = c.Brush.TintColor.SpecifiedColor
                            if type(tc.R) ~= "number" then return nil end
                            return string.format("%.2f,%.2f,%.2f,%.2f", tc.R, tc.G, tc.B, tc.A)
                        end)
                        local res = try(function() return c.Brush.ResourceObject end)
                        if isValid(res) then e.tex = try(function() return res:GetFName():ToString() end) end
                    end
                    out.tree[#out.tree + 1] = e
                    if PANEL_CLASSES[e.cls] then walk(c, depth + 1) end
                end
            end
        end
        walk(box, 0)
    end
    return out
end

-- Niveau de recherche : boîte cachée → 0 ; sinon nombre d'étoiles à teinte claire.
-- Pendant la perte des étoiles (clignotement), on garde la dernière valeur non
-- nulle quelques secondes pour éviter le scintillement 0/N.
local lastWanted, lastWantedAt = 0, 0
local function wantedFromStars(pi, now)
    if not pi or not pi.stars then return 0 end
    local count = 0
    if pi.box_vis == nil or isShown(pi.box_vis) then
        for i = 1, 6 do
            local s = pi.stars[i] or {}
            if s.tint_r and s.tint_r > STAR_LIT_THRESHOLD then count = count + 1 end
        end
    end
    if count > 0 then
        lastWanted, lastWantedAt = count, now
        return count
    end
    -- Boîte cachée ou aucune étoile claire : on tolère 3 s de clignotement.
    if lastWanted > 0 and now - lastWantedAt <= 3 then return lastWanted end
    lastWanted = 0
    return 0
end

-- ---------------------------------------------------------------------------
-- Collecte de l'état
-- ---------------------------------------------------------------------------
local lastLogged = {}
local function logOnChange(key, value)
    if lastLogged[key] ~= value then
        lastLogged[key] = value
        log("%s = %s", key, tostring(value))
    end
end

local stageLogBudget = 3 -- on trace les étapes des 3 premiers ticks (diagnostic de crash)
local function stage(name)
    if stageLogBudget > 0 then log("étape : %s", name) end
end

local lastPos = nil
local wasInVehicle, enteredVehicleAt, lastVehicleExitAt = false, 0, nil

local function collectState()
    local now = os.time()
    local st = {
        version      = SCHEMA,
        timestamp    = now,
        mod_version  = VERSION,
        in_game      = false,
        paused       = false,
        zone         = nil,
        city         = nil,     -- calculé côté client à partir de x/y
        vehicle      = nil,
        in_vehicle   = nil,
        vehicle_kind = nil,
        mission      = nil,
        wanted       = 0,
        money        = nil,
        time         = nil,
        radio        = nil,
        dead         = nil,
        x = nil, y = nil, z = nil,
    }
    local dbg = flags.debug and { flags = {} } or nil
    if dbg then for k, v in pairs(flags) do dbg.flags[k] = v end end
    st.debug = dbg

    stage("gameterface")
    local gi = getGameterface()
    if not gi then
        if dbg then dbg.error = "gameterface introuvable" end
        return st
    end

    stage("IsPlayingGame")
    local playing = try(function() return gi:IsPlayingGame() end)
    st.in_game = (playing == true)
    logOnChange("in_game", st.in_game)
    if not st.in_game then return st end

    -- Menu pause
    if flags.menu then
        stage("menu")
        local menu = try(function() return gi.CurrentMenu end)
        st.paused = isValid(menu)
        if dbg and st.paused then dbg.current_menu = safeClassName(menu) end
        logOnChange("paused", st.paused)
    end

    -- Position joueur (lecture immédiate des champs du struct retourné)
    if flags.position then
        stage("GetGTAPlayerPosition")
        local ok, err = pcall(function()
            local pos = gi:GetGTAPlayerPosition()
            st.x, st.y, st.z = pos.X, pos.Y, pos.Z
        end)
        if not ok and dbg then dbg.position_err = tostring(err) end
        if stageLogBudget > 0 then log("position = %s %s %s", tostring(st.x), tostring(st.y), tostring(st.z)) end
    end

    -- Nom de zone via GetMapAreaName — EXPÉRIMENTAL, plante le jeu (voir en-tête).
    local areaName = nil
    if (flags.area or flags.area_ud or flags.area_sa) and st.x then
        stage("GetMapAreaName")
        local out = {}
        local ok, err = pcall(function()
            if flags.area_ud then
                gi:GetMapAreaName(gi:GetGTAPlayerPosition(), out)
            elseif flags.area_sa then
                gi:GetMapAreaName({ X = st.x / 100, Y = -st.y / 100, Z = st.z / 100 }, out)
            else
                gi:GetMapAreaName({ X = st.x, Y = st.y, Z = st.z }, out)
            end
        end)
        local name = ok and out.OutName or nil
        if name ~= nil and type(name) ~= "string" then name = try(function() return name:ToString() end) end
        if type(name) == "string" and trim(name) ~= "" then areaName = trim(name) end
        if dbg and not ok then dbg.area_err = tostring(err) end
        logOnChange("area_name", areaName or (dbg and dbg.area_err))
    end

    -- À pied / véhicule : GetAppropriateGamepadTab() vaut 0 à pied, 1 en véhicule.
    local tab = nil
    if flags.gamepad then
        stage("GetAppropriateGamepadTab")
        tab = try(function() return gi:GetAppropriateGamepadTab() end)
        logOnChange("gamepad_tab", tab)
    end

    if flags.misc and dbg then
        stage("misc")
        dbg.time_of_day = try(function() return gi:GetTimeOfDay() end)
        dbg.radio_offset = try(function() return gi:GetRadioStationOffset() end)
    end

    -- HUD PlayerInfo : étoiles, argent, heure
    if flags.playerinfo then
        stage("playerinfo")
        local pi = readPlayerInfo()
        if pi then
            st.wanted = wantedFromStars(pi, now)
            st.money = pi.money
            st.time = pi.time
            if dbg then dbg.player_info = pi end
            logOnChange("wanted", st.wanted)
        end
    end

    -- Caméra et vitesse (diagnostic)
    if flags.camera and dbg and st.x then
        stage("camera")
        local pc = getPlayerController()
        local cam = pc and try(function() return pc.PlayerCameraManager end)
        if isValid(cam) then
            pcall(function()
                local c = cam:GetCameraLocation()
                local dx, dy, dz = c.X - st.x, c.Y - st.y, c.Z - st.z
                dbg.cam_dist = math.sqrt(dx * dx + dy * dy + dz * dz) / 100
            end)
        end
        if lastPos and now > lastPos.t then
            local dx, dy, dz = st.x - lastPos.x, st.y - lastPos.y, st.z - lastPos.z
            dbg.speed = math.sqrt(dx * dx + dy * dy + dz * dz) / 100 / (now - lastPos.t)
        end
        lastPos = { x = st.x, y = st.y, z = st.z, t = now }
    end

    -- Titres HUD
    if flags.titles then
        stage("titles")
        st.dead = pollTitles(gi, dbg)
        if dbg then
            dbg.hud = {}
            for kind, h in pairs(hud) do
                if h.text then dbg.hud[kind] = { text = h.text, age = now - h.changed_at, visible = h.visible } end
            end
        end
    end

    -- Zone : titre HUD affiché à chaque changement de quartier (ou GetMapAreaName si validé).
    st.zone = areaName or hud.area.text
    st.radio = hud.radio.text

    -- Véhicule : état via gamepad_tab, nom via le titre HUD affiché à l'entrée.
    if tab ~= nil then
        st.in_vehicle = (tab ~= 0)
        st.vehicle_kind = tab
    end
    if st.in_vehicle then
        if not wasInVehicle then
            enteredVehicleAt = now
            wasInVehicle = true
        end
        if hud.vehicle.text and hud.vehicle.changed_at >= enteredVehicleAt - 3 then
            st.vehicle = hud.vehicle.text            -- titre apparu à l'entrée (ou depuis)
        elseif hud.vehicle.text and lastVehicleExitAt and (enteredVehicleAt - lastVehicleExitAt) < 90 then
            st.vehicle = hud.vehicle.text            -- même véhicule repris peu après en être sorti
        else
            st.vehicle = nil                         -- en véhicule, nom inconnu
        end
    else
        if wasInVehicle then lastVehicleExitAt = now end
        wasInVehicle = false
        st.vehicle = nil
    end
    st.mission = currentMission

    stage("fin")
    return st
end

local function writeState(st)
    local ok, err = writeFileAtomic(STATE_PATH, STATE_TMP, jsonValue(st))
    if not ok then
        log("Écriture de %s impossible : %s", STATE_PATH, tostring(err))
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- Exploration : dump des objets et des widgets texte
-- ---------------------------------------------------------------------------
local KEYWORDS = {
    "hud", "zone", "area", "mission", "wanted", "radar", "vehicle", "player",
    "ped", "weather", "clock", "radio", "money", "subtitle", "stat", "game",
    "widget", "pause", "menu", "level", "map", "gameface", "sa_", "sanandreas",
}

local function matchesKeyword(lowerName)
    for _, k in ipairs(KEYWORDS) do
        if lowerName:find(k, 1, true) then return true end
    end
    return false
end

local function dumpObjects()
    local f, err = io.open(DUMP_OBJECTS, "wb")
    if not f then log("dump_objects impossible : %s", tostring(err)) return end

    local classCount = {}
    local interesting = {}
    local total = 0
    ForEachUObject(function(obj)
        total = total + 1
        local cls = safeClassName(obj)
        classCount[cls] = (classCount[cls] or 0) + 1
        local full = safeFullName(obj)
        if matchesKeyword(full:lower()) and not full:find("^Function ") and not full:find("^Package ") then
            interesting[#interesting + 1] = full
        end
    end)

    f:write(string.format("BetterPresence object dump — %d objets\n\n", total))
    f:write("=== Classes (nombre d'instances) ===\n")
    local classes = {}
    for cls, n in pairs(classCount) do classes[#classes + 1] = { cls, n } end
    table.sort(classes, function(a, b) return a[1] < b[1] end)
    for _, c in ipairs(classes) do f:write(string.format("%6d  %s\n", c[2], c[1])) end

    f:write("\n=== Objets dont le nom contient un mot-clé ===\n")
    table.sort(interesting)
    for _, name in ipairs(interesting) do f:write(name, "\n") end
    f:close()
    log("dump_objects.txt écrit (%d objets, %d intéressants)", total, #interesting)
end

local function dumpWidgets()
    local f, err = io.open(DUMP_WIDGETS, "wb")
    if not f then log("dump_widgets impossible : %s", tostring(err)) return end

    f:write("=== UserWidget instances ===\n")
    local widgets = try(function() return FindAllOf("UserWidget") end) or {}
    for _, w in ipairs(widgets) do
        if isValid(w) then
            local vis = try(function() return w:GetVisibility() end)
            f:write(string.format("%s  visibility=%s\n", safeFullName(w), tostring(vis)))
        end
    end

    for _, cls in ipairs({ "TextBlock", "RichTextBlock", "GTAScalableRichTextBlock" }) do
        f:write(string.format("\n=== %s (texte affiché) ===\n", cls))
        local blocks = try(function() return FindAllOf(cls) end) or {}
        for _, tb in ipairs(blocks) do
            if isValid(tb) then
                local text = textToString(try(function() return tb:GetText() end))
                if text then
                    f:write(string.format("%-90s | %s\n", safeFullName(tb), text))
                end
            end
        end
    end
    f:close()
    log("dump_widgets.txt écrit (%d UserWidget)", #widgets)
end

local function runDumpIfRequested()
    if not fileExists(DUMP_REQUEST) then return end
    os.remove(DUMP_REQUEST)
    log("Dump demandé…")
    local ok, err = pcall(dumpObjects)
    if not ok then log("dumpObjects a échoué : %s", tostring(err)) end
    ok, err = pcall(dumpWidgets)
    if not ok then log("dumpWidgets a échoué : %s", tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- Boucle
-- ---------------------------------------------------------------------------
local tick = 0

local function onTick()
    tick = tick + 1
    local ok, err = pcall(function()
        if tick % 2 == 0 then loadFlags() end
        local st = collectState()
        writeState(st)
        if stageLogBudget > 0 then stageLogBudget = stageLogBudget - 1 end
        if tick % 2 == 0 then runDumpIfRequested() end
    end)
    if not ok then
        log("Erreur dans la boucle : %s", tostring(err))
    end
end

loadFlags()
log("v%s chargé. État → %s", VERSION, STATE_PATH)
log("Drapeaux : %s (fichier %s)", (function()
    local ks = {} for k, v in pairs(flags) do ks[#ks + 1] = k .. "=" .. (v and "1" or "0") end
    table.sort(ks) return table.concat(ks, " ") end)(), FLAGS_PATH)

LoopAsync(POLL_MS, function()
    ExecuteInGameThread(onTick)
    return false -- continuer la boucle
end)
