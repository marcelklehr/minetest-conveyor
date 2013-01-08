-- conveyor mod for Minetest
-- Copyright 2012 Mark Holmquist <mtraceur@member.fsf.org>
-- Copyright 2012 Marcel Klehr <mklehr@gmx.net>
--
-- The conveyor mod is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- The conveyor mod is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with the conveyor mod. If not, see <http://www.gnu.org/licenses/>.

-- Item flow chart:
-- 
-- [source node]    [ !conveyor! ]    [target node]
-- [ inventory ] -> [ inventory  ] -> [ inventory ]
-- [           ]    [            ]    [           ]

local tbox = {
    type = "fixed",
    fixed = {
        { -0.5, -0.4, -0.3, 0.5, 0.1, 0.3 } -- upper left, near corner:(x, y, z), lower right, far corner(x, y, z) [values are relative to the block center]
    }
}

conveyor_adapters = {}

local modpath = minetest.get_modpath( 'conveyor' )

dofile( modpath .. '/adapters/chest.lua' )
dofile( modpath .. '/adapters/furnace.lua' )
dofile( modpath .. '/adapters/rubber_collector.lua' )
dofile( modpath .. '/adapters/factory.lua' )
dofile( modpath .. '/adapters/conveyor.lua' )

minetest.register_node( 'conveyor:conveyor', {
    description = 'Conveyor',
    node_box = tbox,
    selection_box = tbox,
    drawtype = 'nodebox',
    paramtype = 'light',
    paramtype2 = 'facedir',
    groups = { cracky = 2 },
    tiles = {
        'conveyor_top.png',
        'conveyor_bottom.png',
        'conveyor_side.png',
        'conveyor_side.png',
        'conveyor_back.png',
        'conveyor_front.png'
    },

    on_construct = function ( pos )
        local meta = minetest.env:get_meta( pos )
        meta:set_string('infotext', 'Conveyor')
        meta:set_int('conveyor:locked', 0)
        local inv = meta:get_inventory()
        inv:set_size( 'main', 1 ) 
    end,

    after_place_node = function(pos, placer)
        local meta = minetest.env:get_meta(pos)
        meta:set_string("owner", placer:get_player_name() or "")
    end,

    can_dig = function(pos, player)
      local meta = minetest.env:get_meta(pos);
      local inv = meta:get_inventory()
      
      if meta:get_int('conveyor:locked') == 1 then
        return inv:is_empty('main') and player:get_player_name()  == meta:get_string('owner')
      end

      return inv:is_empty('main')
    end
} )

minetest.register_craft( {
    output = 'conveyor:conveyor',
    recipe = {
        { 'rubber_sheet:rubber_sheet', 'rubber_sheet:rubber_sheet', 'rubber_sheet:rubber_sheet' },
        { 'gears:gear', '', 'gears:gear' },
        { 'rubber_sheet:rubber_sheet', 'rubber_sheet:rubber_sheet', 'rubber_sheet:rubber_sheet' }
    }
} )

-- Transfer is allowed if...
--  -> the other node has an owner that equals the current conveyors owner
--  -> the other node has no owner (allowing people to transport things out of their locked chests into publicly available items)
function conveyor_access_allowed(locked, myOwner, otherOwner)
  if not locked then
    return true
  end
  return otherOwner == myOwner  or  otherOwner == ""
end

locked_things = {}
locked_things['default:chest_locked'] = 1


minetest.register_abm( {
    nodenames = { 'conveyor:conveyor' },
    interval = 1.0,
    chance = 1,
    action = function ( pos, node )
        local fromnode, tonode
        local frompos = { x = pos.x, y = pos.y, z = pos.z }
        local topos = { x = pos.x, y = pos.y, z = pos.z }
        
        -- determine direction (-> origin and target)
        local facedir = node.param2
        if facedir == 0 then
            frompos.x = frompos.x - 1
            topos.x = topos.x + 1
        elseif facedir == 1 then
            frompos.z = frompos.z + 1
            topos.z = topos.z - 1
        elseif facedir == 2 then
            frompos.x = frompos.x + 1
            topos.x = topos.x - 1
        elseif facedir == 3 then
            frompos.z = frompos.z - 1
            topos.z = topos.z + 1
        end

        -- identify the nodes we're dealing with
        fromnode = minetest.env:get_node( frompos ).name
        tonode = minetest.env:get_node( topos ).name

        local meta = minetest.env:get_meta( pos )
        local inv = meta:get_inventory()
        local infotext = 'Conveyor'
        local activity = false

        if conveyor_adapters[fromnode] or conveyor_adapters[tonode] or not inv:is_empty('main') then
        
          local tometa = minetest.env:get_meta(topos)
          local frommeta = minetest.env:get_meta(frompos)
          local targetWishlist


          -- If a conveyor belt connects with a locked chest,
          -- all individual conveyors of the same owner may only be removed by their owner
          -- to prevent intercepting conveyor belts
          if (frommeta:get_int('conveyor:locked') == 1 or locked_things[fromnode]) 
            or (tometa:get_int('conveyor:locked') == 1 or locked_things[tonode]) then
              meta:set_int('conveyor:locked', 1)
          else
              meta:set_int('conveyor:locked', 0)
          end
          

          -- Determine whether to allow giving things to target
          if conveyor_adapters[tonode] and conveyor_access_allowed( meta:get_int('conveyor:locked') == 1 , meta:get_string('owner'), tometa:get_string('owner')) then

              -- find out what the target node wants
              targetWishlist = conveyor_adapters[tonode].wishlist
              if targetWishlist == nil and conveyor_adapters[tonode].get_wishlist ~= nil then
                targetWishlist = conveyor_adapters[tonode].get_wishlist( topos )
              end

              -- give the contents of my inventory to the target node
              if inv:is_empty( 'main' ) ~= true then
                  local stack = inv:get_stack('main', 1)
                  -- print('[Conveyor] adding ' .. stack:get_count() .. ' ' .. stack:to_string() .. ' to ' .. tonode)
                  conveyor_adapters[tonode].add(topos, inv:remove_item( 'main', ItemStack(stack:get_name()) ), function ( leftover )
                        -- anything that's left over (e.g. the target inventory is full) goes back
                        inv:add_item('main', leftover)
                      end
                  )
                  activity = true
              end

          else
              infotext = infotext .. ' (Not allowed to access target! My owner: '.. meta:get_string('owner') .. ')'
          end

          -- Determine whether to allow fetching things from origin
          if conveyor_adapters[tonode] and conveyor_adapters[fromnode] and conveyor_access_allowed( meta:get_int('conveyor:locked') == 1 , meta:get_string('owner'), frommeta:get_string('owner')) then
          
              -- get resource from origin and add it to my inventory
              local inbound = conveyor_adapters[fromnode].get( frompos, targetWishlist )
              if inbound ~= nil and not inbound:is_empty() then
                  --print('[Conveyor] taking '.. inbound:get_count() ..' '.. inbound:get_name() .. ' to ' .. fromnode)
                  local leftover = inv:add_item('main', inbound )
                  if not leftover:is_empty() then
                    -- anything that does not fit in there goes back
                    conveyor_adapters[fromnode].add( leftover )
                  end
                  activity = true
              end
          
          else
              infotext = infotext .. ' (Not allowed to access origin! My owner: '.. meta:get_string('owner') .. ')'
          end

          if activity then
            infotext = infotext .. ' (active; '
          else
            infotext = infotext .. ' (inactive; '
          end
          infotext = infotext .. inv:get_stack('main', 1):get_count() .. ' items)'

        end
        
        -- update infotext
        if meta:get_string('infotext') ~= infotext then
            meta:set_string( 'infotext', infotext)
        end
    end
} )

