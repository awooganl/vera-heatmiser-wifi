-- HeatMiser Wi-Fi Thermostat Plug-In for MicasaVerde Vera
-- (c) Alan Carter 2013-2014


-- Plug-in currently supports Heatmiser Program Mode 00 (5/2 Mode) only



local	HEATMISER_VERSION 	= "1.93"

local	TEMPERATURE_SERVICE = "urn:upnp-org:serviceId:TemperatureSensor1"
local	TEMPERATURE_SETPOINT= "urn:upnp-org:serviceId:TemperatureSetpoint1"
local	HOME_AUTO_SERVICE	= "urn:micasaverde-com:serviceId:HaDevice1"
local 	HEATMISER_SERVICE 	= "urn:ra-carter-com:serviceId:Heatmiser"
local 	HEATMISER_LOG 		= "HeatMiser: "
local	HVAC_USER_SERVICE	= "urn:upnp-org:serviceId:HVAC_UserOperatingMode1"
local   HVAC_OPERATING_SERVICE  = "urn:micasaverde-com:serviceId:HVAC_OperatingState1"
local	SECURITY_SERVICE	= "urn:micasaverde-com:serviceId:SecuritySensor1"

local  	FUNCTION_READ		= 147
local  	FUNCTION_WRITE		= 163

local  	DCBPNT_START		= 0
local  	DCBPNT_ALL			= 65535

local	DCBPNT_MODEL		= 4
local	DCBPNT_TEMP_FORMAT	= 5
local	DCBPNT_SENSOR_SEL	= 13
local  	DCBPNT_FROSTTEMP  	= 17
local  	DCBPNT_SETTEMP    	= 18
local  	DCBPNT_ONOFF    	= 21
local  	DCBPNT_KEYLOCK    	= 22
local  	DCBPNT_RUNMODE    	= 23
local  	DCBPNT_TEMPHOLDMINS	= 31
local  	DCBUNQ_TEMPHOLDMINS = 32
local	DCBPNT_REMOTETEMP	= 33
local	DCBPNT_FLOORTEMP	= 35
local  	DCBPNT_ROOMTEMP    	= 37
local  	DCBPNT_ERRORCODE  	= 39	-- Not currently used
local  	DCBPNT_HEATSTATE  	= 40
local	DCBPNT_HWSTATE		= 43	-- HW models only
local	DCBUNQ_HWSTATE		= 42	-- HW models only
local	DCBUNQ_SETTIME		= 43

local 	ipAddress
local 	ipPort 				= 8068
local  	PIN					= 1234

local 	errorsCRC
local	comm_failure

local 	message_type		= ""
local	heatmiser_poll		= "-"
local	heatmiser_cmd		= "*"
local 	incomingDCB 		= ""

local	socket				= require("socket")
local	bit 				= require("bit")
local	err

local 	lug_device 			= nil
local	Handle				= 0

local	model				= 0
local	model_text			= ""
local 	ModeStatus 			= "AutoChangeOver"
local	tempUnits			= ""
local	lo_temp_limit
local	hi_temp_limit
local	lo_frost_limit
local	hi_frost_limit
local	timeSyncEnable
local	loggingEnable
local	setHoldMins
local	setHoldHours
local	setHoldTemp

local	pollFString			=	""
local	pollFrequency		=	30
local	timeSHString		=	""
local	timeSyncHour		=	3

local	last_tempFormat		=	0
local	last_tempHold 		=	0
local	last_onoff_status	=	0
local	last_keylock_status	=	0
local	last_runmode_status	=	0
local	last_sensor_sel		=	0
local	last_frost_temp		=	0
local	last_heat_state		=	0
local	last_hw_state		=	0
local	last_cur_temp		=	0
local	last_set_temp		=	0
local	last_mode_status	=	""
local	hs_change			=	0
local	cs_change			=	1

local	sensor				=	"Unsupported Mode"


	-- Run once at Luup engine startup.
	function initialise(lul_device)
  		luup.log(HEATMISER_LOG.."Initialising Heatmiser Device")
		lug_device = lul_device
		local ip_missing = 0
		local pin_missing = 0
  		if (luup.devices[lul_device].ip == "") then
			luup.task(HEATMISER_LOG.."Assign IP Address", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
			luup.log(HEATMISER_LOG.."No IP Address")
			ip_missing = 1
  		end
		if (luup.variable_get(HEATMISER_SERVICE, "PIN", lul_device) == nil) then
			luup.task(HEATMISER_LOG.."Enter a 4-digit PIN", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
			luup.log(HEATMISER_LOG.."No PIN")
			luup.variable_set(HEATMISER_SERVICE, "PIN", "", lul_device)
			pin_missing = 1
  		end
  		if (ip_missing == 1) or (pin_missing == 1) then
  			return false
  		end
  		ipAddress = luup.devices[lul_device].ip
		luup.log(HEATMISER_LOG.."Wi-Fi Device on "..ipAddress..":"..ipPort)
		
  		PIN = luup.variable_get(HEATMISER_SERVICE, "PIN", lul_device)
  		
  		luup.variable_set(HEATMISER_SERVICE, "Version", HEATMISER_VERSION, lul_device)
  		
  		luup.variable_set(HOME_AUTO_SERVICE, "CommFailure", "0", lul_device)
  		comm_failure = 0
  		
  		luup.variable_set(HEATMISER_SERVICE, "CRCErrors", "0", lul_device)
    	errorsCRC = 0
    	
    	if (luup.variable_get(HEATMISER_SERVICE, "PollFrequency", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "PollFrequency", "30", lul_device)
			pollFrequency = 30
		else
			pollFString = luup.variable_get(HEATMISER_SERVICE, "PollFrequency", lul_device)
			pollFrequency = tonumber(pollFString)
			if (pollFrequency > 0) and (pollFrequency < 30) then
				pollFrequency = 30
				luup.log(HEATMISER_LOG.."Invalid Poll Frequency - will use default")
			end
  		end
  		    	
    	if (luup.variable_get(HEATMISER_SERVICE, "SetHoldMins", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "SetHoldMins", "0", lul_device)
			setHoldMins = 0
		else
			setHoldMins = luup.variable_get(HEATMISER_SERVICE, "SetHoldMins", lul_device)
  		end
  		
  		if (luup.variable_get(HEATMISER_SERVICE, "SetHoldHours", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "SetHoldHours", "1", lul_device)
			setHoldHours = 1
		else
			setHoldHours = luup.variable_get(HEATMISER_SERVICE, "SetHoldHours", lul_device)
  		end
  		
		if (luup.variable_get(HEATMISER_SERVICE, "SetHoldTemp", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "SetHoldTemp", "20", lul_device)
			setHoldTemp = 20
		else
			setHoldTemp = luup.variable_get(HEATMISER_SERVICE, "SetHoldTemp", lul_device)
  		end
    	
    	if (luup.variable_get(HEATMISER_SERVICE, "TimeSyncEnable", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "TimeSyncEnable", "0", lul_device)
			timeSyncEnable = "0"
		else
			timeSyncEnable = luup.variable_get(HEATMISER_SERVICE, "TimeSyncEnable", lul_device)
  		end

    	if (luup.variable_get(HEATMISER_SERVICE, "TimeSyncHour", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "TimeSyncHour", "3", lul_device)
			timeSyncHour = 3
		else
			timeSHString = luup.variable_get(HEATMISER_SERVICE, "TimeSyncHour", lul_device)
			timeSyncHour = tonumber(timeSHString)
			if (timeSyncHour < 0) or (timeSyncHour > 23) then
				timeSyncHour = 3
				luup.variable_set(HEATMISER_SERVICE, "TimeSyncHour", "3", lul_device)
				luup.log(HEATMISER_LOG.."Invalid Time Sync Hour - will use default")
			end
  		end
  		  		
  		if (luup.variable_get(HEATMISER_SERVICE, "LoggingEnable", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "LoggingEnable", "1", lul_device)
			loggingEnable = 1
		else
			loggingEnable = luup.variable_get(HEATMISER_SERVICE, "LoggingEnable", lul_device)
  		end
  		
  		if (luup.variable_get(HEATMISER_SERVICE, "TempUnits", lul_device) == nil) then
			luup.variable_set(HEATMISER_SERVICE, "TempUnits", "", lul_device)
			tempUnits = ""
		else
			tempUnits = luup.variable_get(HEATMISER_SERVICE, "TempUnits", lul_device)
  		end
		
		if pollFrequency > 0 then
			luup.variable_set(HEATMISER_SERVICE, "HeatStateText", "", lug_device)
			luup.variable_set(HVAC_OPERATING_SERVICE, "ModeState", "", lug_device)
			luup.call_timer('routinePoll', 1, "2", "")
		else
			luup.variable_set(HEATMISER_SERVICE, "HeatStateText", "DISABLED", lug_device)
		end
		
		if (pollFrequency > 0 and timeSyncEnable == "1") then
			luup.call_timer('setHeatmiserTime', 1, "10", "")
		end
		
		cs_change = 1
		luup.set_failure(false)
  		luup.log(HEATMISER_LOG.."Startup complete")
	end



	-- Poll device at specified poll frequency
	function routinePoll()
		luup.call_timer('routinePoll', 1, pollFrequency, "")
		message_type = heatmiser_poll
		frameSend(frameGenerate(FUNCTION_READ, 11, DCBPNT_START, DCBPNT_ALL, ""))
	end



	-- Sync Heatmiser time with Vera
	function setHeatmiserTime()
		luup.call_timer('setHeatmiserTime', 1, "1h", "")
		local cmdFrame
		local Now = os.date("*t")
		if Now.hour == timeSyncHour then
			Now.year = Now.year - 2000
			Now.wday = Now.wday - 1
			if Now.wday == 0 then
				Now.wday = 7
			end
			cmdFrame = Dec2Hex(Now.year)..Dec2Hex(Now.month)..Dec2Hex(Now.day)..Dec2Hex(Now.wday)..Dec2Hex(Now.hour)..Dec2Hex(Now.min)..Dec2Hex(Now.sec)
			message_type = heatmiser_cmd
			frameSend(frameGenerate(FUNCTION_WRITE, 18, DCBUNQ_SETTIME, 7, cmdFrame))
			luup.log(HEATMISER_LOG.."Time sync complete")
		end
	end



	-- Heatmiser On/Off
	function setOnOff(lul_device,lul_settings)
		local cmdFrame
		local State = tonumber(lul_settings['OnOffState'])
		if(State ~= 0) then
			State = 1
	 	end
  		cmdFrame = Dec2Hex(State)
  		message_type = heatmiser_cmd
		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_ONOFF, 1, cmdFrame))
		luup.log(HEATMISER_LOG.."SetOnOff " .. lul_settings['OnOffState'])
	end
	


	-- Send new temperature setpoint to Heatmiser
	function setCurrentSetpoint(lul_device,lul_settings)
		local cmdFrame
		local Temp = math.floor(lul_settings['NewCurrentSetpoint'])
		local Diff = lul_settings['NewCurrentSetpoint'] - Temp
		if (Diff > 0.01) then
			Handle = luup.task("Cannot accept fractions of a degree. Rounding down to "..Temp.."deg", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
  			luup.log(HEATMISER_LOG.."Cannot accept fractions of a degree. Rounding down to "..Temp.."deg")
  		elseif (Handle ~= 0) then
  			luup.task("OK", 4, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), Handle)
  			Handle = 0
  		end
  		if (Temp < lo_temp_limit) then
			Temp = lo_temp_limit
			luup.task(HEATMISER_LOG.."Setpoint too low", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
			luup.log(HEATMISER_LOG.."Temperature setpoint too low")
  		elseif (Temp > hi_temp_limit) then
    		Temp = hi_temp_limit
    		luup.task(HEATMISER_LOG.."Setpoint too high", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
    		luup.log(HEATMISER_LOG.."Temperature setpoint too high")
  		end
  		cmdFrame = Dec2Hex(Temp)
  		message_type = heatmiser_cmd
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_SETTEMP, 1, cmdFrame))
  		luup.log(HEATMISER_LOG.."SetCurrentSetpoint " .. Temp)
	end



	-- Send new temperature hold time (minutes) to Heatmiser
	function setHoldTime(lul_device,lul_settings)
  		local cmdFrame
  		local Time = tonumber(lul_settings['HoldTime'])
  		if(Time < 0) then
    		Time = 0
  		elseif(Time > 32000) then
    		Time = 0
  		end
  		cmdFrame = Dec2Hex(bit.band(Time,255))..Dec2Hex(bit.band(bit.rshift(Time,8),255))
  		message_type = heatmiser_cmd
  		frameSend(frameGenerate(FUNCTION_WRITE, 13, DCBUNQ_TEMPHOLDMINS, 2, cmdFrame))
  		luup.log(HEATMISER_LOG.."SetHoldTime " .. lul_settings['HoldTime'])
	end



	-- Send new frost temperature setting to Heatmiser
	function setFrostTemp(lul_device,lul_settings)
		local cmdFrame
		local Temp = tonumber(lul_settings['FrostTemp'])
  		if (Temp < lo_frost_limit) then
			Temp = lo_frost_limit
			luup.task(HEATMISER_LOG.."Setpoint too low", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
			luup.log(HEATMISER_LOG.."Frost setpoint too low")
  		elseif (Temp > hi_frost_limit) then
    		Temp = hi_frost_limit
    		luup.task(HEATMISER_LOG.."Setpoint too high", 2, string.format("%s[%d]", luup.devices[lul_device].description, lul_device), -1)
    		luup.log(HEATMISER_LOG.."Frost setpoint too high")
  		end
  		cmdFrame = Dec2Hex(Temp)
  		message_type = heatmiser_cmd
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_FROSTTEMP, 1, cmdFrame))
  		luup.log(HEATMISER_LOG.."SetFrostTemp " .. lul_settings['FrostTemp'])
	end



	-- Enable Keylock on Heatmiser
	function setKeyLock(lul_device,lul_settings)
  		local cmdFrame
  		local State = tonumber(lul_settings['KeyState'])
  		if(State ~= 0) then
    		State = 1
  		end
  		cmdFrame = Dec2Hex(State)
  		message_type = heatmiser_cmd
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_KEYLOCK, 1, cmdFrame))
  		luup.log(HEATMISER_LOG.."SetKeyLock " .. lul_settings['KeyState'])
	end



	-- Set Heatmiser Run Mode (00 = Normal, 01 = Frost Protection)
	function setRunMode(lul_device,lul_settings)
  		local cmdFrame
  		State = tonumber(lul_settings['FrostState'])
  		if(State ~= 0) then
    		State = 1
  		end
  		cmdFrame = Dec2Hex(State)
  		message_type = heatmiser_cmd
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_RUNMODE, 1, cmdFrame))
  		luup.log(HEATMISER_LOG.."SetRunMode " .. lul_settings['FrostState'])
	end


	-- Set Heatmiser HW Mode (0 = Auto, 1 = On, 2 = Off)   ** Note:  PRTHW model only! **
	function setHWMode(lul_device,lul_settings)
		if model ~= 4 then
			luup.log(HEATMISER_LOG.."SetHWMode on non-HW model is invalid")
			return false
		end
  		local cmdFrame
  		local hw_mode = 0
  		local new_mode = lul_settings['NewHWMode']
  		if new_mode == "Auto" then hw_mode = 0 end
		if new_mode == "On" then hw_mode = 1 end
		if new_mode == "Off" then hw_mode = 2 end
  		cmdFrame = Dec2Hex(hw_mode)
  		message_type = heatmiser_cmd
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBUNQ_HWSTATE, 1, cmdFrame))
  		luup.log(HEATMISER_LOG.."SetHWMode " .. lul_settings['NewHWMode'])
	end


	-- Set Heatmiser according to short-cut buttons on device
	function setCurrentMode(lul_device,lul_settings)

		local mode_target = lul_settings['NewModeTarget']
		message_type = heatmiser_cmd
		
		if(mode_target == "Off") then
	  	-- Set On/Off to 0
		cmdFrame = Dec2Hex(0)
		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_ONOFF, 1, cmdFrame))
		
	  elseif(mode_target == "AutoChangeOver") then
	  	-- Set Hold Time to 0, Run Mode to 0 and On/Off to 1
	  	local Time = 0
		cmdFrame = Dec2Hex(bit.band(Time,255))..Dec2Hex(bit.band(bit.rshift(Time,8),255))
  		frameSend(frameGenerate(FUNCTION_WRITE, 13, DCBUNQ_TEMPHOLDMINS, 2, cmdFrame))
		cmdFrame = Dec2Hex(0)
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_RUNMODE, 1, cmdFrame))
  		cmdFrame = Dec2Hex(1)
		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_ONOFF, 1, cmdFrame))
		
	  elseif(mode_target == "BuildingProtection") then
	  	-- Set Hold Time to 0, Run Mode to 1 and On/Off to 1
	  	local Time = 0
		cmdFrame = Dec2Hex(bit.band(Time,255))..Dec2Hex(bit.band(bit.rshift(Time,8),255))
  		frameSend(frameGenerate(FUNCTION_WRITE, 13, DCBUNQ_TEMPHOLDMINS, 2, cmdFrame))
		cmdFrame = Dec2Hex(1)
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_RUNMODE, 1, cmdFrame))
		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_ONOFF, 1, cmdFrame))
		
	  elseif(mode_target == "HeatOn") then
	  	-- Set Temp Setpoint and Hold Time to selected values, Run Mode to 0 and On/Off to 1
	  	setHoldTemp = luup.variable_get(HEATMISER_SERVICE, "SetHoldTemp", lul_device) 
  		local Temp = tonumber(setHoldTemp)
  		if (Temp < lo_temp_limit) then
			Temp = lo_temp_limit
			luup.log(HEATMISER_LOG.."Temperature setpoint too low")
  		elseif (Temp > hi_temp_limit) then
    		Temp = hi_temp_limit
    		luup.log(HEATMISER_LOG.."Temperature setpoint too high")
  		end
  		cmdFrame = Dec2Hex(Temp)
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_SETTEMP, 1, cmdFrame))
		cmdFrame = Dec2Hex(0)
  		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_RUNMODE, 1, cmdFrame))
  		cmdFrame = Dec2Hex(1)
		frameSend(frameGenerate(FUNCTION_WRITE, 12, DCBPNT_ONOFF, 1, cmdFrame))
		local Time = (tonumber(setHoldHours) * 60) + tonumber(setHoldMins)
	  	if(Time < 0) then
    		Time = 0
  		elseif(Time > 32000) then
    		Time = 0
  		end
		cmdFrame = Dec2Hex(bit.band(Time,255))..Dec2Hex(bit.band(bit.rshift(Time,8),255))
  		frameSend(frameGenerate(FUNCTION_WRITE, 13, DCBUNQ_TEMPHOLDMINS, 2, cmdFrame))
	  end
	  	luup.variable_set(HVAC_USER_SERVICE, "ModeStatus", mode_target, lul_device)
		luup.log(HEATMISER_LOG.."SetCurrentMode " .. mode_target)
	end



	-- Build message to send to Heatmiser device
	-- Note:  Only send one block of items at a time for now
	function frameGenerate(Function, FrameLen, Start, Length, Data)
		local OutFrame = ""
  		local Items = 1
  		
  		OutFrame = OutFrame..Dec2Hex(Function)
  		
		OutFrame = OutFrame..Dec2Hex(bit.band(FrameLen, 255))
  		OutFrame = OutFrame..Dec2Hex(bit.band(bit.rshift(FrameLen, 8), 255))
  
  		OutFrame = OutFrame..Dec2Hex(bit.band(PIN, 255))
  		OutFrame = OutFrame..Dec2Hex(bit.band(bit.rshift(PIN, 8), 255))
  		
  		if Function == FUNCTION_READ then

  			OutFrame = OutFrame..Dec2Hex(bit.band(Start, 255))
  			OutFrame = OutFrame..Dec2Hex(bit.band(bit.rshift(Start, 8), 255))

  			OutFrame = OutFrame..Dec2Hex(bit.band(Length, 255))
  			OutFrame = OutFrame..Dec2Hex(bit.band(bit.rshift(Length, 8), 255))
  		
  		else
  			
  			OutFrame = OutFrame..Dec2Hex(Items)
  		
  			OutFrame = OutFrame..Dec2Hex(bit.band(Start, 255))
  			OutFrame = OutFrame..Dec2Hex(bit.band(bit.rshift(Start, 8), 255))
  			
  			OutFrame = OutFrame..Dec2Hex(Length)
  			
  		end

  		OutFrame = OutFrame..Data
  		
  		csum1, csum2 = CRC16(OutFrame, #OutFrame)
  		OutFrame = OutFrame..Dec2Hex(csum1)..Dec2Hex(csum2)

  		return OutFrame
	end



	-- Send command to Heatmiser and receive/process the reply
	function frameSend(OutFrame)
		binCnt= 0
  		binData = ""
  		for cnt = 1, #OutFrame, 2 do
    		val = tonumber(string.sub(OutFrame, cnt, cnt+1),16)
    		if 0 == val then
      			binData = binData.."\00"
    		else
     			binData = binData..string.format("%c", val)
    		end
		end
		heatmiserLogDCB(DCBtoString(binData), "-->", message_type)
		local tcp = assert(socket.tcp())
		if (tcp ~= "nil" and tcp ~= nill) then
			tcp:settimeout(5)
			tcp:connect(ipAddress, ipPort)
			tcp:send(binData)
			incomingDCB, err = tcp:receive(81)
			luup.sleep(100)
			tcp:close()
			if not err then
      			heatmiserLogDCB(DCBtoString(incomingDCB), "<--", message_type)
      			incomingDCB = string.sub(incomingDCB, 8, -3)
      			processDCB()
				incomingDCB = ""
			else
				luup.log(HEATMISER_LOG.."No response from Heatmiser")
				comm_failure = comm_failure + 1
				luup.variable_set(HOME_AUTO_SERVICE, "CommFailure", comm_failure, lug_device)
				luup.variable_set(HEATMISER_SERVICE, "HeatStateText", "COMM T/OUT", lug_device)
				-- Set flag to force database update when comms recovers
				cs_change = 1
			end
		else
			luup.log(HEATMISER_LOG.."Can't connect to Heatmiser")
			comm_failure = comm_failure + 1
			luup.variable_set(HOME_AUTO_SERVICE, "CommFailure", comm_failure, lug_device)
			luup.variable_set(HEATMISER_SERVICE, "HeatStateText", "COMM FAIL", lug_device)
			-- Set flag to force database update when comms recovers
			cs_change = 1
		end
      end



	-- Read a byte from the DCB
	function dcbReadByte(incomingDCB, start)
		return tonumber (string.byte(string.sub(incomingDCB, start, start)))
	end



	-- Read temperature from DCB and divide by ten to get deg C
	function dcbReadTemp(incomingDCB, start)
		local temp_lo_byte = tonumber (string.byte(string.sub(incomingDCB, start, start)))
		local temp_hi_byte = tonumber (string.byte(string.sub(incomingDCB, start+1, start+1)))
		return (temp_lo_byte + (temp_hi_byte * 256)) / 10
	end



	-- Process received DCB
	function processDCB()
		local tempHold = dcbReadByte(incomingDCB, DCBPNT_TEMPHOLDMINS+1) + dcbReadByte(incomingDCB, DCBPNT_TEMPHOLDMINS+2)*256
		local onoff_status = dcbReadByte(incomingDCB, DCBPNT_ONOFF+1)
		local keylock_status = dcbReadByte(incomingDCB, DCBPNT_KEYLOCK+1)
		local runmode_status = dcbReadByte(incomingDCB, DCBPNT_RUNMODE+1)
		local sensor_sel = dcbReadByte(incomingDCB, DCBPNT_SENSOR_SEL+1)
		local frost_temp = dcbReadByte(incomingDCB, DCBPNT_FROSTTEMP+1)
		local heat_state = dcbReadByte(incomingDCB, DCBPNT_HEATSTATE+1)
		local floor_temp = dcbReadTemp(incomingDCB, DCBPNT_FLOORTEMP+1)
		local room_temp = dcbReadTemp(incomingDCB, DCBPNT_ROOMTEMP+1)
		local remote_temp = dcbReadTemp(incomingDCB, DCBPNT_REMOTETEMP+1)
		local set_temp = dcbReadByte(incomingDCB, DCBPNT_SETTEMP+1)
		local tempFormat = dcbReadByte(incomingDCB, DCBPNT_TEMP_FORMAT+1)
		local mode_status = ""
		if cs_change ~= 0 then
			model = dcbReadByte(incomingDCB, DCBPNT_MODEL+1)
			if model == 0 then
				model_text = "DT"
			elseif model == 1 then
				model_text = "DT-E"
			elseif model == 2 then
				model_text = "PRT"
			elseif model == 3 then
				model_text = "PRT-E"
			elseif model == 4 then
				model_text = "PRTHW"
			elseif model == 5 then
				model_text = "TM1"
			else model_text = "Unknown"
			end
			luup.variable_set(HEATMISER_SERVICE, "Model", model_text, lug_device)
		end
		if tempFormat ~= last_tempFormat or cs_change ~= 0 then
			if tempFormat == 0 then
				tempUnits = "degC"
				lo_temp_limit = 5
				hi_temp_limit = 35
				lo_frost_limit = 7
				hi_frost_limit = 17
			else
				tempUnits = "degF"
				lo_temp_limit = 41
				hi_temp_limit = 95
				lo_frost_limit = 45
				hi_frost_limit = 62
			end
			luup.variable_set(HEATMISER_SERVICE, "TempUnits", tempUnits, lug_device)
			last_tempFormat = tempFormat
		end		
		if tempHold ~= last_tempHold or cs_change ~= 0 then
			luup.variable_set(HEATMISER_SERVICE, "TempHold", tempHold, lug_device)
			last_tempHold = tempHold
		end
		if onoff_status ~= last_onoff_status or cs_change ~= 0 then
			luup.variable_set(HEATMISER_SERVICE, "OnOff", onoff_status, lug_device)
			last_onoff_status = onoff_status
		end
		if keylock_status ~= last_keylock_status or cs_change ~= 0 then
			luup.variable_set(HEATMISER_SERVICE, "KeyLock", keylock_status, lug_device)
			last_keylock_status = keylock_status
		end
		if runmode_status ~= last_runmode_status or cs_change ~= 0 then
			luup.variable_set(HEATMISER_SERVICE, "RunMode", runmode_status, lug_device)
			last_runmode_status = runmode_status
		end
		if frost_temp ~= last_frost_temp or cs_change ~= 0 then
			luup.variable_set(HEATMISER_SERVICE, "FrostTemp", frost_temp, lug_device)
			last_frost_temp = frost_temp
		end
		if heat_state ~= last_heat_state or cs_change ~= 0 then
			luup.variable_set(HEATMISER_SERVICE, "HeatingState", heat_state, lug_device)
			last_heat_state = heat_state
			hs_change = 1
		end
		if sensor_sel ~= last_sensor_sel or cs_change ~= 0 then
			if sensor_sel == 0 then
				sensor = "Internal Air"
			elseif sensor_sel == 1 then
				sensor = "Remote Air"
			elseif sensor_sel == 2 then
				sensor = "Floor"
			elseif sensor_sel == 3 then
				sensor = "Floor & Internal Air"
			elseif sensor_sel == 4 then
				sensor = "Floor & Remote Air"
			end
			luup.variable_set(HEATMISER_SERVICE, "SensorSelect", sensor, lug_device)
			last_sensor_sel = sensor_sel
		end
		local cur_temp = 0
		if sensor_sel == 0 then
			cur_temp = room_temp
		elseif sensor_sel == 1 then
			cur_temp = remote_temp
		elseif sensor_sel == 2 then
			cur_temp = floor_temp
		elseif sensor_sel == 3 then
			cur_temp = room_temp
		elseif sensor_sel == 4 then
			cur_temp = remote_temp
		end
		if cur_temp ~= last_cur_temp or cs_change ~= 0 then
			luup.variable_set(TEMPERATURE_SERVICE, "CurrentTemperature", cur_temp, lug_device)
			last_cur_temp = cur_temp
		end
		if set_temp ~= last_set_temp or cs_change ~= 0 then
			luup.variable_set(TEMPERATURE_SETPOINT, "CurrentSetpoint", set_temp, lug_device)
			last_set_temp = set_temp
		end
		luup.variable_set(HOME_AUTO_SERVICE, "LastUpdate", os.date("%H:%M:%S"), lug_device)
		
		-- Set heating state to display on device dashboard
		if hs_change ~= 0 or cs_change ~= 0 then
			if heat_state == 1 then
				luup.variable_set(HEATMISER_SERVICE, "HeatStateText", "HEATING ON", lug_device)
				luup.variable_set(HVAC_OPERATING_SERVICE, "ModeState", "Heating", lug_device)
			else
				luup.variable_set(HEATMISER_SERVICE, "HeatStateText", "", lug_device)
				luup.variable_set(HVAC_OPERATING_SERVICE, "ModeState", "Idle", lug_device)
			end
			hs_change = 0
		end
		
		-- Get HW state if this is a HW model
		if model == 4 then
			local hw_state = dcbReadByte(incomingDCB, DCBPNT_HWSTATE+1)
			local hw_state_text
			if hw_state ~= last_hw_state or cs_change ~= 0 then
				if hw_state == 0 then
					hw_state_text = "Off"
				else
					hw_state_text = "On"
				end
				luup.variable_set(HEATMISER_SERVICE, "HWState", hw_state_text, lug_device)
				last_hw_state = hw_state
			end
		end
		
		-- Reset 'force database update' flag after first good data following comms recovery
		cs_change = 0

		if (comm_failure ~= 0) then
  			comm_failure = 0
			luup.variable_set(HOME_AUTO_SERVICE, "CommFailure", comm_failure, lug_device)
		end
		
		-- Set device buttons to reflect actual conditions
		if (onoff_status == 0) then
			mode_status = "Off"
		elseif (onoff_status == 1) and (runmode_status == 0) and (tempHold == 0) then
			mode_status = "AutoChangeOver"
		elseif (onoff_status == 1) and (runmode_status == 1) and (tempHold == 0) then
			mode_status = "BuildingProtection"
		elseif (onoff_status == 1) and (runmode_status == 0) and (tempHold > 0) then	
			mode_status = "HeatOn"
		end
		if mode_status ~= last_mode_status then
			luup.variable_set(HVAC_USER_SERVICE, "ModeStatus", mode_status, lug_device)
			last_mode_status = mode_status
		end
	end



    -- Log DCBs to a file
    function heatmiserLogDCB(DCB, direction, msg_type)
    	if (loggingEnable == "1") then
			local logfile = '/var/log/cmh/heatmiserDCB.log'
			-- empty file if it reaches 100kb
			local outf = io.open(logfile , 'a')
			local filesize = outf:seek("end")
			outf:close()
			if (filesize > 100000) then
   				local outf = io.open(logfile , 'w')
   				outf:write('')
   				outf:close()
			end
			local outf = io.open(logfile, 'a')
			local mtype = " (" .. message_type .. ") "
			local sep = "   "
			outf:write(os.date('%d/%m %H:%M:%S'))
			outf:write(sep)
			outf:write(direction)
			outf:write(mtype)
			if DCB == nil then DCB = "?" end
			outf:write(DCB)
			outf:write('\n')
			if direction == "<--" then outf:write('\n') end
				outf:close()
		end
	end
	
	
    -- Convert DCB bytes to a string for logging 
    function DCBtoString(DCB)
		local DCBstr = string.char()
		for i = 1, string.len(DCB) do
			DCBstr = DCBstr .. string.format("%02X ", string.byte(string.sub(DCB, i, i)))
		end
	 	return DCBstr
    end



	-- Convert a value from decimal to hex
	function Dec2Hex(nValue)
	  if(nValue == nil) then
	    luup.log(HEATMISER_LOG.."nil in Dec2Hex")
	    return "00"
	  end
	  if(nValue < 16) then
	  	nHexVal = "0"
	  else
		nHexVal = ""
	  end
  	  return nHexVal..string.format("%X", nValue);  -- %X returns uppercase hex, %x gives lowercase letters
	end



	-- Heatmiser CRC functions
	local CRC16_LookupHigh = {0,16,32,48,64,80,96,112,129,145,161,177,193,209,225,241}
	local CRC16_LookupLow  = {0,33,66,99,132,165,198,231,8,41,74,107,140,173,206,239}
	local CRC16_High
	local CRC16_Low


	function CRC16(buf, len)
  		CRC16_High = 255
		CRC16_Low  = 255
  		for cnt = 1, len, 2 do
   			val = tonumber(string.sub(buf, cnt, cnt+1),16)
			CRC16_Update(val)
		end
  		return CRC16_Low, CRC16_High
	end


	function CRC16_Update4Bits(val)
  		local  t
		t = bit.band(bit.rshift(CRC16_High, 4), 15)
  		t = bit.band(bit.bxor(t, val), 15) + 1
  		CRC16_High = bit.band(bit.bor(bit.lshift(CRC16_High, 4), bit.rshift(CRC16_Low, 4)), 255)
  		CRC16_Low  = bit.band(bit.lshift(CRC16_Low, 4),255)
  		CRC16_High = bit.band(bit.bxor(CRC16_High, CRC16_LookupHigh[t]), 255)
  		CRC16_Low  = bit.band(bit.bxor(CRC16_Low, CRC16_LookupLow[t]), 255)
	end

	
	function CRC16_Update(val)
  		CRC16_Update4Bits(bit.rshift(val, 4))
  		CRC16_Update4Bits(bit.band(val, 15))
	end



