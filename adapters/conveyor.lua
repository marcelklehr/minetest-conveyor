-- Conveyor mod for Minetest
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

-- CONVEYOR ADAPTER (for conveyor chaining)
conveyor_adapters['conveyor:conveyor'] = {
    get = function ( pos, wishlist )
        local inv = minetest.env:get_meta( pos ):get_inventory()
        
        -- no wish list? so we just return what we got
        if wishlist == nil then
            return inv:remove_item('main', inv:get_stack('main', 0))
        end
        
        -- Try every item in the wishlist and return it if we got it
        for _, thing in ipairs( wishlist ) do
            local itst = ItemStack( thing )
            if inv:contains_item( 'main', itst ) then
                return inv:remove_item( 'main', itst )
            end
        end
        
        return false
    end,
    add = function ( pos, thing, addcb )
        if not thing then
            return
        end
        local inv = minetest.env:get_meta( pos ):get_inventory()
        local leftover = inv:add_item( 'main', thing )
        if not leftover:is_empty() and addcb ~= nil then
            addcb( thing )
        end
    end
}

