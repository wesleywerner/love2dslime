slime = require ("slime")

function love.load()
    
    -- nearest image interpolation
    love.graphics.setDefaultFilter("nearest", "nearest", 1)
    
    local background = love.graphics.newImage("background.png")
    local layermask = love.graphics.newImage("layer-mask.png")
    local walkzone = love.graphics.newImage("walk-door-open-mask.png")
    
    slime.background(background, 0, 0)
    slime.layer(background, layermask, 0, 0, 50)
    slime.walkable(walkzone)

    local ego = slime.actor("ego", 70, 50)
    ego.movedelay = 0.05
    
    ego:animation ( "idle east",            -- animation key
                    "green-monster.png",    -- tileset file name
                    12, 12,                 -- tile width & height
                    {'3-2', 1},             -- frames
                    {3, 0.2}                -- delays
                    )
    ego:animation ( "walk east",            -- animation key
                    "green-monster.png",    -- tileset file name
                    12, 12,                 -- tile width & height
                    {'3-6', 1},             -- frames
                    0.2                     -- delays
                    )
    
end

function love.draw()

    -- scale the graphics larger to see our pixel art better.
    love.graphics.push()
    love.graphics.scale(4, 4)
    slime.draw()
    love.graphics.pop()
    
    -- Display debug info.
    -- This only works if slime.debug["enabled"] == true
    slime.debugdraw()

end

function love.update(dt)
    
    slime.update (dt)

end

function love.keypressed( key, isrepeat )
    if key == "escape" then
        love.event.quit()
    end
    if key == "r" then
        slime.reset()
    end
    if key == "tab" then
        slime.debug.enabled = not slime.debug.enabled and true or false
    end
end

function love.mousepressed(x, y, button)
    if button == "l" then
        -- Adjust for scale
        x = math.floor(x / 4)
        y = math.floor(y / 4)
        slime.moveActor("ego", x, y)
    end
end
