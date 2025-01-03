-- Constants
local fps = 15
local canvasWidth, canvasHeight = 480, 260 -- 480, 260  # 720, 390
local blockSize = 3
local blocksWide, blocksHigh = canvasWidth / blockSize, canvasHeight / blockSize
local currentFrame = 1
local numFrames = #FrameData

-- Playback control
local soundFilePath = "Interface\\AddOns\\TestAddon\\sound.mp3"

-- state
local currentSoundHandle
local isPlaying = false

-- The canvas of pixels with their rgb values
local pixelData = {}
local prevPixelColors = {}

-- Create the main frame
local videoCanvas = CreateFrame("Frame", "VideoCanvas", UIParent, "BackdropTemplate")
videoCanvas:SetSize(canvasWidth, canvasHeight)
videoCanvas:SetPoint("CENTER", UIParent, "CENTER")
videoCanvas:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 32, edgeSize = 32,
})
videoCanvas:SetBackdropColor(0, 255, 0, 1)

-- Create pixel grid
local pixels = {}
local chunkSize = 100
local currentPixelIndex = 1

local function createPixelGridChunk()
    for _ = 1, chunkSize do
        if currentPixelIndex > blocksWide * blocksHigh then
            print("Created " .. (currentPixelIndex-1) .. " pixels")
            videoCanvas:SetBackdropColor(0, 0, 0, 1)
            return
        end

        local x = ((currentPixelIndex - 1) % blocksWide) + 1
        local y = math.floor((currentPixelIndex - 1) / blocksWide) + 1

        if not pixels[y] then
            pixels[y] = {}
        end

        local pixel = videoCanvas:CreateTexture()
        pixel:SetSize(blockSize, blockSize)
        pixel:SetPoint("TOPLEFT", videoCanvas, "TOPLEFT", (x-1)*blockSize, -(y-1)*blockSize)
        pixel:SetColorTexture(0, 0, 0, 1)
        pixels[y][x] = pixel
        currentPixelIndex = currentPixelIndex + 1
    end

    C_Timer.After(0.01, createPixelGridChunk)
end

createPixelGridChunk()

videoCanvas:SetMovable(true)
videoCanvas:EnableMouse(true)
videoCanvas:RegisterForDrag("LeftButton")
videoCanvas:SetScript("OnDragStart", videoCanvas.StartMoving)
videoCanvas:SetScript("OnDragStop", videoCanvas.StopMovingOrSizing)

local closeButton = CreateFrame("Button", nil, videoCanvas, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", videoCanvas, "TOPRIGHT")
closeButton:SetScript("OnClick", function()
    SlashCmdList["STOPVIDEO"]()
end)

--- see: encode.py@pack_rgb for format
local function unpack_rgb(packed)
    local r = bit.band(bit.rshift(packed, 10), 0x3F) * 4  -- top 6 bits
    local g = bit.band(bit.rshift(packed, 4), 0x3F) * 4   -- middle 6 bits
    local b = bit.band(packed, 0x0F) * 16                -- bottom 4 bits
    return r, g, b
end

-- see: encode.py@encode_rle_deltas for format
local function decodeRLE(frameData)
    local decoded = {}
    local i = 2 -- skip keyframe flag
    while i <= #frameData do
        local pos = frameData[i]
        --- 0x8000 = high bit
        if bit.band(pos, 0x8000) ~= 0 then
            -- run of deltas
            pos = bit.band(pos, 0x7FFF)
            local run_length = frameData[i + 1]
            local value = frameData[i + 2]
            for j = 0, run_length - 1 do
                decoded[pos + j] = value
            end
            i = i + 3
        else
            -- Single delta
            decoded[pos] = frameData[i + 1]
            i = i + 2
        end
    end
    return decoded
end

local function applyDeltaFrame(deltaFrame)
    local isKeyframe = deltaFrame[1]

    if isKeyframe then
        local pixelIndex = 1
        -- i=2 (first element is keyframe flag)
        for i = 2, #deltaFrame do
            local r, g, b = unpack_rgb(deltaFrame[i])
            pixelData[pixelIndex] = r
            pixelData[pixelIndex + 1] = g
            pixelData[pixelIndex + 2] = b
            pixelData[pixelIndex + 3] = 255
            pixelIndex = pixelIndex + 4
        end
    else
        -- delta frames
        local decoded = decodeRLE(deltaFrame)
        for pos, packed_value in pairs(decoded) do
            local pixelIndex = pos * 4 + 1
            local r, g, b = unpack_rgb(packed_value)
            pixelData[pixelIndex] = r
            pixelData[pixelIndex + 1] = g
            pixelData[pixelIndex + 2] = b
            pixelData[pixelIndex + 3] = 255
        end
    end
end

local function updateDisplay()
    local pixelIndex = 1
    local colorIndex = 1
    for y = 1, blocksHigh do
        for x = 1, blocksWide do
            local r = pixelData[pixelIndex] / 255
            local g = pixelData[pixelIndex + 1] / 255
            local b = pixelData[pixelIndex + 2] / 255
            local colorKey = r * 1000000 + g * 1000 + b

            -- render when color changes
            if prevPixelColors[colorIndex] ~= colorKey then
                pixels[y][x]:SetColorTexture(r, g, b, 1)
                prevPixelColors[colorIndex] = colorKey
            end

            pixelIndex = pixelIndex + 4
            colorIndex = colorIndex + 1
        end
    end
end

local function resetDisplay()
    currentFrame = 1

    local dataSize = blocksWide * blocksHigh * 4 -- rgba
    for i = 1, dataSize do
        pixelData[i] = 0
    end

    for i = 1, blocksWide * blocksHigh do
        prevPixelColors[i] = -1
    end
    
    for y = 1, blocksHigh do
        for x = 1, blocksWide do
            pixels[y][x]:SetColorTexture(0, 0, 0, 0)
        end
    end
end

local function startVideoPlayback()
    local startTime = GetTime()

    videoCanvas:SetScript("OnUpdate", function(self, elapsed)   
        local expectedFrame = math.floor((GetTime() - startTime) * fps) + 1
        
        while currentFrame < expectedFrame and currentFrame < numFrames do
            applyDeltaFrame(FrameData[currentFrame])
            currentFrame = currentFrame + 1
        end
        
        if currentFrame >= numFrames then
            -- Stop everything when video ends
            videoCanvas:SetScript("OnUpdate", nil)
            if currentSoundHandle then
                StopSound(currentSoundHandle)
                currentSoundHandle = nil
            end
            isPlaying = false
            VideoCanvas:Hide()
            return
        end
        
        updateDisplay()
    end)
end

--- slash commands

SLASH_SHOWVIDEO1 = '/showvideo'
SLASH_PLAYVIDEO1 = '/playvideo'
SLASH_STOPVIDEO1 = '/stopvideo'

SlashCmdList["SHOWVIDEO"] = function(msg)
    videoCanvas:SetScript("OnUpdate", nil)
    videoCanvas:Show()
end

SlashCmdList["PLAYVIDEO"] = function(msg)
    videoCanvas:SetScript("OnUpdate", nil)
    videoCanvas:Show()    

    resetDisplay()
   
    local willPlay, soundHandle = PlaySoundFile(soundFilePath, "Master")
    if willPlay then
        currentSoundHandle = soundHandle
        isPlaying = true
        startVideoPlayback()
    else
        print("Failed to play sound file")
    end
end

SlashCmdList["STOPVIDEO"] = function(msg)
    if not isPlaying then
        return
    end

    videoCanvas:SetScript("OnUpdate", nil)
    
    if currentSoundHandle then
        StopSound(currentSoundHandle)
        currentSoundHandle = nil
    end
    
    isPlaying = false
    currentFrame = 1

    for y = 1, blocksHigh do
        for x = 1, blocksWide do
            pixels[y][x]:SetColorTexture(0, 0, 0, 1)
        end
    end

    videoCanvas:Hide()
end

--- buttons

local playButton = CreateFrame("Button", nil, videoCanvas, "UIPanelButtonTemplate")
playButton:SetSize(60, 20)
playButton:SetPoint("BOTTOMLEFT", videoCanvas, "BOTTOMLEFT", 10, 10)
playButton:SetText("Play")
playButton:SetScript("OnClick", function()
    SlashCmdList["PLAYVIDEO"]()
end)

local stopButton = CreateFrame("Button", nil, videoCanvas, "UIPanelButtonTemplate")
stopButton:SetSize(60, 20)
stopButton:SetPoint("LEFT", playButton, "RIGHT", 10, 0)
stopButton:SetText("Stop")
stopButton:SetScript("OnClick", function()
    SlashCmdList["STOPVIDEO"]()
end)