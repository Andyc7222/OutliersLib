-- OutliersUI Library Module
-- File: OutliersUILib.lua

--[[
    OutliersUI - Text-Only UI Library using Drawing API
    Controlled by Numpad Keys
    Position: Top-Left Corner
]]

local OutliersUILib = {}

-- Services
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Starting positions
local startX = 210 -- Moved UI to the right by 200 units
local startY = 70  -- Adjusted to provide space for tabs

-- Column width for alignment
local columnWidth = 250 -- Adjust as needed

-- Default UI Colors (can be customized in the Configuration tab)
local UIColorSettings = {
    TextColor = Color3.fromRGB(205, 205, 205),
    BackgroundColor = Color3.fromRGB(0, 0, 0),
    HighlightColor = Color3.fromRGB(255, 255, 255),
    OutlineColor = Color3.fromRGB(0, 0, 0),
    WarningColor = Color3.fromRGB(255, 255, 0),
    CurrentValueColor = Color3.fromRGB(205, 205, 205),
    ColumnHeaderColor = Color3.fromRGB(205, 205, 205),
    TabTextColor = Color3.fromRGB(205, 205, 205),
}

-- Data Structure for Tabs, Columns, and Items
local tabs = {}

-- Variable to store the Toggle UI Keybind item
local toggleUIKeybindItem = nil

-- Global flags table
_G.UIFlags = {}

-- Variables to track current selection
local currentTabIndex = 1
local currentColumnIndex = 1
local currentItemIndex = 1
local currentSelectionLevel = 1 -- 1=Tab, 2=Column, 3=Item

-- Variables for key hold
local holdingKeyLeft = false
local holdingKeyRight = false

-- Variables to track dropdown and color picker state
local dropdownOpen = false
local dropdownIndex = 1
local dropdownTexts = {}
local colorPickerOpen = false
local colorSliders = {"R", "G", "B"}
local colorSliderIndex = 1

-- Variable for keybind listening state
local keybindListening = false

-- Variable to track UI visibility
local uiVisible = true

-- Store text objects for later updates
local uiTitleText = nil
local tabTexts = {}
local columnHeaders = {}
local itemTexts = {}

-- Variables to store connections for cleanup
local connections = {}

-- Function to set UI visibility
function OutliersUILib:SetVisibility(visible)
    uiVisible = visible
    -- Update the visibility of all UI elements
    if uiTitleText then uiTitleText.Visible = uiVisible end
    for _, tabText in pairs(tabTexts) do
        tabText.Visible = uiVisible
    end
    for _, columnHeader in pairs(columnHeaders) do
        columnHeader.Visible = uiVisible
    end
    for _, texts in pairs(itemTexts) do
        for _, textPair in pairs(texts) do
            if textPair.nameText then textPair.nameText.Visible = uiVisible end
            if textPair.valueText then textPair.valueText.Visible = uiVisible end
        end
    end
    for _, textObj in pairs(dropdownTexts) do
        textObj.Visible = uiVisible
    end
end

-- Function to reset selection indices when switching tabs or columns
local function resetSelectionIndices()
    local tab = tabs[currentTabIndex]
    if currentColumnIndex > #tab.columns then
        currentColumnIndex = #tab.columns
    end
    if currentSelectionLevel == 3 then
        local items = tab.columns[currentColumnIndex].items
        if currentItemIndex > #items then
            currentItemIndex = #items
        end
    end
end

-- Function to move to the next item
local function moveToNextItem()
    local items = tabs[currentTabIndex].columns[currentColumnIndex].items
    if currentItemIndex < #items then
        currentItemIndex = currentItemIndex + 1
    end
    updateSelection()
end

-- Function to move to the previous item
local function moveToPreviousItem()
    if currentItemIndex > 1 then
        currentItemIndex = currentItemIndex - 1
    end
    updateSelection()
end

-- Function to modify item value
local function modifyItemValue(item, delta)
    local oldValue = item.value or item.values
    local valueChanged = false

    if item.type == "Toggle" then
        -- Modify on individual presses
        if delta ~= 0 then
            item.value = (item.value == "On") and "Off" or "On"
            valueChanged = (item.value ~= oldValue)
        end
    elseif item.type == "Slider" then
        -- Adjust slider value
        local increment = item.increment or 1
        local minValue = item.min or 0
        local maxValue = item.max or 1000
        local newValue = tonumber(item.value)
        if newValue then
            newValue = newValue + delta * increment
            if newValue > maxValue then newValue = maxValue end
            if newValue < minValue then newValue = minValue end
            item.value = math.floor(newValue * 100) / 100 -- Round to two decimals
            valueChanged = (item.value ~= oldValue)
        end
    elseif item.type == "ColorPicker" then
        -- Adjust color component
        local component = colorSliders[colorSliderIndex]
        local color = item.value
        local increment = delta * 1 / 255
        if component == "R" then
            color = Color3.new(math.clamp(color.R + increment, 0, 1), color.G, color.B)
        elseif component == "G" then
            color = Color3.new(color.R, math.clamp(color.G + increment, 0, 1), color.B)
        elseif component == "B" then
            color = Color3.new(color.R, color.G, math.clamp(color.B + increment, 0, 1))
        end
        item.value = color
        valueChanged = true
    elseif item.type == "Keybind" then
        -- Change mode on individual presses
        if delta ~= 0 then
            item.modeIndex = item.modeIndex + delta
            if item.modeIndex < 1 then item.modeIndex = #item.modes end
            if item.modeIndex > #item.modes then item.modeIndex = 1 end
            item.mode = item.modes[item.modeIndex]
            -- Reset flag if mode is None
            if item.mode == "None" then
                _G.UIFlags[item.flag] = false
            end
            valueChanged = true
        end
    elseif item.type == "Select" then
        -- Handled via dropdown
    elseif item.type == "MultiDropdown" then
        -- Handled via dropdown
    elseif item.type == "Button" then
        -- Buttons are triggered via Numpad 5
        -- No value to modify here
    end

    -- Update global flag
    if item.flag then
        if item.type == "Keybind" then
            -- Do not update flag here; flag is managed in InputBegan/InputEnded
        elseif item.type == "ColorPicker" then
            _G.UIFlags[item.flag] = item.value
        else
            _G.UIFlags[item.flag] = item.value or item.values
        end
    end

    -- Call the callback function if value changed
    if valueChanged and item.callback then
        if item.type == "Keybind" then
            item.callback(item.keyName or "None", item.mode)
        else
            item.callback(item.value or item.values)
        end
    end

    -- Update the text display
    updateItemText()
    -- Update the selection to refresh highlighting
    updateSelection()
end

-- Function to update item text (after interaction)
function updateItemText()
    local columns = tabs[currentTabIndex].columns
    for colIndex, column in ipairs(columns) do
        local columnX = startX + (colIndex - 1) * columnWidth
        local rightEdgeX = columnX + columnWidth - 10 -- Subtract 10 for padding
        local items = column.items
        for itemIndex, item in ipairs(items) do
            local textPair = itemTexts[colIndex][itemIndex]
            if textPair.nameText then
                textPair.nameText.Text = item.name or ""
                -- Removed setting textPair.nameText.Color here
            end
            if textPair.valueText then
                if item.type == "Button" then
                    textPair.valueText.Text = "[Press 5]"
                elseif item.type == "MultiDropdown" then
                    local valuesText = #item.values > 0 and "Selected" or "None"
                    textPair.valueText.Text = valuesText
                elseif item.type == "ColorPicker" then
                    textPair.valueText.Text = "ColorPicker"
                elseif item.type == "Keybind" then
                    textPair.valueText.Text = (item.keyName or "None") .. " (" .. item.mode .. ")"
                else
                    textPair.valueText.Text = tostring(item.value or "")
                end
                -- Removed setting textPair.valueText.Color here
                -- Adjust value text position for right alignment
                local textBounds = textPair.valueText.TextBounds
                local valueX = rightEdgeX - textBounds.X
                textPair.valueText.Position = Vector2.new(valueX, textPair.valueText.Position.Y)
            end
        end
    end
end

-- Function to update the UI selection
function updateSelection()
    -- Reset colors and positions
    -- Tabs
    for i, tabText in ipairs(tabTexts) do
        tabText.Color = UIColorSettings.TabTextColor
        -- Highlight selected tab
        if i == currentTabIndex and currentSelectionLevel == 1 then
            tabText.Color = UIColorSettings.HighlightColor
        end
    end
    -- Columns
    for i, columnHeader in ipairs(columnHeaders) do
        columnHeader.Color = UIColorSettings.ColumnHeaderColor
        -- Highlight selected column
        if i == currentColumnIndex and currentSelectionLevel == 2 then
            columnHeader.Color = UIColorSettings.HighlightColor
        end
    end
    -- Items
    for colIndex, texts in pairs(itemTexts) do
        for itemIndex, textPair in ipairs(texts) do
            if textPair.nameText then
                textPair.nameText.Color = UIColorSettings.TextColor
                -- Highlight selected item
                if colIndex == currentColumnIndex and itemIndex == currentItemIndex and currentSelectionLevel == 3 then
                    textPair.nameText.Color = UIColorSettings.HighlightColor
                end
            end
            if textPair.valueText then
                textPair.valueText.Color = UIColorSettings.CurrentValueColor
                -- Highlight selected item
                if colIndex == currentColumnIndex and itemIndex == currentItemIndex and currentSelectionLevel == 3 then
                    textPair.valueText.Color = UIColorSettings.HighlightColor
                end
            end
            -- Reset positions to original
            if textPair.nameText then
                textPair.nameText.Position = Vector2.new(textPair.nameText.Position.X, textPair.originalNameY)
            end
            if textPair.valueText then
                textPair.valueText.Position = Vector2.new(textPair.valueText.Position.X, textPair.originalValueY)
            end
        end
    end
    -- Clear previous dropdown texts
    for _, textObj in pairs(dropdownTexts) do
        textObj:Remove()
    end
    dropdownTexts = {}

    if dropdownOpen then
        -- Display dropdown options
        local selectedItemTextPair = itemTexts[currentColumnIndex][currentItemIndex]
        local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
        local options = item.options or {}
        local startY = selectedItemTextPair.nameText.Position.Y + 20 -- Adjust as needed

        -- Shift items below dropdown
        local shiftAmount = #options * 20 -- Adjust as needed
        for idx = currentItemIndex + 1, #itemTexts[currentColumnIndex] do
            local nextItem = itemTexts[currentColumnIndex][idx]
            if nextItem.nameText then
                nextItem.nameText.Position = nextItem.nameText.Position + Vector2.new(0, shiftAmount)
            end
            if nextItem.valueText then
                nextItem.valueText.Position = nextItem.valueText.Position + Vector2.new(0, shiftAmount)
            end
        end

        for i, option in ipairs(options) do
            local optionText = Drawing.new("Text")
            optionText.Visible = uiVisible
            if item.type == "MultiDropdown" then
                local selected = table.find(item.values, option) and "[x] " or "[ ] "
                optionText.Text = selected .. option
            else
                optionText.Text = option
            end
            optionText.Size = 16 -- Adjust as needed
            optionText.Position = Vector2.new(selectedItemTextPair.nameText.Position.X + 20, startY + (i - 1) * 20)
            if i == dropdownIndex then
                optionText.Color = UIColorSettings.HighlightColor
            else
                optionText.Color = UIColorSettings.TextColor
            end
            optionText.Outline = true
            optionText.OutlineColor = UIColorSettings.OutlineColor
            table.insert(dropdownTexts, optionText)
        end
    elseif colorPickerOpen then
        -- Display RGB sliders
        local selectedItemTextPair = itemTexts[currentColumnIndex][currentItemIndex]
        local startY = selectedItemTextPair.nameText.Position.Y + 20 -- Adjust as needed

        -- Shift items below color picker
        local shiftAmount = #colorSliders * 20 -- Adjust as needed
        for idx = currentItemIndex + 1, #itemTexts[currentColumnIndex] do
            local nextItem = itemTexts[currentColumnIndex][idx]
            if nextItem.nameText then
                nextItem.nameText.Position = nextItem.nameText.Position + Vector2.new(0, shiftAmount)
            end
            if nextItem.valueText then
                nextItem.valueText.Position = nextItem.valueText.Position + Vector2.new(0, shiftAmount)
            end
        end

        for i, slider in ipairs(colorSliders) do
            local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
            local color = item.value
            local value = 0
            if slider == "R" then
                value = math.floor(color.R * 255)
            elseif slider == "G" then
                value = math.floor(color.G * 255)
            elseif slider == "B" then
                value = math.floor(color.B * 255)
            end

            local valueText = Drawing.new("Text")
            valueText.Visible = uiVisible
            valueText.Text = slider .. ": " .. tostring(value)
            valueText.Size = 16 -- Adjust as needed
            -- Align the value text (Right alignment)
            local rightEdgeX = selectedItemTextPair.nameText.Position.X + columnWidth - 10
            local textBounds = valueText.TextBounds
            local valueX = rightEdgeX - textBounds.X
            valueText.Position = Vector2.new(valueX, startY + (i - 1) * 20)
            if i == colorSliderIndex then
                valueText.Color = UIColorSettings.HighlightColor
            else
                valueText.Color = UIColorSettings.TextColor
            end
            valueText.Outline = true
            valueText.OutlineColor = UIColorSettings.OutlineColor

            table.insert(dropdownTexts, valueText)
        end
    elseif keybindListening then
        -- Display "Press any key..." message
        local selectedItemTextPair = itemTexts[currentColumnIndex][currentItemIndex]
        local listeningText = Drawing.new("Text")
        listeningText.Visible = uiVisible
        listeningText.Text = "Press any key to bind..."
        listeningText.Size = 16 -- Adjust as needed
        listeningText.Position = Vector2.new(selectedItemTextPair.nameText.Position.X + 20, selectedItemTextPair.nameText.Position.Y + 20)
        listeningText.Color = UIColorSettings.WarningColor
        listeningText.Outline = true
        listeningText.OutlineColor = UIColorSettings.OutlineColor
        table.insert(dropdownTexts, listeningText)
    end
end

-- Function to update UI colors
function updateUIColors()
    -- Update UI title
    if uiTitleText then
        uiTitleText.Color = UIColorSettings.TextColor
        uiTitleText.OutlineColor = UIColorSettings.OutlineColor
    end

    -- Update tab texts
    for i, tabText in pairs(tabTexts) do
        tabText.Color = UIColorSettings.TabTextColor
        tabText.OutlineColor = UIColorSettings.OutlineColor
        -- Highlight selected tab
        if i == currentTabIndex and currentSelectionLevel == 1 then
            tabText.Color = UIColorSettings.HighlightColor
        end
    end
    -- Update column headers
    for i, columnHeader in pairs(columnHeaders) do
        columnHeader.Color = UIColorSettings.ColumnHeaderColor
        columnHeader.OutlineColor = UIColorSettings.OutlineColor
        -- Highlight selected column
        if i == currentColumnIndex and currentSelectionLevel == 2 then
            columnHeader.Color = UIColorSettings.HighlightColor
        end
    end
    -- Update items
    for colIndex, texts in pairs(itemTexts) do
        for itemIndex, textPair in pairs(texts) do
            if textPair.nameText then
                textPair.nameText.Color = UIColorSettings.TextColor
                textPair.nameText.OutlineColor = UIColorSettings.OutlineColor
            end
            if textPair.valueText then
                textPair.valueText.Color = UIColorSettings.CurrentValueColor
                textPair.valueText.OutlineColor = UIColorSettings.OutlineColor
            end
            -- Highlight selected item
            if colIndex == currentColumnIndex and itemIndex == currentItemIndex and currentSelectionLevel == 3 then
                if textPair.nameText then
                    textPair.nameText.Color = UIColorSettings.HighlightColor
                end
                if textPair.valueText then
                    textPair.valueText.Color = UIColorSettings.HighlightColor
                end
            end
        end
    end
    -- Update selection (e.g., dropdowns, color picker)
    updateSelection()
end

-- Function to create and display tabs
local function createTabs()
    -- Remove previous tab texts
    for _, textObj in pairs(tabTexts) do
        textObj:Remove()
    end
    tabTexts = {}

    local tabX = startX
    local tabY = startY - 30  -- Adjusted to be above columns
    for i, tab in ipairs(tabs) do
        local tabText = Drawing.new("Text")
        tabText.Visible = uiVisible
        tabText.Text = tab.name
        tabText.Size = 20 -- Adjust size as needed
        tabText.Position = Vector2.new(tabX, tabY)
        tabText.Color = UIColorSettings.TabTextColor
        tabText.Outline = true
        tabText.OutlineColor = UIColorSettings.OutlineColor
        tabTexts[i] = tabText

        -- Align tabs with columns
        tabX = tabX + columnWidth -- Move to the next column position
    end
end

-- Function to display columns and items for the current tab
local function displayCurrentTab()
    -- Clear previous column headers and items
    for _, textObj in pairs(columnHeaders) do
        textObj:Remove()
    end
    columnHeaders = {}
    for _, texts in pairs(itemTexts) do
        for _, textPair in pairs(texts) do
            if textPair.nameText then textPair.nameText:Remove() end
            if textPair.valueText then textPair.valueText:Remove() end
        end
    end
    itemTexts = {}

    local tab = tabs[currentTabIndex]
    local columns = tab.columns
    local columnX = startX
    local columnY = startY + 10 -- Adjust as needed based on tab size

    for colIndex, column in ipairs(columns) do
        -- Create column header
        local columnHeader = Drawing.new("Text")
        columnHeader.Visible = uiVisible
        columnHeader.Text = column.name
        columnHeader.Size = 18 -- Adjust size as needed
        columnHeader.Position = Vector2.new(columnX, columnY)
        columnHeader.Color = UIColorSettings.ColumnHeaderColor
        columnHeader.Outline = true
        columnHeader.OutlineColor = UIColorSettings.OutlineColor
        columnHeaders[colIndex] = columnHeader

        -- Create items under this column
        local items = column.items
        itemTexts[colIndex] = {}
        local itemY = columnY + 25
        for itemIndex, item in ipairs(items) do
            -- Initialize global flag
            if item.flag then
                if item.type == "Keybind" then
                    _G.UIFlags[item.flag] = false -- Initialize keybind flag to false
                elseif item.type == "ColorPicker" then
                    _G.UIFlags[item.flag] = item.value
                else
                    _G.UIFlags[item.flag] = item.value or item.values
                end
            end

            -- Item Name
            local itemNameText = Drawing.new("Text")
            itemNameText.Visible = uiVisible
            itemNameText.Text = item.name
            itemNameText.Size = 16 -- Adjust size as needed
            itemNameText.Position = Vector2.new(columnX, itemY)
            itemNameText.Color = UIColorSettings.TextColor
            itemNameText.Outline = true
            itemNameText.OutlineColor = UIColorSettings.OutlineColor

            -- Item Value
            local itemValueText = Drawing.new("Text")
            itemValueText.Visible = uiVisible
            if item.type == "Button" then
                itemValueText.Text = "[Press 5]"
            elseif item.type == "MultiDropdown" then
                -- Display "Selected" or "None"
                local valuesText = #item.values > 0 and "Selected" or "None"
                itemValueText.Text = valuesText
            elseif item.type == "ColorPicker" then
                itemValueText.Text = "ColorPicker"
            elseif item.type == "Keybind" then
                itemValueText.Text = (item.keyName or "None") .. " (" .. item.mode .. ")"
            else
                itemValueText.Text = tostring(item.value)
            end
            itemValueText.Size = 16 -- Adjust size as needed
            itemValueText.Color = UIColorSettings.CurrentValueColor
            itemValueText.Outline = true
            itemValueText.OutlineColor = UIColorSettings.OutlineColor
            -- Align the value text (Right alignment)
            local rightEdgeX = columnX + columnWidth - 10 -- Subtract 10 for padding
            local textBounds = itemValueText.TextBounds
            local valueX = rightEdgeX - textBounds.X
            itemValueText.Position = Vector2.new(valueX, itemY)

            -- Store original positions
            itemTexts[colIndex][itemIndex] = {
                nameText = itemNameText,
                valueText = itemValueText,
                originalNameY = itemNameText.Position.Y,
                originalValueY = itemValueText.Position.Y,
                itemHeight = 20 -- Adjust as needed
            }
            itemY = itemY + 20 -- Adjust as needed
        end
        columnX = columnX + columnWidth -- Move to the next column position
    end
end

-- Key hold processing
local function keyHoldLoop()
    local holdTime = 0
    local minDelay = 0.05
    local maxDelay = 0.15 -- Adjusted max delay
    local delay = maxDelay

    while holdingKeyLeft or holdingKeyRight do
        if currentSelectionLevel == 3 and not dropdownOpen and not colorPickerOpen and not keybindListening then
            local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
            if item.type == "Slider" then
                -- Only apply continuous modification to sliders
                if holdingKeyLeft then
                    modifyItemValue(item, -1)
                elseif holdingKeyRight then
                    modifyItemValue(item, 1)
                end
                -- updateItemText() and updateSelection() are called inside modifyItemValue()
            end
        elseif colorPickerOpen then
            -- Adjust color component
            local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
            if holdingKeyLeft then
                modifyItemValue(item, -1)
            elseif holdingKeyRight then
                modifyItemValue(item, 1)
            end
            -- updateItemText() and updateSelection() are called inside modifyItemValue()
        end
        wait(delay)
        -- Increase hold time
        holdTime = holdTime + delay
        -- Accelerate the modification speed
        delay = math.max(minDelay, maxDelay - holdTime * 0.02) -- Adjusted acceleration rate
    end
end

-- Function to add the "Configuration" tab
function OutliersUILib:AddConfigurationTab()
    local configTab = {
        name = "Configuration",
        columns = {
            {
                name = "Colors",
                items = {
                    {type = "ColorPicker", name = "Text Color", value = UIColorSettings.TextColor, flag = "TextColor", callback = function(value)
                        UIColorSettings.TextColor = value
                        updateUIColors()
                    end},
                    {type = "ColorPicker", name = "Highlight Color", value = UIColorSettings.HighlightColor, flag = "HighlightColor", callback = function(value)
                        UIColorSettings.HighlightColor = value
                        updateUIColors()
                    end},
                    {type = "ColorPicker", name = "Outline Color", value = UIColorSettings.OutlineColor, flag = "OutlineColor", callback = function(value)
                        UIColorSettings.OutlineColor = value
                        updateUIColors()
                    end},
                    {type = "ColorPicker", name = "Warning Color", value = UIColorSettings.WarningColor, flag = "WarningColor", callback = function(value)
                        UIColorSettings.WarningColor = value
                        updateUIColors()
                    end},
                    {type = "ColorPicker", name = "Current Value Color", value = UIColorSettings.CurrentValueColor, flag = "CurrentValueColor", callback = function(value)
                        UIColorSettings.CurrentValueColor = value
                        updateUIColors()
                    end},
                    {type = "ColorPicker", name = "Column Header Color", value = UIColorSettings.ColumnHeaderColor, flag = "ColumnHeaderColor", callback = function(value)
                        UIColorSettings.ColumnHeaderColor = value
                        updateUIColors()
                    end},
                    {type = "ColorPicker", name = "Tab Text Color", value = UIColorSettings.TabTextColor, flag = "TabTextColor", callback = function(value)
                        UIColorSettings.TabTextColor = value
                        updateUIColors()
                    end},
                    -- Add more color settings as needed
                }
            },
            {
                name = "Settings",
                items = {
                    {type = "Keybind", name = "Toggle UI Keybind", key = Enum.KeyCode.RightShift, keyName = "RightShift", mode = "Toggle", modes = {"Toggle"}, modeIndex = 1, flag = "ToggleUIKeybind", callback = function(key, mode)
                        print("Toggle UI Keybind set to:", key)
                    end},
                    {type = "Button", name = "Unload UI", callback = function()
                        OutliersUILib:Unload()
                    end}
                }
            }
        }
    }
    -- Store a reference to the Toggle UI Keybind item
    toggleUIKeybindItem = configTab.columns[2].items[1]
    table.insert(tabs, configTab)
end

-- Function to initialize the UI library
function OutliersUILib:Init()
    -- Add the "Configuration" tab
    self:AddConfigurationTab()
    -- Create the UI
    createTabs()
    displayCurrentTab()
    updateUIColors()
    -- Initial selection highlight
    updateSelection()
end

-- Function to add a tab
function OutliersUILib:AddTab(tabName)
    local tab = { name = tabName, columns = {} }
    table.insert(tabs, tab)
    return tab
end

-- Function to add a column to a tab
function OutliersUILib:AddColumn(tab, columnName)
    local column = { name = columnName, items = {} }
    table.insert(tab.columns, column)
    return column
end

-- Function to add an item to a column
function OutliersUILib:AddItem(column, item)
    table.insert(column.items, item)
end

-- Function to unload the UI
function OutliersUILib:Unload()
    -- Remove UI elements
    if uiTitleText then uiTitleText:Remove() end
    for _, tabText in pairs(tabTexts) do
        tabText:Remove()
    end
    for _, columnHeader in pairs(columnHeaders) do
        columnHeader:Remove()
    end
    for _, texts in pairs(itemTexts) do
        for _, textPair in pairs(texts) do
            if textPair.nameText then textPair.nameText:Remove() end
            if textPair.valueText then textPair.valueText:Remove() end
        end
    end
    for _, textObj in pairs(dropdownTexts) do
        textObj:Remove()
    end
    -- Disconnect input events
    for _, connection in pairs(connections) do
        connection:Disconnect()
    end
    -- Clear tables
    tabs = {}
    tabTexts = {}
    columnHeaders = {}
    itemTexts = {}
    dropdownTexts = {}
    _G.UIFlags = {}
    -- Print message
    print("OutliersUI Unloaded")
end

-- Input handling
local inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if gameProcessedEvent then return end

    -- Handle UI toggle keybind
    if toggleUIKeybindItem and toggleUIKeybindItem.key and toggleUIKeybindItem.mode == "Toggle" then
        if input.KeyCode == toggleUIKeybindItem.key then
            uiVisible = not uiVisible
            -- Set visibility of all UI elements
            OutliersUILib:SetVisibility(uiVisible)
            -- Do not process other inputs if UI is hidden
            if not uiVisible then return end
        end
    end

    if not uiVisible then return end

    -- Handle keybind activation
    if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
        for _, tab in ipairs(tabs) do
            for _, column in ipairs(tab.columns) do
                for _, item in ipairs(column.items) do
                    if item.type == "Keybind" and item.key and item.mode ~= "None" then
                        if input.KeyCode == item.key or (input.UserInputType == Enum.UserInputType.MouseButton1 and item.key == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.MouseButton2 and item.key == Enum.UserInputType.MouseButton2) then
                            if item.mode == "Hold" then
                                _G.UIFlags[item.flag] = true
                            elseif item.mode == "Toggle" then
                                _G.UIFlags[item.flag] = not _G.UIFlags[item.flag]
                            end
                            if item.callback then
                                item.callback(item.keyName or "None", item.mode)
                            end
                        end
                    end
                end
            end
        end
    end

    if keybindListening then
        -- Capture key for keybind
        local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
        if input.UserInputType == Enum.UserInputType.Keyboard then
            item.key = input.KeyCode
            item.keyName = input.KeyCode.Name
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            item.key = Enum.UserInputType.MouseButton1
            item.keyName = "MouseButton1"
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            item.key = Enum.UserInputType.MouseButton2
            item.keyName = "MouseButton2"
        else
            item.key = nil
            item.keyName = "Unknown"
        end
        keybindListening = false
        -- Update global flag
        if item.flag then
            _G.UIFlags[item.flag] = false -- Initialize flag to false
        end
        if item.callback then
            item.callback(item.keyName or "None", item.mode)
        end
        updateItemText()
        updateSelection()
        return
    end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        local keyPressed = input.KeyCode

        if keyPressed == Enum.KeyCode.KeypadEight then -- Numpad 8
            if dropdownOpen then
                if dropdownIndex > 1 then
                    -- Navigate up in the dropdown
                    dropdownIndex = dropdownIndex - 1
                    updateSelection()
                else
                    -- At the first option, exit dropdown
                    dropdownOpen = false
                    updateSelection()
                end
            elseif colorPickerOpen then
                if colorSliderIndex > 1 then
                    colorSliderIndex = colorSliderIndex - 1
                    updateSelection()
                else
                    -- Exit color picker
                    colorPickerOpen = false
                    updateSelection()
                end
            elseif currentSelectionLevel == 1 then
                -- Do nothing, already at top level
            elseif currentSelectionLevel == 2 then
                -- Move up to tab level
                currentSelectionLevel = 1
                updateSelection()
            elseif currentSelectionLevel == 3 then
                -- Move to previous item
                moveToPreviousItem()
            end
        elseif keyPressed == Enum.KeyCode.KeypadTwo then -- Numpad 2
            if dropdownOpen then
                local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
                local options = item.options or {}
                if dropdownIndex < #options then
                    -- Navigate down in the dropdown
                    dropdownIndex = dropdownIndex + 1
                    updateSelection()
                else
                    -- At the last option, exit dropdown
                    dropdownOpen = false
                    updateSelection()
                end
            elseif colorPickerOpen then
                if colorSliderIndex < #colorSliders then
                    colorSliderIndex = colorSliderIndex + 1
                    updateSelection()
                else
                    -- Exit color picker
                    colorPickerOpen = false
                    updateSelection()
                end
            elseif currentSelectionLevel == 1 then
                -- Move down to column level
                currentSelectionLevel = 2
                updateSelection()
            elseif currentSelectionLevel == 2 then
                -- Move down to item level
                currentSelectionLevel = 3
                currentItemIndex = 1
                updateSelection()
            elseif currentSelectionLevel == 3 then
                -- Move to next item
                moveToNextItem()
            end
        elseif keyPressed == Enum.KeyCode.KeypadFour then -- Numpad 4
            if dropdownOpen then
                -- Do nothing when dropdown is open
            elseif colorPickerOpen then
                -- Start holding left key
                holdingKeyLeft = true
                coroutine.wrap(keyHoldLoop)()
            elseif keybindListening then
                -- Do nothing while listening
            elseif currentSelectionLevel == 1 then
                -- Navigate between tabs
                if currentTabIndex > 1 then
                    currentTabIndex = currentTabIndex - 1
                    currentColumnIndex = 1
                    currentItemIndex = 1
                    createTabs()
                    displayCurrentTab()
                    resetSelectionIndices()
                    updateSelection()
                end
            elseif currentSelectionLevel == 2 then
                -- Navigate between columns
                if currentColumnIndex > 1 then
                    currentColumnIndex = currentColumnIndex - 1
                    updateSelection()
                end
            elseif currentSelectionLevel == 3 then
                -- Modify item value
                local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
                if item.type == "Slider" then
                    -- Start holding left key
                    holdingKeyLeft = true
                    coroutine.wrap(keyHoldLoop)()
                elseif item.type == "Keybind" then
                    -- Modify mode on single press
                    modifyItemValue(item, -1)
                else
                    -- Modify item value once
                    modifyItemValue(item, -1)
                end
            end
        elseif keyPressed == Enum.KeyCode.KeypadSix then -- Numpad 6
            if dropdownOpen then
                -- Do nothing when dropdown is open
            elseif colorPickerOpen then
                -- Start holding right key
                holdingKeyRight = true
                coroutine.wrap(keyHoldLoop)()
            elseif keybindListening then
                -- Do nothing while listening
            elseif currentSelectionLevel == 1 then
                -- Navigate between tabs
                if currentTabIndex < #tabs then
                    currentTabIndex = currentTabIndex + 1
                    currentColumnIndex = 1
                    currentItemIndex = 1
                    createTabs()
                    displayCurrentTab()
                    resetSelectionIndices()
                    updateSelection()
                end
            elseif currentSelectionLevel == 2 then
                -- Navigate between columns
                local columns = tabs[currentTabIndex].columns
                if currentColumnIndex < #columns then
                    currentColumnIndex = currentColumnIndex + 1
                    updateSelection()
                end
            elseif currentSelectionLevel == 3 then
                -- Modify item value
                local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
                if item.type == "Slider" then
                    -- Start holding right key
                    holdingKeyRight = true
                    coroutine.wrap(keyHoldLoop)()
                elseif item.type == "Keybind" then
                    -- Modify mode on single press
                    modifyItemValue(item, 1)
                else
                    -- Modify item value once
                    modifyItemValue(item, 1)
                end
            end
        elseif keyPressed == Enum.KeyCode.KeypadFive then -- Numpad 5 (Select/Enter)
            -- Select/Interact
            if dropdownOpen then
                -- Confirm selection
                local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
                local options = item.options or {}
                if item.type == "MultiDropdown" then
                    local selectedOption = options[dropdownIndex]
                    local idx = table.find(item.values, selectedOption)
                    if idx then
                        table.remove(item.values, idx)
                    else
                        table.insert(item.values, selectedOption)
                    end
                    if item.callback then
                        item.callback(item.values)
                    end
                    updateItemText()
                    updateSelection()
                else
                    -- For single Select
                    item.value = options[dropdownIndex]
                    dropdownOpen = false
                    if item.callback then
                        item.callback(item.value)
                    end
                    updateItemText()
                    updateSelection()
                end
            elseif colorPickerOpen then
                -- Do nothing on Numpad 5 in color picker
            elseif keybindListening then
                -- Do nothing while listening
            elseif currentSelectionLevel == 2 then
                -- From column header, move to item level
                currentSelectionLevel = 3
                currentItemIndex = 1
                updateSelection()
            elseif currentSelectionLevel == 3 then
                -- Interact with item
                local item = tabs[currentTabIndex].columns[currentColumnIndex].items[currentItemIndex]
                if item.type == "Button" then
                    if item.callback then
                        item.callback()
                    end
                elseif item.type == "Select" or item.type == "MultiDropdown" then
                    -- Open dropdown
                    dropdownOpen = true
                    local options = item.options or {}
                    -- Set dropdownIndex to current value's index
                    if item.type == "Select" then
                        dropdownIndex = table.find(options, item.value) or 1
                    elseif item.type == "MultiDropdown" then
                        dropdownIndex = 1
                    end
                    updateSelection()
                elseif item.type == "ColorPicker" then
                    -- Open color picker
                    colorPickerOpen = true
                    colorSliderIndex = 1
                    updateSelection()
                elseif item.type == "Keybind" then
                    -- Enter listening mode
                    keybindListening = true
                    updateSelection()
                elseif item.type == "Toggle" then
                    modifyItemValue(item, 1)
                end
            end
        elseif keyPressed == Enum.KeyCode.KeypadSeven then -- Numpad 7 (Back)
            if dropdownOpen then
                -- Close dropdown without changing selection
                dropdownOpen = false
                updateSelection()
            elseif colorPickerOpen then
                -- Close color picker
                colorPickerOpen = false
                updateSelection()
            elseif keybindListening then
                -- Cancel keybind listening
                keybindListening = false
                updateSelection()
            elseif currentSelectionLevel > 1 then
                currentSelectionLevel = currentSelectionLevel - 1
                updateSelection()
            end
        end
    end
end)
table.insert(connections, inputBeganConnection)

local inputEndedConnection = UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
    if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
        -- Handle keybind deactivation for Hold mode
        for _, tab in ipairs(tabs) do
            for _, column in ipairs(tab.columns) do
                for _, item in ipairs(column.items) do
                    if item.type == "Keybind" and item.key and item.mode == "Hold" then
                        if input.KeyCode == item.key or (input.UserInputType == Enum.UserInputType.MouseButton1 and item.key == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.MouseButton2 and item.key == Enum.UserInputType.MouseButton2) then
                            _G.UIFlags[item.flag] = false
                            if item.callback then
                                item.callback(item.keyName or "None", item.mode)
                            end
                        end
                    end
                end
            end
        end
    end

    if input.UserInputType == Enum.UserInputType.Keyboard then
        local keyReleased = input.KeyCode
        if keyReleased == Enum.KeyCode.KeypadFour then -- Numpad 4
            holdingKeyLeft = false
        elseif keyReleased == Enum.KeyCode.KeypadSix then -- Numpad 6
            holdingKeyRight = false
        end
    end
end)
table.insert(connections, inputEndedConnection)

return OutliersUILib
