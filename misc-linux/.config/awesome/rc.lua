-- need to do this before everything, so that signal handler fires before standard ones
client.connect_signal("unmanage", function (c) c.was_floating = c.floating end)

local aw = require("awful")
local ar = require("awful.rules")
local al = require("awful.layout")
local na = require("naughty")
local be = require("beautiful")
local wi = require("wibox")
local gt = require("gears.timer")
-- 3rd party libs
local cfg = require("my-config")
local ut = require("my-utils")
local af = require("my-autofocus")
local cf = require("cyclefocus")
-- local sw = require("awesome-switcher-preview")
local ch = require("conky-hud")

local HOME_DIR = os.getenv("HOME")
na.config.defaults.font = "Sans " .. (10 * cfg.font_scale_factor)
cf.naughty_preset.position = "center_middle"

local debug = function (msg)
   na.notify({
         text = tostring(msg),
         timeout = 10
   })
end

awesome.connect_signal(
   "debug::error",
   function (msg)
      debug(msg)
   end
)

aw.util.spawn_with_shell(HOME_DIR .. "/.xdesktoprc.awesome")
be.init("/usr/share/awesome/themes/default/theme.lua")

-- layouts

local tag_list = {1, 2, 3, 4}
local global_keys_switch_tags = {}

for i, t in ipairs(tag_list) do
   if i >= 10 then break end
   global_keys_switch_tags = aw.util.table.join(
      global_keys_switch_tags,
      aw.key({ "Mod4" }, tostring(i), function () aw.screen.focused().tags[i]:view_only() end)
   )
end

local layouts = {
   al.suit.tile,
   al.suit.fair,
   al.suit.max
}

tags = {}
for s = 1, screen.count() do
   tags[s] = aw.tag(tag_list, s, layouts[1])
end

require("my-widgets")

-- helper functions

local is_floating = function (c)
   return
      c.was_floating or c.floating
      or c.maximized_horizontal or c.maximized_vertical or c.maximized
      or #al.parameters(nil, c.screen).clients <= 1 
      or c.type == "dialog"
end

af.find_alternative_focus = function(prev, s)
   if prev and not prev.valid then prev = nil end
   if prev then 
      local f = is_floating(prev)
      local new_focus = cf.find_history(
         0, {
            function (c)
               return c.valid and c:isvisible() and is_floating(c) == f
            end
      })
      
      if new_focus then
         return new_focus
      end
   end
   
   new_focus = cf.find_history(
      0, {
         function (c)
            return c.valid and c:isvisible()
         end
   })

   return new_focus
end

local my_focus_by_direction = function(dir)
   local old_c = client.focus
   aw.client.focus.global_bydirection(dir);
   local new_c = client.focus
   
   if old_c ~= new_c and new_c ~= nil then 
      aw.screen.focus(new_c.screen.index)
      new_c:raise()
   end
end

-- keys and buttons
local global_keys = aw.util.table.join(
   global_keys_switch_tags,
   
   aw.key({ "Mod4", "Control" }, "Left", aw.tag.viewprev),
   aw.key({ "Mod4", "Control" }, "Right", aw.tag.viewnext),
      
   aw.key({ "Mod4" }, "[", function () al.inc(layouts, -1) end),
   aw.key({ "Mod4" }, "]", function () al.inc(layouts, 1) end),

   cf.key({ "Mod1" }, "Tab", 1,
      {
         modifier = "Alt_L",
         cycle_filters = {
            -- cf.filters.same_screen, cf.filters.common_tag
            function (c, src_c)
               return c:isvisible()
            end
            ,
            function (c, src_c)
               if src_c == nil then return true end
               if c.pid == src_c.pid then return true
               else
                  return is_floating(c) == is_floating(src_c)
               end
            end
         }
   }),

   aw.key({ "Mod4" }, "w", function () my_focus_by_direction("up") end),
   aw.key({ "Mod4" }, "a", function () my_focus_by_direction("left") end),
   aw.key({ "Mod4" }, "s", function () my_focus_by_direction("down") end),
   aw.key({ "Mod4" }, "d", function () my_focus_by_direction("right") end),
   
   -- aw.key({ "Mod1",           }, "Tab",
   --    function ()
   --       sw.switch( 1, "Alt_L", "Tab", "ISO_Left_Tab")
   -- end),
   -- aw.key({ "Mod1", "Shift"   }, "Tab",
   --    function ()
   --       sw.switch(-1, "Alt_L", "Tab", "ISO_Left_Tab")
   -- end),

   aw.key({ }, "XF86AudioLowerVolume", function() aw.util.spawn("amixer sset Master,0 2%-") end),
   aw.key({ }, "XF86AudioRaiseVolume", function() aw.util.spawn("amixer sset Master,0 2%+") end),
   aw.key({ }, "XF86AudioMute", function() aw.util.spawn("amixer sset Master,0 toggle") end),
   aw.key({ }, "XF86MonBrightnessUp", function () aw.util.spawn("xbacklight -inc 5") end),
   aw.key({ }, "XF86MonBrightnessDown", function () aw.util.spawn("xbacklight -dec 5") end),   

   aw.key({ "Mod4", "Control" }, "m", function () for _, c in pairs(client.get()) do c.minimized = false end end),

   aw.key({ "Mod4" }, "r", function () aw.util.spawn_with_shell("dlauncher open") end),
   aw.key({ "Mod4" }, "Return", function () aw.util.spawn("open-terminal-emulator") end),
   aw.key({ "Mod4", "Control" }, "Return", function () aw.util.spawn_with_shell("open-terminal-emulator background") end),
   aw.key({ "Mod4" }, "t", function () aw.util.spawn("urxvt -name root-terminal") end),

   aw.key({ "Mod4" }, "F1", function () ch.toggle_conky() end),
   aw.key({ "Mod4" }, "F2", function () aw.util.spawn("gmpc") end),
   aw.key({ "Mod4" }, "grave", function() ch.raise_conky() end, function() ch.lower_conky_delayed() end),
   
   aw.key({ "Mod4", "Control" }, "Escape", awesome.quit)
)

local client_keys = aw.util.table.join(
   aw.key({ "Mod4" }, "Tab", function(src_c)
         local f = is_floating(src_c)
         local new_focus = nil
         
         for _, c in ipairs(client.get(src_c.screen)) do
            if c:isvisible() and (not aw.client.focus.filter or aw.client.focus.filter(c)) then
               if not is_floating(c) then
                  if f then
                     c:raise()
                  else
                     c:lower()
                  end
               else
               end
            end            
         end

         new_focus = cf.find_history(
            0, {
               function (c)
                  return cf.filters.same_screen(c, src_c)
                     and cf.filters.common_tag(c, src_c)
                     and is_floating(c) ~= f
               end
         })
         
         if new_focus then
            client.focus = new_focus
         end
         client.focus:raise()
   end),

   aw.key({ "Mod4" }, "Up", function (c)
         if c.minimized then
            c.minimized = false
         else
            c.maximized = not c.maximized
         end
   end),

   aw.key({ "Mod4", "Shift" }, "Up", function (c)
         c.maximized_vertical = not c.maximized_vertical
   end),

   aw.key({ "Mod4", "Control" }, "Up", function (c)
         c.maximized_horizontal = not c.maximized_horizontal
   end),

   -- aw.key({ "Mod4" }, "Down", function (c)
   --       c.minimized = true
   -- end),
      
   aw.key({ "Mod4" }, "Left", function (c)
         if not is_floating(c) then
            c:swap(aw.client.getmaster())
         end
   end),

   aw.key({ "Mod4" }, "Right", function (c)
         if c.floating then
            c.maximized = false;
            c.maximized_vertical = false;
            c.maximized_horizontal = false;
         end
         aw.client.floating.toggle(c);
   end),

   aw.key({ "Mod4", "Control" }, "w", function (c) aw.client.swap.global_bydirection("up"); gt.delayed_call(function () client.focus = c; c:raise() end); end),
   aw.key({ "Mod4", "Control" }, "a", function (c) aw.client.swap.global_bydirection("left"); gt.delayed_call(function () client.focus = c; c:raise() end); c:raise() end),
   aw.key({ "Mod4", "Control" }, "s", function (c) aw.client.swap.global_bydirection("down"); gt.delayed_call(function () client.focus = c; c:raise() end); c:raise() end),
   aw.key({ "Mod4", "Control" }, "d", function (c) aw.client.swap.global_bydirection("right"); gt.delayed_call(function () client.focus = c; c:raise() end); c:raise() end),

   aw.key({ "Mod4" }, "j", function (c) aw.tag.incmwfact(-0.05) end),
   aw.key({ "Mod4" }, "l", function (c) aw.tag.incmwfact( 0.05) end),
   aw.key({ "Mod4" }, "i", function (c) aw.client.incwfact(-0.1) end),
   aw.key({ "Mod4" }, "k", function (c) aw.client.incwfact( 0.1) end),


   aw.key({ "Mod4" }, "c", function (c) c:kill() end)
)

local client_buttons = aw.util.table.join(
   aw.button({ }, 1, function (c) client.focus = c; c:raise() end),
   aw.button({ "Mod4" }, 1, aw.mouse.client.move),
   aw.button({ "Mod4" }, 3, aw.mouse.client.resize)
)

root.keys(global_keys)

-- rules

client.connect_signal(
   "focus",
   function (c)
      c.border_color = be.border_focus
   end
)
client.connect_signal(
   "unfocus",
   function (c)
      c.border_color = be.border_normal      
   end
)

ar.rules = {
   {
      rule = { },
      properties = {
         focus = true,
         size_hints_honor = false,
         keys = client_keys,
         buttons = client_buttons,
         border_width = 2 * cfg.widget_scale_factor,
         border_color = be.border_normal
      }
   },
   {
      rule = { class = "Conky" },
      properties = {
         floating = true,
         sticky = true,
         ontop = false,
         below = true,
         focus = false,
         border_width = 0,
         focusable = false
      }
   },
   {
      rule = { class = "Wicd-client.py" },
      properties = {
         floating = true
      }
   },
   {
      rule = { class = "Eclipse" },
      properties = { floating = true }
   }
}
