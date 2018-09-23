--- A point-and-click adventure game library for LÖVE.
-- @module init
local slime = {
  _VERSION     = 'slime v0.1',
  _DESCRIPTION = 'A point-and-click adventure game library for LÖVE',
  _URL         = 'https://github.com/wesleywerner/loveslime',
  _LICENSE     = [[
    MIT LICENSE

    Copyright (c) 2016 Wesley Werner

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}

-- Uses anim8 by Enrique García Cota
-- https://github.com/kikito/anim8
local anim8 = require 'slime.anim8'

local actors = { }
local backgrounds = { }
local bags = { }
local chains = { }
local events = { }
local debug = { }
local cursor = { }
local hotspots = { }
local floors = { }
local layers = { }
local path = { }
local settings = { }
local speech = { }



--               _
--     __ _  ___| |_ ___  _ __ ___
--    / _` |/ __| __/ _ \| '__/ __|
--   | (_| | (__| || (_) | |  \__ \
--    \__,_|\___|\__\___/|_|  |___/

--- Actors are items on your stage that walk or talk, like people, animals and robots.
-- They can also be inanimate objects and are animated, like doors, toasters and computers.
--
-- @table actor
--
-- @tparam string name
-- The name of the actor.
--
-- @tparam int x
--
-- @tparam int y
--
-- @tparam string feet
-- Position of the actor's feet relative to the sprite.

--- Clear actors.
function actors:clear ( )

	self.list = { }

end

--- Add an actor.
--
-- @tparam string name
-- The name of the actor
--
-- @tparam int x
--
-- @tparam int y
function actors:add (name, x, y)

    -- Add an actor to the stage.
    -- Allows adding the same actor name multiple times, but only
    -- the first instance uses the "name" as the key, subsequent
    -- duplicates will use the natural numbering of the table.

    -- default sprite size
    local w = 10
    local h = 10

    local newActor = {
        ["isactor"] = true,
        ["name"] = name,
        ["x"] = x,
        ["y"] = y,
        ["direction recalc delay"] = 0,     -- delay direction calc counter.
        ["w"] = w,
        ["h"] = h,
        ["feet"] = {0, 0},                  -- position of actor's feet (relative to the sprite)
        ["image"] = nil,                    -- a static image of this actor.
        ["animations"] = { },
        ["direction"] = "south",
        ["action"] = "idle",
        ["speechcolor"] = {255, 255, 255},
        ["inventory"] = { }
        }

    function newActor:getAnim ()
        local priorityAction = self.action == "talk" or self.action == "walk"
        if (self.customAnimationKey and not priorityAction) then
            return self.animations[self.customAnimationKey]
        else
            local key = self.action .. " " .. self.direction
            return self.animations[key]
        end
    end

    table.insert(self.list, newActor)

    -- set actor image method
    newActor.setImage = slime.setImage

    -- set the actor new animation method
    -- TODO refactor this, pass animation data to this add() method
    -- instead of all this chaining business.
    newActor.tileset = slime.defineTileset

    -- set slime host reference
    newActor.host = self

    self:sort ()

    return newActor

end

--- Update actors
--
--  animations and movement.
--
-- @tparam int dt
-- The delta time since the last update.
--
-- @local
function actors:update (dt)

	local actorsMoved = false

    -- Update animations
    for _, actor in ipairs(self.list) do
        if actor.isactor then

            if self:updatePath (actor, dt) then
				actorsMoved = true
            end

            local anim = actor:getAnim()
            if anim then
                anim._frames:update(dt)
                local framesound = anim._sounds[anim._frames.position]
                if framesound then
                    love.audio.play(framesound)
                end
            end
        end
    end

	-- reorder if any actors moved
	if actorsMoved then
		self:sort ()
    end

end

--- Sort actors.
--
-- Orders actors and layers for correct z-order drawing.
-- It sorts by actor feet position (for actors)
-- and baselines (for layers).
--
-- @local
function actors:sort ( )

    table.sort(self.list, function (a, b)

            --~ local m = a.isactor and a.y or a.baseline
            --~ local n = b.isactor and b.y or b.baseline
            --~ if a.isactor and a.nozbuffer then m = 10000 end
            --~ if b.isactor and b.nozbuffer then n = 10001 end
            --~ return m < n

			-- layers only have a baseline.
			-- actors can optionally have a baseline.

			local aY = 0
			local bY = 0

			if a.islayer then
				aY = a.baseline
			elseif a.onTop then
				aY = 10000
			elseif a.onBottom then
				aY = -10000
			else
				aY = a.y + (a.baseline or 0)
			end

			if b.islayer then
				bY = b.baseline
			elseif b.onTop then
				bY = 10001
			elseif b.onBottom then
				bY = -10001
			else
				bY = b.y + (b.baseline or 0)
			end

            return aY < bY

	end)

end

--- Update actor path.
-- Moves an actor to the next point in their movement path.
--
-- @tparam actor actor
-- The actor to update.
--
-- @tparam int dt
-- The delta time since last update.
--
-- @local
function actors:updatePath (actor, dt)

    if (actor.path and #actor.path > 0) then

        -- Check if the actor's speed is set to delay movement.
        -- If no speed is set, we move on every update.
        if (actor.movedelay) then

            -- start a new move delay counter
            if (not actor.movedelaydelta) then
                actor.movedelaydelta = actor.movedelay
            end

            actor.movedelaydelta = actor.movedelaydelta - dt

            -- the delay has not yet passed
            if (actor.movedelaydelta > 0) then
                return
            end

            -- the delay has passed. Reset it and continue.
            actor.movedelaydelta = actor.movedelay

        end

		-- load the next point in the path
        local point = table.remove (actor.path, 1)

        if (point) then

			-- update actor position
            actor.x, actor.y = point.x, point.y

            -- Test if we should calculate actor direction
            actor["direction recalc delay"] = actor["direction recalc delay"] - 1

            if (actor["direction recalc delay"] <= 0) then
                actor["direction recalc delay"] = 5
                actor.direction = self:directionOf (actor.lastx, actor.lasty, actor.x, actor.y)
                actor.lastx, actor.lasty = actor.x, actor.y
            end

        end

		-- the goal is reached
        if (#actor.path == 0) then

			debug:append (actor.name .. " moved complete")
            actor.path = nil
            actor.action = "idle"

			-- notify the moved callback
            events.moved (self, actor)

            -- OBSOLETE: replaced by events.move callback
            slime.callback ("moved", actor)

        end

		-- return movement signal
		return true

    end

end

--- Get direction between two points.
--
-- @tparam int x1
-- Point 1 x
--
-- @tparam int y1
-- Point 1 y
--
-- @tparam int x2
-- Point 2 x
--
-- @tparam int y2
-- Point 2 y
--
-- @return nearest cardinal direction represented by the angle:
-- north south east or west.
--
-- @local
function actors:directionOf (x1, y1, x2, y2)

    -- function angle(x1, y1, x2, y2)
    --     local ang = math.atan2(y2 - y1, x2 - x1) * 180 / math.pi
    --     ang = 90 - ang
    --     if (ang < 0) then ang = ang + 360 end
    --     return ang
    -- end
    --
    -- print('nw', angle(100, 100, 99, 99))
    -- print('n', angle(100, 100, 100, 99))
    -- print('ne', angle(100, 100, 101, 99))
    -- print('sw', angle(100, 100, 99, 101))
    -- print('s', angle(100, 100, 100, 101))
    -- print('se', angle(100, 100, 101, 101))
    -- print('w', angle(100, 100, 99, 100))
    -- print('e', angle(100, 100, 101, 100))
    --
    -- nw	225.0
    -- n	180.0
    -- ne	135.0
    -- sw	315.0
    -- s	0.0
    -- se	45.0
    -- w	270.0
    -- e	90.0
    --
    --        180
    --         N
    --   225   |    135
    --         |
    --  270    |      90
    --  W -----+----- E
    --         |
    --         |
    --   315   |    45
    --         S
    --         0

    -- test if a value is between a range (inclusive)
    local function between(n, a, b)
        return n >= a and n <= b
    end

    -- calculate the angle between the two points
    local ang = math.atan2(y2 - y1, x2 - x1) * 180 / math.pi

    -- map the angle to a 360 degree range
    ang = 90 - ang
    if (ang < 0) then ang = ang + 360 end

    if between(ang, 0, 45) or between(ang, 315, 359) then
        return 'south'
    elseif between(ang, 45, 135) then
        return 'east'
    elseif between(ang, 135, 225) then
        return 'north'
    elseif between(ang, 225, 315) then
        return 'west'
    end

    --return 'south'
end

--- Get an actor.
-- Find an actor by name.
--
-- @tparam string name
-- The name of the actor
--
-- @return the @{actor} or nil if not found.
function actors:get (name)

    for _, actor in ipairs(self.list) do
        if actor.name == name then
            return actor
        end
    end

end

--- Remove an actor.
-- Removes an actor by name
--
-- @tparam string name
-- The name of the actor to remove.
function actors:remove (name)

    for i, actor in ipairs(self.list) do
        if actor.name == name then
            table.remove(self.list, i)
            return true
        end
    end

end

--- Draw actors on screen.
--
-- @local
function actors:draw ()

    for _, actor in ipairs(self.list) do
        if actor.isactor then

			local anim = actor:getAnim()

			if anim then
				local tileset = slime:cache(anim.anim.tileset)
				anim._frames:draw(tileset,
					actor.x - actor.feet[1] + anim._offset.x,
					actor.y - actor.feet[2] + anim._offset.y)
			elseif (actor.image) then
				love.graphics.draw(actor.image,
					actor.x - actor.feet[1],
					actor.y - actor.feet[2])
			else
				love.graphics.rectangle ("fill", actor.x - actor.feet[1], actor.y - actor.feet[2], actor.w, actor.h)
			end

        elseif actor.islayer then
            love.graphics.draw(actor.image, 0, 0)
        end
    end

end

--- Move an actor.
-- Uses path finding when a walkable floor is set, otherwise
-- if no floor is set an actor can walk anywhere.
--
-- @tparam string name
-- Name of the actor to move.
--
-- @tparam int x
-- X-position to move to.
--
-- @tparam int y
-- Y-position to move to.
--
-- @see floors:set
function actors:move (name, x, y)

	-- intercept chaining
	if chains.capturing then
		debug:append (string.format("chaining %s move", name))
		chains:add (actors.move,
			{self, name, x, y},
			-- expires when actor path is empty
			function (parameters)
				local actor = actors:get (parameters[2])
				if not actor or not actor.path then
					return true
				end
			end
			)
		return
	end

	-- test if the actor is on the stage
    local actor = self:get (name)

    if (actor == nil) then
        debug:append ("No actor named " .. name)
        return
    end

	local start = { x = actor.x, y = actor.y }
	local goal = { x = x, y = y }

	-- If the goal is on a solid block find the nearest open point
	if floors:hasMap () then
		if not floors:isWalkable (goal.x, goal.y) then
			goal = floors:findNearestOpenPoint (goal)
		end
	end

	local useCache = false
	local width, height = floors:size ()
	local route = path:find (width, height, start, goal, floors.isWalkable, useCache)

	-- we have a path
	if route then
		actor.clickedX = x
		actor.clickedY = y
		actor.path = route
		-- Default to walking animation
		actor.action = "walk"
		-- Calculate actor direction immediately
		actor.lastx, actor.lasty = actor.x, actor.y
		actor.direction = actors:directionOf (actor.x, actor.y, x, y)
		-- Output debug
		debug:append ("move " .. name .. " to " .. x .. " : " .. y)
	else
		debug:append ("no actor path found")
	end

end

--- Turn an actor.
-- Turn to face a cardinal direction, north south east or west.
--
-- @tparam string name
-- The actor to turn.
--
-- @tparam string direction
-- A cardinal direction: north, south, east or west.
function actors:turn (name, direction)

	-- intercept chaining
	if chains.capturing then
		debug:append (string.format("chaining %s turn %s", name, direction))
		chains:add (actors.turn, {self, name, direction})
		return
	end

    local actor = self:get (name)

    if (actor) then
        actor.direction = direction
    end

end

--- Move an actor.
-- Moves towards another actor, as close as possible as
-- the walkable floor allows.
--
-- @tparam string name
-- Name of the actor to move.
--
-- @tparam string target
-- Name of the actor to move towards.
function actors:moveTowards (name, target)

    local targetActor = self:get (target)

    if (targetActor) then
        self:move (name, targetActor.x, targetActor.y)
    else
        debug:append ("no actor named " .. target)
    end

end

--- Stop and actor.
-- Stop an actor from moving along their movement path.
--
-- @tparam string name
-- Name of the actor.
function actors:stop (name)

    local actor = self:get (name)

    if actor then
        actor.path = nil
    end

end


--~  _                _                                   _
--~ | |__   __ _  ___| | ____ _ _ __ ___  _   _ _ __   __| |___
--~ | '_ \ / _` |/ __| |/ / _` | '__/ _ \| | | | '_ \ / _` / __|
--~ | |_) | (_| | (__|   < (_| | | | (_) | |_| | | | | (_| \__ \
--~ |_.__/ \__,_|\___|_|\_\__, |_|  \___/ \__,_|_| |_|\__,_|___/
--~ 				      |___/

--- Add a background.
-- Called multiple times, is how one creates animated backgrounds,
-- with a delay (in seconds), which when expired,
-- cycles to the next background.
--
-- The image size of each one, has to match the background before it.
-- If no delay is given, the background will draw forever.
--
-- @tparam string path
-- The image path.
--
-- @tparam[opt] int seconds
-- Seconds to display before cycling the background.
function backgrounds:add (path, seconds)

    local image = love.graphics.newImage (path)
    local width, height = image:getDimensions ()

    -- set the background size
    if not self.width or not self.height then
		self.width, self.height = width, height
    end

    -- ensure consistent background sizes
    assert (width == self.width, "backgrounds must have the same size")
    assert (height == self.height, "backgrounds must have the same size")

    table.insert(self.list, {
		image = image,
		seconds = seconds
	})

end

--- Clear all backgrounds.
function backgrounds:clear ()

	-- stores the list of backgrounds
	self.list = { }

	-- the index of the current background
	self.index = 1

	-- background size
	self.width, self.height = nil, nil

end

--- Draw the background.
--
-- @local
function backgrounds:draw ()

    local bg = self.list[self.index]

    if (bg) then
        love.graphics.draw(bg.image, 0, 0)
    end

end

--- Update backgrounds.
-- Tracks background delays and performs their rotation.
--
-- @tparam int dt
-- Delta time since the last update.
--
-- @local
function backgrounds:update (dt)

	-- skip background rotation if there is no more than one
    if not self.list[2] then
        return
    end

    local index = self.index
    local background = self.list[index]
    local timer = self.timer

    if (timer == nil) then
        -- start a new timer
        index = 1
        timer = background.seconds
    else
        timer = timer - dt
        -- this timer has expired
        if (timer < 0) then
            -- move to the next background
            index = (index == #self.list) and 1 or index + 1
            if (self.list[index]) then
                timer = self.list[index].seconds
            end
        end
    end

    self.index = index
    self.timer = timer

end



--~  _
--~ | |__   __ _  __ _ ___
--~ | '_ \ / _` |/ _` / __|
--~ | |_) | (_| | (_| \__ \
--~ |_.__/ \__,_|\__, |___/
--~              |___/

--- Clear all bags.
function bags:clear ()

	self.contents = { }

end

--- Add a thing to a bag.
--
-- @tparam string name
-- Name of the bag to store in.
--
-- @tparam table object
-- TODO: this bag object thing is a bit under-developed.
-- define it's structure.
function bags:add (name, object)

    -- load the image
    if type(object.image) == "string" then
        object.image = love.graphics.newImage(object.image)
    end

    -- create it
    self.contents[name] = self.contents[name] or { }

	-- add the object to it
    table.insert(self.contents[name], object)

    -- notify the callback
    events.bag (self, name)

    -- OBSOLETE: replaced by events.bag
    slime.inventoryChanged (name)

	debug:append (string.format("Added %s to bag", object.name))

end

--- Remove a thing from a bag.
--
-- @tparam string name
-- Name of the bag.
--
-- @tparam string thingName
-- Name of the thing to remove.
function bags:remove (name, thingName)

    local inv = self.contents[name] or { }

	for i, item in pairs(inv) do
		if (item.name == thingName) then
			table.remove(inv, i)
			debug:append (string.format("Removed %s", thingName))
			slime.inventoryChanged (name)
		end
	end

end

--- Test if a bag has a thing.
--
-- @tparam string name
-- Name of bag to search.
--
-- @tparam string thingName
-- Name of thing to find.
function bags:contains (name, thingName)

    local inv = self.contents[name] or { }

    for _, v in pairs(inv) do
        if v.name == thingName then
            return true
        end
    end

end


--       _           _
--   ___| |__   __ _(_)_ __  ___
--  / __| '_ \ / _` | | '_ \/ __|
-- | (__| | | | (_| | | | | \__ \
--  \___|_| |_|\__,_|_|_| |_|___/

-- Provides ways to chain actions to run in sequence

--- Clear all chained actions.
-- Call this to start or append an actor action to build a chain of events.
function chains:clear ()

	-- Allow calling this table like it was a function.
	-- We do this for brevity sake.
	setmetatable (chains, {
		__call = function (self, ...)
			return self:capture (...)
		end
	})

	self.list = { }

	-- when capturing: certain actor functions will queue themselves
	-- to the chain instead of actioning instantly.
	self.capturing = nil

end

--- Begins chain capturing mode.
-- While in this mode, the next call to a slime function
-- will be added to the chain action list instead of executing
-- immediately.
--
-- @tparam[opt] string name
-- Specifying a name allows creating multiple, concurrent chains.
--
-- @tparam[opt] function userFunction
-- User provided function to add to the chain.
--
-- @return The slime instance
--
-- @function chain
-- @see @{chains_example.lua}
function chains:capture (name, userFunction)

	-- catch obsolete usage
	if type (name) == "table" then
		assert (false, "slime:chain is obsolete. use slime.chain()... notation")
	end

	-- use a default chain name if none is provided
	name = name or "default"

	-- fetch the chain from storage
	self.capturing = self.list[name]

	-- create a new chain instead
	if not self.capturing then
		self.capturing = { name = name, actions = { } }
		self.list[name] = self.capturing
		debug:append (string.format ("created chain %q", name))
	end

	-- queue custom function
	if type (userFunction) == "function" then
		self:add (userFunction, { })
		debug:append (string.format("user function chained"))
	end

	-- return the slime instance to allow further action chaining
	return slime

end

--- Add an action to the capturing chain.
--
-- @tparam function func
-- The function to call
--
-- @tparam table parameters
-- The function parameters
--
-- @tparam[opt] function expired
-- Function that returns true when the action
-- has expired, which does so instantly if this parameter
-- is not given.
--
-- @local
function chains:add (func, parameters, expired)

	local command = {
		-- the function to be called
		func = func,
		-- parameters to pass the function
		parameters = parameters,
		-- a function that tests if the command has expired
		expired = expired,
		-- a flag to ensure the function is only called once
		ran = false
	}

	-- queue this command in the capturing chain
	table.insert (self.capturing.actions, command)

	-- release this capture
	self.capturing = nil

end

--- Process chains.
--
-- @tparam int dt
-- Delta time since the last update
--
-- @local
function chains:update (dt)

	-- for each chain
	for key, chain in pairs(self.list) do

		-- the next command in this chain
		local command = chain.actions[1]

		if command then

			-- run the action once only
			if not command.ran then
				--debug:append (string.format("running chain command"))
				command.ran = true
				command.func (unpack (command.parameters))
			end

			-- test if the action expired
			local skipTest = type (command.expired) ~= "function"

			-- remove expired actions from this chain
			if skipTest or command.expired (command.parameters, dt) then
				--debug:append (string.format("chain action expired"))
				table.remove (chain.actions, 1)
			end

		end

	end

end

--- Pause the chain.
--
-- @tparam int seconds
-- Seconds to wait before the next action is run.
function chains:wait (seconds)

	if chains.capturing then

		--debug:append (string.format("waiting %ds", seconds))

		chains:add (chains.wait,

					-- pack parameter twice, the second being
					-- our countdown
					{seconds, seconds},

					-- expires when the countdown reaches zero
					function (p, dt)
						p[2] = p[2] - dt
						return p[2] < 0
					end
					)

	end

end


--                       _
--   _____   _____ _ __ | |_ ___
--  / _ \ \ / / _ \ '_ \| __/ __|
-- |  __/\ V /  __/ | | | |_\__ \
--  \___| \_/ \___|_| |_|\__|___/
--

--- Actor animation looped callback.
--
-- @param self
-- The slime instance
--
-- @tparam actor actor
-- The actor being interacted with
--
-- @tparam string key
-- The animation key that looped
--
-- @tparam int counter
-- The number of times the animation has looped
function events.animation (self, actor, key, counter)

end

--- Bag contents changed callback.
--
-- @param self
-- The slime instance
--
-- @tparam string bag
-- The name of the bag that changed
function events.bag (self, bag)

end

--- Callback when a mouse interaction occurs.
--
-- @param self
-- The slime instance
--
-- @tparam string event
-- The name of the cursor
--
-- @tparam actor actor
-- The actor being interacted with
function events.interact (self, event, actor)

end

--- Actor finished moving callback.
--
-- @param self
-- The slime instance
--
-- @tparam actor actor
-- The actor that moved
function events.moved (self, actor)

end

--- Actor speaking callback.
--
-- @param self
-- The slime instance
--
-- @tparam actor actor
-- The talking actor
--
-- @tparam bool started
-- true if the actor has started talking
--
-- @tparam bool ended
-- true if the actor has stopped talking
function events.speech (self, actor, started, ended)

end


--   ___ _   _ _ __ ___  ___  _ __
--  / __| | | | '__/ __|/ _ \| '__|
-- | (__| |_| | |  \__ \ (_) | |
--  \___|\__,_|_|  |___/\___/|_|
--

--- Custom cursor data
--
-- @table cursor
--
-- @tfield string name
-- Name of the cursor. This gets passed back to the
-- @{events.interact} callback event.
--
-- @tfield image image
-- The cursor image.
--
-- @tfield[opt] quad quad
-- If image is a spritesheet, then quad defines the position
-- in of the cursor in the image.
--
-- @tfield[opt] table hotspot
-- The {x, y} point on the cursor that identifies as the click point.
-- Defaults to the top-left corner if not specified.


--- Clear the custom cursor.
function cursor:clear ()

	self.cursor = nil

end

--- Draw the cursor.
--
-- @local
function cursor:draw ()

	if self.cursor and self.x then
		if self.cursor.quad then
			love.graphics.draw (self.cursor.image, self.cursor.quad, self.x, self.y)
		else
			love.graphics.draw (self.cursor.image, self.x, self.y)
		end
	end

end

--- Get the current cursor name.
--
-- @local
function cursor:getName ()

	if self.cursor then
		return self.cursor.name
	else
		return "interact"
	end

end

--- Set a custom cursor.
--
-- @tparam cursor cursor
-- The cursor data.
function cursor:set (cursor)

	assert (cursor.name, "cursor needs a name")
	assert (cursor.image, "cursor needs an image")

	-- default hotspot to top-left corner
	cursor.hotspot = cursor.hotspot or {x = 0, y = 0}

	self.cursor = cursor

	debug:append (string.format("set cursor %q", cursor.name))

end

function cursor:mousemoved (x, y, dx, dy, istouch)

	-- adjust to scale
	x = math.floor (x / slime.scale)
	y = math.floor (y / slime.scale)

	-- adjust draw position to center around the hotspot
	if self.cursor then
		self.x = x - self.cursor.hotspot.x
		self.y = y - self.cursor.hotspot.y
	else
		self.x, self.y = x, y
	end

end


--        _      _
--     __| | ___| |__  _   _  __ _
--    / _` |/ _ \ '_ \| | | |/ _` |
--   | (_| |  __/ |_) | |_| | (_| |
--    \__,_|\___|_.__/ \__,_|\__, |
--                           |___/
-- Provides helpful debug information while building your game.

--- Clear the debug log
function debug:clear ()

	self.log = { }
	self.enabled = true

	-- debug border
	self.padding = 10
	self.width, self.height = love.graphics.getDimensions ()
	self.width = self.width - (self.padding * 2)
	self.height = self.height - (self.padding * 2)

	-- the alpha for debug outlines
	local alpha = 0.42

	-- define colors for debug outlines
	self.hotspotColor = {1, 1, 0, alpha}
	self.actorColor = {0, 0, 1, alpha}
	self.layerColor = {1, 0, 0, alpha}
	self.textColor = {0, 1, 0, alpha}

	-- the font for printing debug texts
	self.font = love.graphics.newFont (12)

end


--- Append to the log.
--
-- @local
function debug:append (text)

    table.insert(self.log, text)

    -- cull the log
    if (#self.log > 10) then
		table.remove(self.log, 1)
	end

end


--- Draw the debug overlay.
function debug:draw (scale)

	-- draw the debug frame
	love.graphics.setColor (self.textColor)
	love.graphics.rectangle ("line", self.padding, self.padding, self.width, self.height)
	love.graphics.setFont (self.font)
	love.graphics.printf ("SLIME DEBUG", self.padding, self.padding, self.width, "center")

    -- print fps
    love.graphics.print (tostring(love.timer.getFPS()) .. " fps", self.padding, self.padding)

    -- print background info
    if (backgrounds.index and backgrounds.timer) then
        love.graphics.print(
			string.format("background #%d showing for %.1f",
			backgrounds.index, backgrounds.timer), 60, 10)
    end

	-- print log
    for i, n in ipairs(self.log) do
        love.graphics.print (n, self.padding, self.padding * 3 + (16 * i))
    end

	-- draw object outlines to scale
	love.graphics.push ()
	love.graphics.scale (scale)

    -- outline hotspots
	love.graphics.setColor (self.hotspotColor)
    for ihotspot, hotspot in pairs(hotspots.list) do
        love.graphics.rectangle ("line", hotspot.x, hotspot.y, hotspot.w, hotspot.h)
    end

    -- outline actors
    for _, actor in ipairs(actors.list) do
        if actor.isactor then
			love.graphics.setColor (self.actorColor)
            love.graphics.rectangle("line", actor.x - actor.feet[1], actor.y - actor.feet[2], actor.w, actor.h)
            love.graphics.circle("line", actor.x, actor.y, 1, 6)
        elseif actor.islayer then
            -- draw baselines for layers
			love.graphics.setColor (self.layerColor)
            love.graphics.line(0, actor.baseline, self.width, actor.baseline)
        end
    end

    love.graphics.pop ()

end


--~   __ _
--~  / _| | ___   ___  _ __ ___
--~ | |_| |/ _ \ / _ \| '__/ __|
--~ |  _| | (_) | (_) | |  \__ \
--~ |_| |_|\___/ \___/|_|  |___/


--- Clear walkable floors.
function floors:clear ()

	self.walkableMap = nil

end

--- Test if a walkable map is loaded.
--
-- @local
function floors:hasMap ()

	return self.walkableMap ~= nil

end

--- Set a walkable floor.
-- The floor mask defines where actors can walk.
-- Any non-black pixel is walkable.
--
-- @tparam string filename
-- The image mask defining walkable areas.
function floors:set (filename)

	-- intercept chaining
	if chains.capturing then
		chains:add (floors.set, {self, filename})
		return
	end

	self:convert (filename)

end

--- Convert a walkable floor mask.
-- Prepares the mask for use in path finding.
--
-- @tparam string filename
-- The floor map image filename
--
-- @local
function floors:convert (filename)

    -- Converts a walkable image mask into map points.
    local mask = love.image.newImageData(filename)
    local w = mask:getWidth()
    local h = mask:getHeight()

    -- store the size
    self.width, self.height = w, h

    local row = nil
    local r = nil
    local g = nil
    local b = nil
    local a = nil
    self.walkableMap = { }

    -- builds a 2D array of the image size, each index references
    -- a pixel in the mask
    for ih = 1, h - 1 do
        row = { }
        for iw = 1, w - 1 do
            r, g, b, a = mask:getPixel (iw, ih)
            if (r + g + b == 0) then
				-- not walkable
                table.insert(row, false)
            else
				-- walkable
                table.insert(row, true)
            end
        end
        table.insert(self.walkableMap, row)
    end

end

--- Test if a point is walkable.
-- This is the callback used by path finding.
--
-- @tparam int x
-- X-position to test.
--
-- @tparam int y
-- Y-position to test.
--
-- @return true if the position is open to walk
--
-- @local
function floors:isWalkable (x, y)

	if self:hasMap () then
		-- clamp to floor boundary
		x = path:clamp (x, 1, self.width - 1)
		y = path:clamp (y, 1, self.height - 1)
		return self.walkableMap[y][x]
	else
		-- no floor is always walkable
		return true
	end

end

--- Get the size of the floor.
--
-- @local
function floors:size ()

	if self.walkableMap then
		return self.width, self.height
	else
		-- without a floor map, we return the background size
		return backgrounds.width, backgrounds.height
	end

end

--- Get the points of a line.
-- http://www.roguebasin.com/index.php?title=Bresenham%27s_Line_Algorithm#Lua
--
-- @tparam table start
-- {x, y} of the line start.
--
-- @tparam table goal
-- {x, y} of the line end.
--
-- @return table of list of points from start to goal.
--
-- @local
function floors:bresenham (start, goal)

  local linepath = { }
  local x1, y1, x2, y2 = start.x, start.y, goal.x, goal.y
  delta_x = x2 - x1
  ix = delta_x > 0 and 1 or -1
  delta_x = 2 * math.abs(delta_x)

  delta_y = y2 - y1
  iy = delta_y > 0 and 1 or -1
  delta_y = 2 * math.abs(delta_y)

  table.insert(linepath, {["x"] = x1, ["y"] = y1})

  if delta_x >= delta_y then
    error = delta_y - delta_x / 2

    while x1 ~= x2 do
      if (error >= 0) and ((error ~= 0) or (ix > 0)) then
        error = error - delta_x
        y1 = y1 + iy
      end

      error = error + delta_y
      x1 = x1 + ix

      table.insert(linepath, {["x"] = x1, ["y"] = y1})
    end
  else
    error = delta_x - delta_y / 2

    while y1 ~= y2 do
      if (error >= 0) and ((error ~= 0) or (iy > 0)) then
        error = error - delta_y
        x1 = x1 + ix
      end

      error = error + delta_x
      y1 = y1 + iy

      table.insert(linepath, {["x"] = x1, ["y"] = y1})
    end
  end

  return linepath

end

--- Find the nearest open point.
-- Use the bresenham line algorithm to project four lines from the goal:
-- North, south, East and West, and find the first open point on each line.
-- We then choose the point with the shortest distance from the goal.
--
-- @tparam table point
-- {x, y} of the point to reach.
--
-- @local
function floors:findNearestOpenPoint (point)

    -- Get the dimensions of the walkable floor map.
    local width, height = floors:size ()

    -- Define the cardinal direction to test against relative to the point.
    local directions = {
        { ["x"] = point.x, ["y"] = height },    -- S
        { ["x"] = 1, ["y"] = point.y },         -- W
        { ["x"] = point.x, ["y"] = 1 },         -- N
        { ["x"] = width, ["y"] = point.y }      -- E
        }

    -- Stores the four directional points found and their distance.
    local foundPoints = { }

    for idirection, direction in pairs(directions) do
        local goal = point
        local walkTheLine = self:bresenham (direction, goal)
        local continueSearch = true
        while (continueSearch) do
            if (#walkTheLine == 0) then
                continueSearch = false
            else
                goal = table.remove(walkTheLine)
                continueSearch = not self:isWalkable (goal.x, goal.y)
            end
        end
        -- math.sqrt( (x2 - x1)^2 + (y2 - y1)^2 )
        local distance = math.sqrt( (goal.x - point.x)^2 + (goal.y - point.y)^2 )
        table.insert(foundPoints, { ["goal"] = goal, ["distance"] = distance })
    end

    -- Sort the results with shortest distance first
    table.sort(foundPoints, function (a, b) return a.distance < b.distance end )

    -- Return the winning point
    return foundPoints[1].goal

end



--    _           _                   _
--   | |__   ___ | |_ ___ _ __   ___ | |_ ___
--   | '_ \ / _ \| __/ __| '_ \ / _ \| __/ __|
--   | | | | (_) | |_\__ \ |_) | (_) | |_\__ \
--   |_| |_|\___/ \__|___/ .__/ \___/ \__|___/
--                       |_|

--- Clear hotspots.
function hotspots:clear ()

	self.list = { }

end

--- Add a hotspot.
--
-- @tparam string name
-- Name of the hotspot.
--
-- @tparam int x
-- @tparam int y
-- @tparam int w
-- @tparam int h
function hotspots:add (name, x, y, w, h)

    local hotspot = {
        ["name"] = name,
        ["x"] = x,
        ["y"] = y,
        ["w"] = w,
        ["h"] = h
    }

    table.insert(self.list, hotspot)
    return hotspot

end


--    _
--   | | __ _ _   _  ___ _ __ ___
--   | |/ _` | | | |/ _ \ '__/ __|
--   | | (_| | |_| |  __/ |  \__ \
--   |_|\__,_|\__, |\___|_|  |___/
--            |___/
--
-- Layers define areas of the background that actors can walk behind.

--- Add a walk-behind layer.
-- The layer mask is used to cut out a piece of the background, and
-- drawn over other actors to create a walk-behind layer.
--
-- @tparam string background
-- Filename of the background to cut out.
--
-- @tparam string mask
-- Filename of the mask.
--
-- @tparam int baseline
-- The Y-position on the mask that defines the behind/in-front point.
function layers:add (background, mask, baseline)

    local newLayer = {
        ["image"] = self:convertMask (background, mask),
        ["baseline"] = baseline,
        islayer = true
        }

	-- layers are merged with actors so that we can perform
	-- efficient sorting, enabling drawing of actors behind layers.
    table.insert(actors.list, newLayer)

    actors:sort()

end

--- Cut a shape out of an image.
-- All corresponding black pixels from the mask will cut and discard
-- pixels (they become transparent), and only non-black mask pixels
-- preserve the matching source pixels.
--
-- @tparam string source
-- Source image filename.
--
-- @tparam string mask
-- Mask image filename.
--
-- @return the cut out image.
--
-- @local
function layers:convertMask (source, mask)

    -- Returns a copy of the source image with transparent pixels where
    -- the positional pixels in the mask are black.

    local sourceData = love.image.newImageData(source)
    local maskData = love.image.newImageData(mask)

	local sourceW, sourceH = sourceData:getDimensions()
    layerData = love.image.newImageData( sourceW, sourceH )

    -- copy the orignal
    layerData:paste(sourceData, 0, 0, 0, 0, sourceW, sourceH)

    -- map black mask pixels to transparent layer pixels
    layerData:mapPixel( function (x, y, r, g, b, a)
                            r2, g2, b2, a2 = maskData:getPixel(x, y)
                            if (r2 + g2 + b2 == 0) then
                                return 0, 0, 0, 0
                            else
                                return r, g, b, a
                            end
                        end)

    return love.graphics.newImage(layerData)

end


--              _   _
--  _ __   __ _| |_| |__
-- | '_ \ / _` | __| '_ \
-- | |_) | (_| | |_| | | |
-- | .__/ \__,_|\__|_| |_|
-- |_|
--

-- Clear all cached paths
function path:clear ()

    self.cache = nil

end

-- Gets a unique start/goal key
function path:keyOf (start, goal)

    return string.format("%d,%d>%d,%d", start.x, start.y, goal.x, goal.y)

end

-- Returns the cached path
function path:getCached (start, goal)

    if self.cache then
        local key = self:keyOf (start, goal)
        return self.cache[key]
    end

end

-- Saves a path to the cache
function path:saveCached (start, goal, path)

    self.cache = self.cache or { }
    local key = self:keyOf (start, goal)
    self.cache[key] = path

end

--- Distance between two points.
-- This method doesn't bother getting the square root of s, it is faster
-- and it still works for our use.
--
-- @tparam int x1
-- @tparam int y1
-- @tparam int x2
-- @tparam int y2
--
-- @local
function path:distance (x1, y1, x2, y2)

	local dx = x1 - x2
	local dy = y1 - y2
	local s = dx * dx + dy * dy
	return s

end

--- Clamp a value to a range.
--
-- @tparam int x
-- The value to test.
--
-- @tparam int min
-- Minimum value.
--
-- @tparam int max
-- Maximum value.
--
-- @local
function path:clamp (x, min, max)

	return x < min and min or (x > max and max or x)

end

-- Get movement cost.
-- G is the cost from START to this node.
-- H is a heuristic cost, in this case the distance from this node to the goal.
-- Returns F, the sum of G and H.
function path:calculateScore (previous, node, goal)

    local G = previous.score + 1
    local H = self:distance (node.x, node.y, goal.x, goal.y)
    return G + H, G, H

end

--- Test an item is in a list.
--
-- @tparam table list
-- @table item
--
-- @local
function path:listContains (list, item)
    for _, test in ipairs(list) do
        if test.x == item.x and test.y == item.y then
            return true
        end
    end
    return false
end

--- Get an item in a list.
--
-- @tparam table list
--
-- @tparam table item
--
-- @local
function path:listItem (list, item)
    for _, test in ipairs(list) do
        if test.x == item.x and test.y == item.y then
            return test
        end
    end
end

--- Get adjacent map points.
--
-- @tparam int width
--
--
-- @tparam int height
--
--
-- @tparam table point
-- {x, y} point to test.
--
-- @tparam function openTest
-- Function that should return if a point is open.
--
-- @return table of points adjacent to the point.
--
-- @local
function path:getAdjacent (width, height, point, openTest)

    local result = { }

    local positions = {
        { x = 0, y = -1 },  -- top
        { x = -1, y = 0 },  -- left
        { x = 0, y = 1 },   -- bottom
        { x = 1, y = 0 },   -- right
        -- include diagonal movements
        { x = -1, y = -1 },   -- top left
        { x = 1, y = -1 },   -- top right
        { x = -1, y = 1 },   -- bot left
        { x = 1, y = 1 },   -- bot right
    }

    for _, position in ipairs(positions) do
        local px = self:clamp (point.x + position.x, 1, width)
        local py = self:clamp (point.y + position.y, 1, height)
        local value = openTest (floors, px, py)
        if value then
            table.insert( result, { x = px, y = py  } )
        end
    end

    return result

end


--- Find a walkable path.
--
-- @tparam int width
-- Width of the floor.
--
-- @tparam int height
-- Height of the floor.
--
-- @tparam table start
-- {x, y} of the starting point.
--
-- @tparam table goal
-- {x, y} of the goal to reach.
--
-- @tparam function openTest
-- Called when querying if a point is open.
--
-- @tparam bool useCache
-- Cache paths for future re-use.
-- Caching is not used at the moment.
--
-- @return the path from start to goal, or false if no path exists.
--
-- @local
function path:find (width, height, start, goal, openTest, useCache)

    if useCache then
        local cachedPath = self:getCached (start, goal)
        if cachedPath then
            return cachedPath
        end
    end

    local success = false
    local open = { }
    local closed = { }

    start.score = 0
    start.G = 0
    start.H = self:distance (start.x, start.y, goal.x, goal.y)
    start.parent = { x = 0, y = 0 }
    table.insert(open, start)

    while not success and #open > 0 do

        -- sort by score: high to low
        table.sort(open, function(a, b) return a.score > b.score end)

        local current = table.remove(open)

        table.insert(closed, current)

        success = self:listContains (closed, goal)

        if not success then

            local adjacentList = self:getAdjacent (width, height, current, openTest)

            for _, adjacent in ipairs(adjacentList) do

                if not self:listContains (closed, adjacent) then

                    if not self:listContains (open, adjacent) then

                        adjacent.score = self:calculateScore (current, adjacent, goal)
                        adjacent.parent = current
                        table.insert(open, adjacent)

                    end

                end

            end

        end

    end

    if not success then
        return false
    end

    -- traverse the parents from the last point to get the path
    local node = self:listItem (closed, closed[#closed])
    local path = { }

    while node do

        table.insert(path, 1, { x = node.x, y = node.y } )
        node = self:listItem (closed, node.parent)

    end

    self:saveCached (start, goal, path)

    -- reverse the closed list to get the solution
    return path

end



--                           _
--  ___ _ __   ___  ___  ___| |__
-- / __| '_ \ / _ \/ _ \/ __| '_ \
-- \__ \ |_) |  __/  __/ (__| | | |
-- |___/ .__/ \___|\___|\___|_| |_|
--     |_|


--- Clear queued speeches.
function speech:clear ()

	self.queue = { }

end


--- Make an actor talk.
-- Call this multiple times to queue speech.
--
-- @tparam string name
-- Name of the actor.
--
-- @tparam string text
-- The words to display.
--
-- @tparam[opt=3] int seconds
-- Seconds to display the words.
function speech:say (name, text, seconds)

	-- default seconds
	seconds = seconds or 3

	-- intercept chaining
	if chains.capturing then
		debug:append (string.format("chaining %s say", name))
		chains:add (speech.say,
					{self, name, text, seconds},
					-- expires when actor is not talking
					function (parameters)
						return not speech:isTalking (parameters[2])
					end
					)
		return
	end

    local newSpeech = {
        ["actor"] = actors:get (name),
        ["text"] = text,
        ["time"] = seconds
        }

    if (not newSpeech.actor) then
        debug:append ("Speech failed: No actor named " .. name)
        return
    end

    table.insert(self.queue, newSpeech)

end


--- Test if someone is talking.
--
-- @tparam[opt] string actor
-- The actor to test against.
-- If not given, any talking actor is tested.
--
-- @return true if any actor, or the specified actor is talking.
function speech:isTalking (actor)

	if type (actor) == "string" then
		actor = actors:get (actor)
	end

	if actor then
		-- if a specific actor is talking
		return self.queue[1] and self.queue[1].actor.name == actor
	else
		-- if any actor is talking
		return (#self.queue > 0)
	end

end


--- Skip the current spoken line.
-- Jumps to the next line in the queue.
function speech:skip ()

    local speech = self.queue[1]

    if (speech) then

		-- remove the line
        table.remove(self.queue, 1)

        -- restore the actor animation to idle
        speech.actor.action = "idle"

        -- clear the current spoken line
        self.currentLine = nil

        -- notify speech ended event
        events.speech (slime, speech.actor, false, true)

    end

end


--- Update speech.
--
-- @tparam int dt
-- Delta time since the last update.
--
-- @local
function speech:update (dt)

    if (#self.queue > 0) then

        local speech = self.queue[1]
        speech.time = speech.time - dt

        -- notify speech started event
        if self.currentLine ~= speech.text then
			self.currentLine = speech.text
			events.speech (slime, speech.actor, true)
		end

        if (speech.time < 0) then
            self:skip ()
        else
            speech.actor.action = "talk"
            if not settings["walk and talk"] then
                speech.actor.path = nil
            end
        end

    end

end


--- Draw speech.
--
-- @local
function speech:draw ()

    if (#self.queue > 0) then
        local spc = self.queue[1]
        if settings["builtin text"] then

            -- Store the original color
            local r, g, b, a = love.graphics.getColor()

            local y = settings["speech position"]
            local w = love.graphics.getWidth() / scale

            love.graphics.setFont(settings["speech font"])

            -- Black outline
            love.graphics.setColor({0, 0, 0, 255})
            love.graphics.printf(spc.text, 1, y+1, w, "center")

            love.graphics.setColor(spc.actor.speechcolor)
            love.graphics.printf(spc.text, 0, y, w, "center")

            -- Restore original color
            love.graphics.setColor(r, g, b, a)

        else
            self:onDrawSpeechCallback(spc.actor.x, spc.actor.y,
                spc.actor.speechcolor, spc.text)
        end
    end

end


--      _ _
--  ___| (_)_ __ ___   ___
-- / __| | | '_ ` _ \ / _ \
-- \__ \ | | | | | | |  __/
-- |___/_|_|_| |_| |_|\___|
--


--- Clear the room.
-- Call this when setting up a room.
function slime:clear ()

	self.scale = 1
    actors:clear ()
    backgrounds:clear ()
    chains:clear ()
	cursor:clear ()
    debug:clear ()
    floors:clear ()
    hotspots:clear ()
    speech:clear ()
    self.statusText = nil

end

--- Reset slime.
-- Clears everything, even bags and settings.
-- Call this when starting a new game.
function slime:reset ()

	self:clear ()
	bags:clear ()
	settings:clear ()

end

--- Update the game.
--
-- @tparam int dt
-- Delta time since the last update.
function slime:update (dt)

	chains:update (dt)
    backgrounds:update (dt)
	actors:update (dt)
	speech:update (dt)

end

--- Draw the room.
--
-- @tparam[opt=1] int scale
-- Draw at the given scale.
function slime:draw (scale)

    self.scale = scale or 1

    -- reset draw color
    love.graphics.setColor (1, 1, 1)

    backgrounds:draw ()
	actors:draw ()

    -- Bag Buttons
	-- OBSOLETE IN FUTURE
    for counter, button in pairs(self.bagButtons) do
        love.graphics.draw (button.image, button.x, button.y)
    end

    -- status text
    if (self.statusText) then
        local y = settings["status position"]
        local w = love.graphics.getWidth() / self.scale
        love.graphics.setFont(settings["status font"])
        -- Outline
        love.graphics.setColor({0, 0, 0, 255})
        love.graphics.printf(self.statusText, 1, y+1, w, "center")
        love.graphics.setColor({255, 255, 255, 255})
        love.graphics.printf(self.statusText, 0, y, w, "center")
    end

	speech:draw ()
	cursor:draw ()

end

function slime:mousemoved (x, y, dx, dy, istouch)

	cursor:mousemoved (x, y, dx, dy, istouch)

end

--- Get objects at a point.
-- Includes actors, hotspots.
--
-- @tparam int x
-- X-position to test.
--
-- @tparam int y
-- Y-position to test.
--
-- @return table of objects.
function slime:getObjects (x, y)

    local objects = { }

    for _, actor in pairs(actors.list) do
        if actor.isactor and
            (x >= actor.x - actor.feet[1]
            and x <= actor.x - actor.feet[1] + actor.w)
        and (y >= actor.y - actor.feet[2]
            and y <= actor.y - actor.feet[2] + actor.h) then
            table.insert(objects, actor)
        end
    end

	-- TODO convert to hotspots:getAt()
    for ihotspot, hotspot in pairs(hotspots.list) do
        if (x >= hotspot.x and x <= hotspot.x + hotspot.w) and
            (y >= hotspot.y and y <= hotspot.y + hotspot.h) then
            table.insert(objects, hotspot)
        end
    end

    for ihotspot, hotspot in pairs(self.bagButtons) do
        if (x >= hotspot.x and x <= hotspot.x + hotspot.w) and
            (y >= hotspot.y and y <= hotspot.y + hotspot.h) then
            table.insert(objects, hotspot)
        end
    end

    if (#objects == 0) then
        return nil
    else
        return objects
    end

end

--- Interact with objects.
-- This triggers the @{events.interact} callback for every
-- object that is interacted with, passing the current cursor name.
--
-- @tparam int x
-- X-position to interact with.
--
-- @tparam int y
-- Y-position to interact with.
function slime:interact (x, y)

    local objects = self:getObjects(x, y)
    if (not objects) then return end

	local cursorname = cursor:getName ()

    for i, object in pairs(objects) do
		debug:append (cursorname .. " on " .. object.name)

		-- notify the interact callback
		events.interact (self, cursorname, object)

		-- OBSOLETE: slime.callback replaced by events
        slime.callback (cursorname, object)
    end

    return true

end


--~           _   _   _
--~  ___  ___| |_| |_(_)_ __   __ _ ___
--~ / __|/ _ \ __| __| | '_ \ / _` / __|
--~ \__ \  __/ |_| |_| | | | | (_| \__ \
--~ |___/\___|\__|\__|_|_| |_|\__, |___/
                          --~ |___/

--- Clear slime settings.
function settings:clear ()

	-- Let slime handle displaying of speech text on screen,
	-- if false the onDrawSpeechCallback function is called.
    self["builtin text"] = true

	-- The y-position to display status text
    self["status position"] = 70

    self["status font"] = love.graphics.newFont(12)

    -- The y-position to display speech text
    self["speech position"] = 0

    self["speech font"] = love.graphics.newFont(10)

    -- actors stop walking when they speak
    self["walk and talk"] = false

end


--~        _               _      _
--~   ___ | |__  ___  ___ | | ___| |_ ___
--~  / _ \| '_ \/ __|/ _ \| |/ _ \ __/ _ \
--~ | (_) | |_) \__ \ (_) | |  __/ ||  __/
--~  \___/|_.__/|___/\___/|_|\___|\__\___|
--~


function slime.callback (event, object)
end

function slime.animationLooped (actor, key, counter)
end

function slime.onDrawSpeechCallback(actorX, actorY, speechcolor, words)
end

function slime.background (self, ...)

	backgrounds:add (...)

end

function slime.setCursor (self, name, image, hotspot, quad)

	print ("slime.setCursor will be obsoleted, use slime.cursor:set()")

	local data = {
		name = name,
		image = image,
		quad = quad,
		hotspot = hotspot
	}
	cursor:set (data)

end

function slime.loadCursors (self, path, w, h, names, hotspots)

	print ("slime.loadCursors will be obsoleted, use slime.cursor:set()")
    cursor.names = names or {}
    cursor.hotspots = hotspots or {}
    cursor.image = love.graphics.newImage(path)
    cursor.quads = {}
    cursor.current = 1

    local imgwidth, imgheight = cursor.image:getDimensions()

    local totalImages = imgwidth / w

    for x = 1, totalImages do

        local quad = love.graphics.newQuad((x - 1) * w, 0,
            w, h, imgwidth, imgheight)

        table.insert(cursor.quads, quad)

    end

end

function slime.useCursor (self, index)
	--print ("slime.useCursor will be obsoleted, use slime.cursor:set()")
    cursor.current = index
end

function slime.getCursor (self)
	print ("slime.getCursor will be obsoleted")
    return self.cursor.current
end

function slime.floor (self, filename)

	print ("slime.floors will be obsoleted, use slime.floors:set()")
	floors:set (filename)

end

function slime.actor (self, ...)

	print ("slime.actor will be obsoleted, use slime.actors:add()")
	return actors:add (...)

end

function slime.getActor (self, ...)

	-- OBSOLETE IN FUTURE
	print ("slime.getActor will be obsoleted, use slime.actors:get()")
	return actors:get (...)

end

function slime.removeActor (self, ...)

	-- OBSOLETE IN FUTURE
	print ("slime.removeActor will be obsoleted, use slime.actors:remove()")
	return actors:remove (...)

end

function slime.defineTileset (self, tileset, size)

	print ("slime.defineTileset will be obsoleted.")
    local actor = self

    -- cache tileset image to save loading duplicate images
    slime:cache(tileset)

    -- default actor hotspot to centered at the base of the image
    actor.w = size.w
    actor.h = size.h
    actor.feet = { size.w / 2, size.h }

    return {
        actor = actor,
        tileset = tileset,
        size = size,
        define = slime.defineAnimation
        }

end

function slime.defineAnimation (self, key)

    local pack = {
        anim = self,
        frames = slime.defineFrames,
        delays = slime.defineDelays,
        sounds = slime.defineSounds,
        offset = slime.defineOffset,
        flip = slime.defineFlip,
        key = key,
        loopcounter = 0,
        _sounds = {},
        _offset = {x=0, y=0}
    }

    return pack

end

function slime.defineFrames (self, frames)
    self.framesDefinition = frames
    return self
end

function slime.defineDelays (self, delays)

    local image = slime:cache(self.anim.tileset)

    local g = anim8.newGrid(
        self.anim.size.w,
        self.anim.size.h,
        image:getWidth(),
        image:getHeight())

    self._frames = anim8.newAnimation(
        g(unpack(self.framesDefinition)),
        delays or 1,
        slime.internalAnimationLoop)

    -- circular ref back
    self._frames.pack = self

    -- store this animation object in the actor's animation table
    self.anim.actor.animations[self.key] = self

    return self
end

function slime.defineSounds (self, sounds)
    sounds = sounds or {}
    for i, v in pairs(sounds) do
        if type(v) == "string" then
            sounds[i] = love.audio.newSource(v, "static")
        end
    end
    self._sounds = sounds
    return self
end

function slime.defineOffset (self, x, y)
    self._offset = {x=x, y=y}
    return self
end

function slime.defineFlip (self)
    self._frames:flipH()
    return self
end

function slime.setAnimation (self, name, key)

	-- intercept chaining
	if chains.capturing then
		chains:add (slime.setAnimation, {self, name, key})
		return
	end

    local actor = self:getActor(name)

    if (not actor) then
        debug:append ("Set animation failed: no actor named " .. name)
    else
        actor.customAnimationKey = key
        -- reset the animation counter
        local anim = actor:getAnim()
        if anim then
            anim.loopcounter = 0
            -- Recalculate the actor's base offset
            local size = anim.anim.size
            actor.w = size.w
            actor.h = size.h
            actor.base = { size.w / 2, size.h }
        end
    end

end

function slime.animationDuration(self, name, key)
    local a = self:getActor(name)
    if a then
        local anim = a.animations[key]
        if anim then
            return anim._frames.totalDuration
        end
    end
    return 0
end

function slime.setImage (self, image)

    local actor = self

    if (not actor) then
        debug:append ("slime.Image method should be called from an actor instance")
    else
        image = love.graphics.newImage(image)
        actor.image = image
        actor.w = image:getWidth()
        actor.h = image:getHeight()
        actor.feet = { actor.w/2, actor.h }
    end

end

function slime.turnActor (self, ...)

	-- OBSOLETE IN FUTURE
	print ("slime.turnActor will be obsoleted, use slime.actors:turn()")
	actors:turn (...)

end

function slime.moveActor (self, ...)

	-- OBSOLETE IN FUTURE
	print ("slime.moveActor will be obsoleted, use slime.actors:move()")
	return actors:move (...)

end

function slime.moveActorTo (self, ...)

	-- OBSOLETE IN FUTURE
	print ("slime.moveActorTo will be obsoleted, use slime.actors:moveTowards()")
	actors:moveTowards (...)

end

function slime.stopActor (self, ...)

	-- OBSOLETE IN FUTURE
	print ("slime.stopActor will be obsoleted, use slime.actors:stop()")
	actors:stop (...)

end

function slime.say (self, name, text)

	print ("slime.say will be obsoleted, use slime.speech:say()")
	speech:say (name, text)

end

function slime.someoneTalking (self)

	print ("slime.someoneTalking will be obsoleted, use slime.speech:isTalking()")
	return speech:isTalking ()

end

function slime.actorTalking (self, actor)

	print ("slime.actorTalking will be obsoleted, use slime.speech:isTalking()")
	return speech:isTalking (actor)

end

function slime.skipSpeech (self)

	print ("slime.skipSpeech will be obsoleted, use slime.speech:skip()")
	speech:skip ()

end

function slime.layer (self, ...)

	print ("slime.layer will be obsoleted, use slime.layers:add()")
	layers:add (...)

end

function slime:createLayer (source, mask)

	print ("slime.layer will be obsoleted, use slime.layers:add()")
	return layers:convertMask (source, mask)

end

function slime.hotspot(self, ...)

	print ("slime.hotspot will be obsoleted, use slime.hotspots:add()")
	hotspots:add (...)

end

slime.bagButtons = { }

function slime.inventoryChanged ( )
	-- OBSOLETE IN FUTURE
	-- replace with the future room structure
end

function slime.bagInsert (self, ...)

	print ("slime.bagInsert will be obsoleted, use slime.bags:add()")
	bags:add (...)

end

function slime.bagContents (self, bag)

	print ("slime.bagContents will be obsoleted, use slime.bags.contents[<key>]")
    return bags.contents[bag] or { }

end

function slime.bagContains (self, ...)
	print ("slime.bagContains will be obsoleted, use slime.bags:contains()")
	return bags:contains (...)
end

function slime.bagRemove (self, ...)

	print ("slime.bagRemove will be obsoleted, use slime.bags:remove()")
	bags:remove (...)

end

function slime.bagButton (self, name, image, x, y)

	print ("slime.bagButton will be obsoleted")

    if type(image) == "string" then image = love.graphics.newImage(image) end

    local w, h = image:getDimensions ()

    table.insert(self.bagButtons, {
        ["name"] = name,
        ["image"] = image,
        ["x"] = x,
        ["y"] = y,
        ["w"] = w,
        ["h"] = h,
        ["data"] = data
    })

end

function slime.status (self, text)

	--print ("slime.status will be obsoleted")
    self.statusText = text

end


slime.tilesets = {}

function slime.internalAnimationLoop (frames, counter)
    local pack = frames.pack
    pack.loopcounter = pack.loopcounter + 1
    if pack.loopcounter > 255 then
        pack.loopcounter = 0
    end

	-- notify the animation callback
    events.animation (slime, pack.anim.actor.name, pack.key, pack.loopcounter)

    -- OBSOLETE: replaced by events.animation
    slime.animationLooped (pack.anim.actor.name, pack.key, pack.loopcounter)
end

-- Cache a tileset image in slime, or return an already cached one.
function slime.cache (self, path)

    -- cache tileset image to save loading duplicate images
    local image = self.tilesets[path]

    if not image then
        image = love.graphics.newImage(path)
        self.tilesets[path] = image
    end

    return image

end


                            --~ _
--~   _____  ___ __   ___  _ __| |_
--~  / _ \ \/ / '_ \ / _ \| '__| __|
--~ |  __/>  <| |_) | (_) | |  | |_
--~  \___/_/\_\ .__/ \___/|_|   \__|
          --~ |_|


slime.actors = actors
slime.backgrounds = backgrounds
slime.bags = bags
slime.chain = chains
slime.cursor = cursor
slime.debug = debug
slime.events = events
slime.floors = floors
slime.layers = layers
slime.settings = settings
slime.speech = speech
slime.wait = chains.wait
return slime
