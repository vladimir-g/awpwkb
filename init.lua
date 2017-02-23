--------------------------------------------------
-- awpwkb - awesome per-window keyboard layouts --
--------------------------------------------------
-- Copyright (c) 2017 Vladimir Gorbunov
-- This work is free. It comes without any warranty, to the extent
-- permitted by applicable law. You can redistribute it and/or modify
-- it under the terms of the Do What The Fuck You Want To Public
-- License, Version 2, as published by Sam Hocevar. See the COPYING
-- file for more details.

local setmetatable = setmetatable
local table = table
local capi = {
   client = client,
   awesome = awesome
}
local awful = require("awful")
local gears = require("gears")
local rules = require("awful.rules")
local keyboardlayout = require("awful.widget.keyboardlayout")

local awpwkb = {}

-- Get layout from rule by name or index
function awpwkb:get_layout_idx_from_rule(rule)
   if rule.layout.index ~= nil then
      if self:is_valid_layout(rule.layout.index) then
         return rule.layout.index
      end
   elseif rule.layout.name ~= nil then
      return self:find_layout_idx_by_name(rule.layout.name)
   end
   return
end

-- Match rules list and get layout index
function awpwkb:match_rules(c, rules_list)
   for _, v in pairs(rules_list) do
      if v.check_callback ~= nil then
         if v.check_callback(c) then
            return self:get_layout_idx_from_rule(v)
         end
      elseif rules.matches(c, v) then
         return self:get_layout_idx_from_rule(v)
      end
   end
   return
end

-- Change layout on focus if it was saved already
function awpwkb:on_focus(c)
   -- Sometimes focus can trigger before manage
   if not c.awpwkb_managed then return end

   local layout_idx = nil
   -- Check if we have focus rules
   if layout_idx == nil and self.focus_rules then
      layout_idx = self:match_rules(c, self.focus_rules)
   end

   -- No rule exist, so get already stored layout because focus rules
   -- has priority over saved
   if layout_idx == nil then
      layout_idx = c.awpwkb_layout
   end

   if layout_idx == nil or not self:is_valid_layout(layout_idx) then
      layout_idx = self.default_layout
   end

   -- Save layout
   awesome.xkb_set_layout_group(layout_idx)
   self.current_idx = layout_idx
   c.awpwkb_layout = layout_idx
   self:layout_changed()
end

-- Update cacked layout on xkb change
function awpwkb:on_xkb_change()
   self:update_layouts()
   if capi.client.focus ~= nil then
      capi.client.focus.awpwkb_layout = awesome.xkb_get_layout_group()
   end
   self.current_idx = awesome.xkb_get_layout_group()
   self:layout_changed()
end

-- Need to select default layout on manage
function awpwkb:on_manage(c)
   -- Don't do anything if window already managed
   if c.awpwkb_managed then return end

   local layout_idx = c.awpwkb_layout
   -- Check rules
   if layout_idx == nil and self.default_rules then
      layout_idx = self:match_rules(c, self.default_rules)
   end

   -- Apply layout if it is valid
   if layout_idx ~= nil and self:is_valid_layout(layout_idx) then
      c.awpwkb_layout = layout_idx
   end

   c.awpwkb_managed = true
   -- Sometimes first focus signal isn't triggered
   if capi.client.focus and capi.client.focus.window == c.window then
      self:on_focus(c)
   end
end

-- Create layout name from layout. Taken from kayboardlayout widget.
function awpwkb.layout_name(layout)
   local name = layout.file
   if layout.section ~= nil then
      name = name .. "(" .. layout.section .. ")"
   end
   return name
end

-- Get layout index by name
function awpwkb:find_layout_idx_by_name(name)
   for idx, layout in pairs(self.layouts) do
      if self.layout_name(layout) == name then
         return idx - 1
      end
   end
   return nil
end

-- Get layout by index
function awpwkb:find_layout_by_idx(idx)
   for _, layout in pairs(self:get_layouts()) do
      if layout.idx == idx then
         return layout
      end
   end
end

-- Check if layout index is valid
function awpwkb:is_valid_layout(idx)
   return idx >= 0 and idx < #self.layouts
end

-- Return layout list
function awpwkb:get_layouts()
   local list = {}
   for idx, layout in pairs(self.layouts) do
      table.insert(list, {
         idx = idx - 1,
         name = self.layout_name(layout),
         layout = layout
      })
   end
   return list
end

-- Update list of layouts
function awpwkb:update_layouts()
   self.layouts = keyboardlayout.get_groups_from_group_names(
      awesome.xkb_get_group_names()
   )
end

-- Set layout by name
function awpwkb:set_layout(name)
   local layout_idx = self:find_layout_idx_by_name(name)
   if layout_idx ~= nil then
      if capi.client.focus then
         capi.client.focus.awpwkb_layout = layout_idx
      end
      awesome.xkb_set_layout_group(layout_idx)
      self.current_idx = layout_idx
      self:layout_changed()
   else
      -- Layout isn't fount - it is error
      gears.debug.print_error("Layout not found")
   end
end

-- Set next layout
function awpwkb:set_next_layout()
   self:inc_layout(1)
end

-- Set previous layout
function awpwkb:set_prev_layout()
   self:inc_layout(-1)
end

-- Set layout by relative index
function awpwkb:inc_layout(num)
   local idx = (self.current_idx + num) % #self.layouts
   awesome.xkb_set_layout_group(idx)
   self.current_idx = idx
   self:layout_changed()
end

-- Get current layout name and index
function awpwkb:get_current_layout()
   if self.current_idx ~= nil then
      local layout = self:find_layout_by_idx(self.current_idx)
      if layout ~= nil then
         return layout
      end
   end
   return nil
end

-- Callbacks
-- Inner function to run changed callback
function awpwkb:layout_changed()
   local layout = self:get_current_layout()
   if layout ~= nil then
      if self.on_layout_change ~= nil then
         self.on_layout_change(layout)
      end
      self:emit_signal("on_layout_change", layout)
   end
end

-- Create new instance of awpwkb. Don't use it directly.
function awpwkb.new(opts)
   opts = opts or {}

   -- Create new object from gears.object for signals support
   local obj = gears.object { class = awpwkb }

   -- Save opts, maybe they'll be needed in future
   obj.opts = opts

   -- Rules
   obj.default_rules = opts.default_rules
   obj.focus_rules = opts.focus_rules

   -- Set persisten x property to check if we already got layout
   awful.client.property.persist("awpwkb_layout", "number")
   -- Property to check if awpwkb already do on_manage check
   awful.client.property.persist("awpwkb_managed", "boolean")

   -- Update layouts for first time (maybe it isn't really needed)
   obj:update_layouts()

   -- Set default layout for new windows
   obj.default_layout = obj:find_layout_idx_by_name(opts.default_layout) or 0

   -- Add signals
   capi.client.connect_signal("focus", function(c) obj:on_focus(c) end)
   capi.client.connect_signal("manage", function(c) obj:on_manage(c) end)
   capi.awesome.connect_signal("xkb::map_changed", function(c) obj:on_xkb_change() end)
   capi.awesome.connect_signal("xkb::group_changed", function(c) obj:on_xkb_change() end)

   return obj
end

local instance = nil

-- Get instance of awpwkb. Init must be run before.
function awpwkb.get()
   return instance
end

-- Init instance of awpwkb.
function awpwkb.init(opts)
   instance = awpwkb.new(opts)
   return instance;
end

return awpwkb
