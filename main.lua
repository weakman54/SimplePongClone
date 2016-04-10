--[[
Simple Love2d Game
made by Erik Wallin
]]--

-- TODO:
--  Remove gameplay dependencies on windowsize
--  Improve fullscreen
--  Add menu system
--      Settings
--  Add friction to ball, and figure out a good way to combine two friction factors (ball and paddle)
--      Put friction_factor into the objects, not globally
--


-- Libs
HC = require 'HC'
vector = require "hump.vector"


-- Constants
Font_Size = 25

Width, Height = love.graphics.getWidth(), love.graphics.getHeight()

Paddle_Width, Paddle_Height = 20, 120
Paddle_Acc = vector(30, 30) -- px/s/s?
Paddle_Max_Speed = 800 
Paddle_Edge_Offset = 20
Paddle_Dampening_Factor = 0.9 -- How much to modify paddle speed each frame, in percent
                               -- (f<1 - reduce speed each frame, f=1 - "frictionless", f>1 - accelerates each frame)
Paddle_Mass = 100              -- mass units?


Ball_Radius = 10
Ball_Circumference = 2*math.pi*Ball_Radius
Ball_Speed = 200
Ball_Mass = Paddle_Mass/2

Spin_Friction_Factor = 0.4                -- How much "friction" a paddle has,
                                        -- translates to how much of it's speed it transfers to the ball as spin
Wall_Friction = Spin_Friction_Factor   -- How much friction a wall has, translates to how much horizontal speed
                                        -- the ball gets from its spin when hitting a wall

Spin_Air_Drag = 0.006                     -- How much of the balls spin that translates into deflection

-- Debug
Debug_Flags = {
    Ball_Collision_Color = false,       -- Color ball if colliding, TODO: re-implement if needed
    Draw_Center_Lines = false,          -- Draw a centered crosshair
    Draw_Collision_Vectors = false,      -- Draw vectors as lines for collisions, TODO: implement if needed
    Collision_Vector_Scale = 4,         -- How much to scale the Collision vectors for visibility
    Print_Paddle_Velocities = false,    -- Prints the velocities of the paddles
    Draw_Spin_Line = true,              -- Draws a line on the ball, representing spin
    Print_Ball_Spin = false,             -- Print amount of spin on screen
    Mouse_Ball_Direction = true         -- Click with the mouse to set a new direction for the ball
}


-- Functions
function clamp(val, lower, upper)
    assert(val and lower and upper, "Please supply all values to clamp")
    if lower > upper then lower, upper = upper, lower end -- swap if boundaries supplied the wrong way
    return math.max(lower, math.min(upper, val))
end

function round(num)
    if num<0 then x=-.5 else x=.5 end
    return math.modf(num+x)
end



function love.load(arg)
    ---------- Initialize stuff: -----------------------
    math.randomseed(os.time())
    love.graphics.setNewFont(Font_Size)

    
    ----------- Objects: ---------------------------
    ---- Paddles: ----
    paddles = {{}, {}}
    
    -- controls
    paddles[1].up = "w"
    paddles[1].down = "s"

    paddles[2].up = "i"
    paddles[2].down = "k"

    -- Starting positions
    paddles[1].pos = vector(0     + Paddle_Edge_Offset, Height/2)
    paddles[2].pos = vector(Width - Paddle_Edge_Offset, Height/2)
    
    for i, paddle in ipairs(paddles) do
        paddle.vel = vector(0, 0)
        paddle.acc = Paddle_Acc
        paddle.maxSpeed = Paddle_Max_Speed

        paddle.mass = Paddle_Mass

        paddle.width = Paddle_Width
        paddle.height = Paddle_Height

        paddle.points = 0
        
        paddle.cRect = HC.rectangle(paddle.pos.x, paddle.pos.y, paddle.width, paddle.height)
    end



    ---- Ball: ---
    ball = {
        pos = vector(Width/2,
                     Height/2),
        vel = vector(0, 0),
        speed = Ball_Speed, -- px/s?
        radius = Ball_Radius,
        collide = false,
        spin = 0,            -- rad/s?
        edgeSpeed = 0,
        mass = Ball_Mass,
        dbgAngle = 0,
        dbgSpinV = vector(Ball_Radius, 0)
    }
    ball.cCircle = HC.circle(ball.pos.x, ball.pos.y, ball.radius)

    function ball:setAng(angle)
        self.vel.x = 1
        self.vel.y = 0
        self.vel:rotateInplace(angle)
        self.vel = ball.vel*ball.speed
    end

    ball:setAng(math.pi+0.1) -- Init for debug TODO: can probably put this somehere better later



    ---- Wall Collider Rects ----
    local w, h = Width, Height
    wallRects = {
        top    = HC.rectangle(-200, -200,    w+400, 200),
        bottom = HC.rectangle(-200,    h,    w+400, 200),
        right  = HC.rectangle(w,       0,      200, h  ),
        left   = HC.rectangle(-200,    0,      200, h  ),
    }
end



function love.keypressed(key)
   if key == "escape" then
      love.event.quit()
   end
   if key == "f" then
      love.window.setFullscreen(not love.window.getFullscreen())
   end
end



function love.update(dt)
    if Debug_Flags.Mouse_Ball_Direction then
        local down = love.mouse.isDown(1)
        if down then
            local mousePV = vector(love.mouse.getPosition())
            local dirV = mousePV-ball.pos
            ball:setAng(dirV:angleTo())
        end

        local down = love.mouse.isDown(2)
        if down then
            local mousePV = vector(love.mouse.getPosition())
            local dirV = mousePV-ball.pos
            ball.vel = dirV
        end
    end

    ---------- Update Ball -------------------
    -- Position and hitbox ----
    ball.pos.x = ball.pos.x + ball.vel.x*dt
    ball.pos.y = ball.pos.y + ball.vel.y*dt
    ball.cCircle:moveTo(ball.pos.x, ball.pos.y)

    -- Spin deflection
    local deflection = ball.spin*Spin_Air_Drag

    -- ball.spin = ball.spin - deflection
    ball.vel:rotateInplace(deflection*dt)

   -- ball.edgeSpeed = (ball.spin/math.pi*2)*Ball_Circumference


    -- DEBUG spinV
    ball.dbgSpinV:rotateInplace(ball.spin*dt)


    -- Ball Collision ----
    for shape, delta in pairs(HC.collisions(ball.cCircle)) do
        deltaV = vector(delta.x, delta.y)
        normDV = deltaV:normalized()

        -- Move ball out of collision zone
        ball.pos = ball.pos + deltaV
    
        -- Goal detection ----
        -- TODO: reset ball? make sure to remember to move both graphics and collision
        if shape == wallRects.right then
            paddles[1].points = paddles[1].points + 1
        elseif shape == wallRects.left then
            paddles[2].points = paddles[2].points + 1
        end
        
        -- simple bounce
        ball.vel = ball.vel:mirrorOn(deltaV)*-1

        if shape == wallRects.top or shape == wallRects.bottom then
            -- transferSpeed = paddle.vel.y*Spin_Friction_Factor*-normDV.x
            local transferSpeed = ball.edgeSpeed*Wall_Friction
            ball.edgeSpeed = ball.edgeSpeed - transferSpeed
            ball.spin = (ball.edgeSpeed/Ball_Circumference) * math.pi*2

            ball.vel.x = ball.vel.x - transferSpeed*normDV.y*0.5
        end

        
        -- Paddle collision
        if shape == paddles[1].cRect or shape == paddles[2].cRect then
            -- get which paddle we collided with
            local paddle = (shape == paddles[1].cRect) and paddles[1] or paddles[2]

            -- Directional Bounce for paddles:
            -- Get Vectorpositions to the center of the shapes
            local paddleCV = vector(shape:center())
            local ballCV = vector(ball.cCircle:center())

            -- get vector from rect to ball Center
            
            local dir = ballCV-paddleCV 
            dir:normalizeInplace()
            dir.x = dir.x *1.4
            dir.y = dir.y * 0.4
            ball.vel = dir * ball.vel:len()*1.1 -- Increase speed slightly TODO: remove magic number


            local transferSpeed = paddle.vel.y*Spin_Friction_Factor*-normDV.x -- NOTE: norm(deltaV.x) is here to make the transferred speed dependent on collison angle, including which side it hits
            ball.edgeSpeed = ball.edgeSpeed + transferSpeed

            ball.spin = (ball.edgeSpeed/Ball_Circumference) * math.pi*2 -- NOTE: negating paddle velocity depending on which side the ball hits on
            
            paddle.vel.y = paddle.vel.y - transferSpeed*0.5




            if Debug_Flags.Draw_Collision_Vectors then
                _, _, bboxX2 = shape:bbox()
                print(bboxX2, deltaV)
                local dbgV = deltaV*Debug_Flags.Collision_Vector_Scale
                sepLine = {
                    x1 = ball.pos.x,
                    y1 = ball.pos.y,
                    x2 = ball.pos.x + dbgV.x,
                    y2 = ball.pos.y + dbgV.y,
                }
            end
        end
    end -- Ball Collision



    ------------- Update Paddles: -----------------------
    for i, paddle in ipairs(paddles) do
         -- Read keyboard and accelerate paddles ----
        if love.keyboard.isDown(paddle.down) then
            if paddle.vel.y < paddle.maxSpeed*0.5 then
                paddle.vel.y = paddle.maxSpeed*0.5
            end
            paddle.vel.y = clamp(paddle.vel.y + paddle.acc.y, -paddle.maxSpeed, paddle.maxSpeed)
        elseif love.keyboard.isDown(paddle.up) then
            if paddle.vel.y > -paddle.maxSpeed*0.5 then
                paddle.vel.y = -paddle.maxSpeed*0.5
            end
            paddle.vel.y = clamp(paddle.vel.y - paddle.acc.y, -paddle.maxSpeed, paddle.maxSpeed)
        else
            paddle.vel.y = math.modf(paddle.vel.y*Paddle_Dampening_Factor) -- Use modf to "round toward 0", to avoid extremely small fractional velocities
        end

        -- Handle paddle collisions ----
        for shape, delta in pairs(HC.collisions(paddle.cRect)) do
            deltaV = vector(delta.x, delta.y)
            
            if shape == wallRects.top or shape == wallRects.bottom then
                -- Move paddle out of collision zone
                paddle.pos = paddle.pos + deltaV

                -- flip vel
                paddle.vel = paddle.vel*-1
            end
        end

        -- Paddle position and hitbox: ----
        paddle.pos = paddle.pos + paddle.vel*dt

        paddle.cRect:moveTo(paddle.pos.x, paddle.pos.y)
    end  
end



function love.draw(dt)
    -- Reset color
    love.graphics.setColor(255, 255, 255, 255)


    -- Draw paddles
    for i, paddle in ipairs(paddles) do
         love.graphics.rectangle("fill", paddle.pos.x-paddle.width/2, paddle.pos.y-paddle.height/2, paddle.width, paddle.height)
    end


    -- Draw score:
    love.graphics.print(paddles[1].points, Width/4, 50)
    love.graphics.print(paddles[2].points, (Width/4)*3, 50)


    -- Draw Ball:
    if Debug_Flags.Ball_Collision_Color then
        -- Color ball when colliding
        if ball.collide then
            love.graphics.setColor(255, 0, 0, 255)
        else
            love.graphics.setColor(255, 255, 255, 255)
        end
    end

    love.graphics.circle("fill", ball.pos.x, ball.pos.y, ball.radius)


    -- Draw field lines
    love.graphics.rectangle("line", 1, 1, Width-2, Height-2)



    -- Draw Debug
    if Debug_Flags.Draw_Center_Lines then
        love.graphics.setColor(255, 255, 255, 255)
        love.graphics.line(0, Height/2, Width, Height/2)
        love.graphics.line(Width/2, 0, Width/2, Height)
    end
    
    if Debug_Flags.Print_Paddle_Velocities then
        love.graphics.setNewFont(14)
        love.graphics.print(paddles[1].vel.x..", "..paddles[1].vel.y, 0+Paddle_Edge_Offset, Paddle_Edge_Offset)
        love.graphics.print(paddles[2].vel.x..", "..paddles[2].vel.y, Width-Paddle_Edge_Offset*2, Paddle_Edge_Offset)
        love.graphics.setNewFont(Font_Size)
    end

    if Debug_Flags.Draw_Collision_Vectors then
        love.graphics.setColor(255, 0, 0, 255)
        if sepLine then
            love.graphics.line(sepLine.x1, sepLine.y1, sepLine.x2, sepLine.y2)
        end
        love.graphics.setColor(255, 255, 255, 255)
    end

    if Debug_Flags.Draw_Spin_Line then
        love.graphics.setColor(0, 0, 255, 255)

        love.graphics.line(ball.pos.x, ball.pos.y, ball.pos.x + ball.dbgSpinV.x, ball.pos.y + ball.dbgSpinV.y)
        
        love.graphics.setColor(255, 255, 255, 255)
    end

    if Debug_Flags.Print_Ball_Spin then
        love.graphics.print(ball.spin, Width/2, Height-50)
    end
end
