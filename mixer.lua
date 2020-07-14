dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local allowed_urls = {}
local ids = {}
local current_id = nil
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if allowed_urls[url] then
    return true
  end

  if string.match(url, "'+")
    or string.match(url, "[<>\\\"'%*%$;%^%[%],%(%){}\n]")
    or not string.match(url, "^https?://[^/]*mixer%.com") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  for s in string.gmatch(url, "([0-9a-f%-]+)") do
    if ids[s] then
      return true
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\\"'%*%$;%^%[%],%(%){}\n]") then
    return false
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
     and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla, force)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if force == true then
      allowed_urls[url_] = true
    end
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl, force)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"), force)
    elseif string.match(newurl, "^https?://") then
      check(newurl, force)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)") .. string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)") .. newurl, force)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)") .. string.gsub(newurl, "\\", ""), force)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)") .. newurl, force)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"), force)
    end
  end

  local function checknewshorturl(newurl, force)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)") .. newurl, force)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^webcals?:")
        or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)") .. newurl, force)
    end
  end

  if allowed(url, nil) and status_code == 200
    and not string.match(url, "%.ts$")
    and not string.match(url, "^https?://uploads%.mixer%.com/") then
    html = read_file(file)
    if string.match(url, "%.m3u8$") then
      for newurl in string.gmatch(html, "([^\r\n]+)") do
        checknewurl(newurl, true)
      end
    end
    if string.match(url, "^https?://mixer%.com/api/v1/clips/[0-9a-f%-]+$") then
      local data = load_json_file(html)
      check("https://mixer.com/api/v1/ascension/channels/" .. data["ownerChannelId"] .. "/details", true)
      check("https://mixer.com/api/v1/channels/" .. data["ownerChannelId"] .. "/broadcast", true)
      check("https://mixer.com/api/v1/channels/" .. data["ownerChannelId"] .. "/features", true)
      check("https://mixer.com/api/v1/channels/" .. data["ownerChannelId"] .. "/manifest.light2", true)
      check("https://mixer.com/api/v1/channels/" .. data["ownerChannelId"], true)
      check("https://mixer.com/api/v1/chats/" .. data["ownerChannelId"] .. "/anonymous", true)
      check("https://mixer.com/api/v1/clips/channels/" .. data["ownerChannelId"], true)
      check("https://mixer.com/api/v1/types/" .. data["typeId"], true)
      check("https://mixer.com/api/v1/types/" .. data["typeId"] .. "?noCount=1", true)
      check("https://mixer.com/api/v2/channels/" .. data["ownerChannelId"] .. "/viewerCount", true)
      check("https://mixer.com/api/v2/channels/" .. data["ownerChannelId"] .. "/viewerCount", true)
      check("https://mixer.com/api/v2/chats/" .. data["ownerChannelId"] .. "/history", true)
      check("https://mixer.com/api/v2/clips/channels/" .. data["ownerChannelId"] .. "/settings", true)
      check("https://mixer.com/api/v2/leaderboards/embers-weekly/channels/" .. data["ownerChannelId"], true)
      check("https://mixer.com/api/v2/levels/patronage/channels/" .. data["ownerChannelId"] .. "/status/all", true)
      check("https://mixer.com/api/v2/vods/channels/" .. data["ownerChannelId"], true)
    end
    if string.match(url, "^https?://mixer%.com/api/v1/channels/[0-9]+$") then
      local data = load_json_file(html)
      check("https://mixer.com/" .. data["token"] .. "?clip=" .. current_id, true)
      check("https://mixer.com/api/v1/channels/" .. data["token"], true)
      check("https://mixer.com/api/v1/channels/" .. data["token"] .. "?noCount=1", true)
      check("https://mixer.com/api/v1/users/" .. data["userId"] .. "/achievements", true)
      check("https://mixer.com/api/v1/users/" .. data["userId"] .. "/achievements?noCount=1", true)
      check("https://mixer.com/api/v1/users/" .. data["userId"] .. "/avatar?w=64&h=64", true)
      check("https://mixer.com/api/v1/users/" .. data["userId"] .. "/teams", true)
      check("https://mixer.com/api/v1/users/" .. data["userId"] .. "/teams?noCount=1", true)
      check("https://mixer.com/api/v1/users/" .. data["userId"], true)
      check("https://mixer.com/api/v1/users/" .. data["userId"] .. "?noCount=1", true)
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  local match = string.match(url["url"], "^https?://mixer%.com/api/v1/clips/([0-9a-f%-]+)$")
  if match ~= nil then
    ids[match] = true
    current_id = match
  end

  if status_code >= 300 and status_code <= 399 then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 404 and status_code ~= 405 and status_code ~= 403)
      or status_code  == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if not allowed(url["url"], nil) then
        maxtries = 2
    end
    if tries > maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
