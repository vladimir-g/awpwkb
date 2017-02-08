--------------------------------------------------
-- awpwkb - awesome per-window keyboard layouts --
--------------------------------------------------
-- Copyright (c) 2017 Vladimir Gorbunov
-- This work is free. You can redistribute it and/or modify it under the
-- terms of the Do What The Fuck You Want To Public License, Version 2,
-- as published by Sam Hocevar. See the COPYING file for more details.

local setmetatable = setmetatable
local table = table
local capi = {
   client = client,
   awesome = awesome
}
local gears = require("gears")
local rules = require("awful.rules")
local keyboardlayout = require("awful.widget.keyboardlayout")


local awpwkb = {}

-- Change layout on focus if it was saved already
function awpwkb:on_focus(c)
   local id = c.window
   -- Check if we have layout already
   local layout_idx = self.clients[id]
   if layout_idx ~= nil and self:is_valid_layout(layout_idx) then
      -- Set saved layout
      awesome.xkb_set_layout_group(layout_idx)
      self.current_idx = layout_idx
      self:layout_changed()
   else
      -- Save current layout
      self.clients[id] = awesome.xkb_get_layout_group()
   end
end

-- Remove cached layout on client exit
function awpwkb:on_unmanage(c)
   self.clients[c.window] = nil
end

-- Update cacked layout on xkb change
function awpwkb:on_xkb_change()
   self:update_layouts()
   if capi.client.focus ~= nil then
      self.clients[capi.client.focus.window] = awesome.xkb_get_layout_group()
   end
   self.current_idx = awesome.xkb_get_layout_group()
   self:layout_changed()
end

-- Need to select default layout on manage
function awpwkb:on_manage(c)
   local layout_idx = nil
   -- Check rules
   for _, v in pairs(self.rules) do
      if rules.matches(c, v) then
         if v.layout.index ~= nil then
            if self:is_valid_layout(v.layout.index) then
               layout_idx = v.layout.index
            end
         elseif v.layout.name ~= nil then
            layout_idx = self:find_layout_idx_by_name(v.layout.name)
         end
         break
      end
   end
   -- Set default if rules don't apply
   if layout_idx == nil or not self:is_valid_layout(layout_idx) then
      layout_idx = self.default_layout
   end
   self.clients[c.window] = layout_idx

   -- Sometimes first focus signal isn't triggered
   if capi.client.focus and capi.client.focus.window == c.window then
      awesome.xkb_set_layout_group(layout_idx)
      self.current_idx = layout_idx
   end
   self:layout_changed()
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

function awpwkb:set_layout(name)
   local layout_idx = self:find_layout_idx_by_name(name)
   if layout_idx ~= nil then
      if capi.client.focus then
         self.clients[capi.client.focus.window] = layout_idx
      end
      awesome.xkb_set_layout_group(layout_idx)
      self.current_idx = layout_idx
      self:layout_changed()
   else
      -- Layout isn't fount - it is error
      gears.debug.print_error("Layout not found")
   end
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
   if self.on_layout_change == nil then
      return
   end
   local layout = self:get_current_layout()
   if layout ~= nil then
      self.on_layout_change(layout)
   end
end

-- Create new instance of awpwkb. Don't use it directly.
function awpwkb.new(opts)
   opts = opts or {}
   local obj = { clients = {} }
   setmetatable(obj, { __index = awpwkb })

   -- Save opts, maybe they'll be needed in future
   obj.opts = opts

   -- Rules
   obj.rules = opts.rules or {}

   -- Update layouts for first time (maybe it isn't really needed)
   obj:update_layouts()

   -- Set default layout for new windows
   obj.default_layout = obj:find_layout_idx_by_name(opts.default_layout) or 0

   -- Add signals
   capi.client.connect_signal("focus", function(c) obj:on_focus(c) end)
   capi.client.connect_signal("unmanage", function(c) obj:on_unmanage(c) end)
   capi.client.connect_signal("manage", function(c) obj:on_manage(c) end)
   capi.awesome.connect_signal("xkb::map_changed", function(c) obj:on_xkb_change() end)
   capi.awesome.connect_signal("xkb::group_changed", function(c) obj:on_xkb_change() end)

   return obj
end

local instance = nil

-- Get instance of awpwkb. Opts would work only on first call.
function awpwkb.init(opts)
   if instance == nil then
      instance = awpwkb.new(opts)
   end
   return instance
end

return awpwkb
