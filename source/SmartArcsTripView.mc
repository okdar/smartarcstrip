/*
    This file is part of SmartArcs Trip watch face.
    https://github.com/okdar/smartarcstrip

    SmartArcs Trip is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SmartArcs Trip is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with SmartArcs Trip. If not, see <https://www.gnu.org/licenses/gpl.html>.
*/

using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Position;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SmartArcsTripView extends WatchUi.WatchFace {

    //TRYING TO KEEP AS MUCH PRE-COMPUTED VALUES AS POSSIBLE IN MEMORY TO SAVE CPU UTILIZATION
    //AND HOPEFULLY PROLONG BATTERY LIFE. PRE-COMPUTED VARIABLES DON'T NEED TO BE COMPUTED
    //AGAIN AND AGAIN ON EACH SCREEN UPDATE. THAT'S THE REASON FOR LONG LIST OF GLOBAL VARIABLES.

    //global variables
    var isAwake = false;
    var partialUpdatesAllowed = false;
    var hasElevationHistory = false;
    var hasPressureHistory = false;
    var hasHeartRateHistory = false;
    var hasTemperatureHistory = false;
    var elevationNumberOfSamples = 0;
    var pressureNumberOfSamples = 0;
    var heartRateNumberOfSamples = 0;
    var temperatureNumberOfSamples = 0;
    var curClip;
    var fullScreenRefresh;
    var offscreenBuffer;
    var offSettingFlag = -999;
    var font = Graphics.FONT_TINY;
    var lastMeasuredHR;
    var deviceSettings;
    var powerSaverDrawn = false;
    var sunArcsOffset;

    //global variables for pre-computation
    var screenWidth;
    var screenRadius;
    var screenResolutionRatio;
    var ticks;
    var hourHandLength;
    var minuteHandLength;
    var handsTailLength;
    var hrTextDimension;
    var halfHRTextWidth;
    var startPowerSaverMin;
    var endPowerSaverMin;
    var powerSaverIconRatio;
	var sunriseStartAngle = 0;
	var sunriseEndAngle = 0;
	var sunsetStartAngle = 0;
	var sunsetEndAngle = 0;
	var locationLatitude;
	var locationLongitude;

    //user settings
    var bgColor;
    var handsColor;
    var handsOutlineColor;
    var hourHandWidth;
    var minuteHandWidth;
    var battery100Color;
    var battery30Color;
    var battery15Color;
    var notificationColor;
    var bluetoothColor;
    var dndColor;
    var alarmColor;
    var dateColor;
    var ticksColor;
    var ticks1MinWidth;
    var ticks5MinWidth;
    var ticks15MinWidth;
    var oneColor;
    var handsOnTop;
    var showBatteryIndicator;
    var dateFormat;
    var hrColor;
    var hrRefreshInterval;
    var upperField;
    var upperGraph;
    var bottomGraph;
    var bottomField;
    var graphBordersColor;
    var graphLegendColor;
    var graphLineColor;
    var graphLineWidth;
    var graphCurrentValueColor;
    var powerSaver;
    var powerSaverRefreshInterval;
    var powerSaverIconColor;
    var sunriseColor;
    var sunsetColor;

    function initialize() {
        WatchFace.initialize();
    }

    //load resources here
    function onLayout(dc) {
        //if this device supports BufferedBitmap, allocate the buffers we use for drawing
        if (Toybox.Graphics has :BufferedBitmap) {
            //Allocate a full screen size buffer to draw the background image of the watchface.
            //This is used to facilitate blanking the second hand during partial updates of the display
            offscreenBuffer = new Graphics.BufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
        } else {
            offscreenBuffer = null;
        }

        partialUpdatesAllowed = (Toybox.WatchUi.WatchFace has :onPartialUpdate);

        if (Toybox has :SensorHistory) {
            if (Toybox.SensorHistory has :getElevationHistory) {
                hasElevationHistory = true;
            }
            if (Toybox.SensorHistory has :getPressureHistory) {
                hasPressureHistory = true;
            }
            if (Toybox.SensorHistory has :getHeartRateHistory) {
                hasHeartRateHistory = true;
            }
            if (Toybox.SensorHistory has :getTemperatureHistory) {
                hasTemperatureHistory = true;
            }
        }

        loadUserSettings();
        computeConstants(dc);
		computeSunConstants();
        fullScreenRefresh = true;

        curClip = null;
    }

    //called when this View is brought to the foreground. Restore
    //the state of this View and prepare it to be shown. This includes
    //loading resources into memory.
    function onShow() {
    }

    //update the view
    function onUpdate(dc) {
        var clockTime = System.getClockTime();

		//refresh whole screen before drawing power saver icon
        if (powerSaverDrawn && shouldPowerSave()) {
            //should be screen refreshed in given intervals?
            if (powerSaverRefreshInterval == offSettingFlag || !(clockTime.min % powerSaverRefreshInterval == 0)) {
                return;
            }
        }

        powerSaverDrawn = false;

        deviceSettings = System.getDeviceSettings();

		if (clockTime.min == 0) {
            //recompute sunrise/sunset constants every hour - to address new location when traveling	
			computeSunConstants();
		}

        //we always want to refresh the full screen when we get a regular onUpdate call.
        fullScreenRefresh = true;

        var targetDc = null;
        if (offscreenBuffer != null) {
            dc.clearClip();
            curClip = null;
            //if we have an offscreen buffer that we are using to draw the background,
            //set the draw context of that buffer as our target.
            targetDc = offscreenBuffer.getDc();
        } else {
            targetDc = dc;
        }

        //clear the screen
        targetDc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        targetDc.fillCircle(screenRadius, screenRadius, screenRadius + 2);

        if (showBatteryIndicator) {
            var batStat = System.getSystemStats().battery;
            if (oneColor != offSettingFlag) {
                drawSmartArc(targetDc, oneColor, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
            } else {
                if (batStat > 30) {
                    drawSmartArc(targetDc, battery100Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                    drawSmartArc(targetDc, battery30Color, Graphics.ARC_CLOCKWISE, 180, 153);
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 166.5);
                } else if (batStat <= 30 && batStat > 15) {
                    drawSmartArc(targetDc, battery30Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 166.5);
                } else {
                    drawSmartArc(targetDc, battery15Color, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                }
            }
        }

        var itemCount = deviceSettings.notificationCount;
        if (notificationColor != offSettingFlag && itemCount > 0) {
            if (itemCount < 11) {
                drawSmartArc(targetDc, notificationColor, Graphics.ARC_CLOCKWISE, 90, 90 - 30 - ((itemCount - 1) * 6));
            } else {
                drawSmartArc(targetDc, notificationColor, Graphics.ARC_CLOCKWISE, 90, 0);
            }
        }

        if (bluetoothColor != offSettingFlag && deviceSettings.phoneConnected) {
            drawSmartArc(targetDc, bluetoothColor, Graphics.ARC_CLOCKWISE, 0, -30);
        }

        if (dndColor != offSettingFlag && deviceSettings.doNotDisturb) {
            drawSmartArc(targetDc, dndColor, Graphics.ARC_COUNTER_CLOCKWISE, 270, -60);
        }

        itemCount = deviceSettings.alarmCount;
        if (alarmColor != offSettingFlag && itemCount > 0) {
            if (itemCount < 11) {
                drawSmartArc(targetDc, alarmColor, Graphics.ARC_CLOCKWISE, 270, 270 - 30 - ((itemCount - 1) * 6));
            } else {
                drawSmartArc(targetDc, alarmColor, Graphics.ARC_CLOCKWISE, 270, 0);
            }
        }

        if (locationLatitude != offSettingFlag) {
    	    drawSun(targetDc);
        }

        if (ticks != null) {
            drawTicks(targetDc);
        }

        if (!handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        if (hasElevationHistory) {
            if (upperField == 2 || bottomField == 2) {
                var iter = SensorHistory.getElevationHistory({});
                if (iter != null) {
                    var item = iter.next();
                    var value = null;
                    if (item != null) {
                        value = item.data;
                    }
                    if (value != null && graphCurrentValueColor != offSettingFlag) {
                        targetDc.setColor(graphCurrentValueColor, Graphics.COLOR_TRANSPARENT);
                        if (deviceSettings.elevationUnits == System.UNIT_STATUTE) {
                            value = convertM_Ft(value);
                        }
                        if (upperField == 2) {
                            targetDc.drawText(screenRadius, 30, Graphics.FONT_TINY, value.format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
                        }
                        if (bottomField == 2) {
                            targetDc.drawText(screenRadius, screenWidth - Graphics.getFontHeight(font) - 30, Graphics.FONT_TINY, value.format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
                        }
                    }
                }
                iter = null;
            }
            if (upperGraph == 1) {
                if (elevationNumberOfSamples == 0) {
                    elevationNumberOfSamples = countSamples(SensorHistory.getElevationHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getElevationHistory({}), 1, 0, 1.0, 5, true, upperGraph, elevationNumberOfSamples);
            }
            if (bottomGraph == 1) {
                if (elevationNumberOfSamples == 0) {
                    elevationNumberOfSamples = countSamples(SensorHistory.getElevationHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getElevationHistory({}), 2, 0, 1.0, 5, true, bottomGraph, elevationNumberOfSamples);
            }
        }

        if (hasPressureHistory) {
            if (upperField == 3 || bottomField == 3) {
                var iter = SensorHistory.getPressureHistory({});
                if (iter != null) {
                    var item = iter.next();
                    var value = null;
                    if (item != null) {
                        value = item.data;
                    }
                    if (value != null && graphCurrentValueColor != offSettingFlag) {
                        targetDc.setColor(graphCurrentValueColor, Graphics.COLOR_TRANSPARENT);
                        if (upperField == 3) {
                            targetDc.drawText(screenRadius, 30, Graphics.FONT_TINY, (value / 100.0).format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER);
                        }
                        if (bottomField == 3) {
                            targetDc.drawText(screenRadius, screenWidth - Graphics.getFontHeight(font) - 30, Graphics.FONT_TINY, (value / 100.0).format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER);
                        }
                    }
                }
                iter = null;
            }
            if (upperGraph == 2) {
                if (pressureNumberOfSamples == 0) {
                    pressureNumberOfSamples = countSamples(SensorHistory.getPressureHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getPressureHistory({}), 1, 1, 100.0, 2, true, upperGraph, pressureNumberOfSamples);
            }
            if (bottomGraph == 2) {
                if (pressureNumberOfSamples == 0) {
                    pressureNumberOfSamples = countSamples(SensorHistory.getPressureHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getPressureHistory({}), 2, 1, 100.0, 2, true, bottomGraph, pressureNumberOfSamples);
            }
        }

        if (hasHeartRateHistory) {
            if (upperGraph == 3) {
                if (heartRateNumberOfSamples == 0) {
                    heartRateNumberOfSamples = countSamples(SensorHistory.getHeartRateHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getHeartRateHistory({}), 1, 0, 1.0, 5, false,upperGraph, heartRateNumberOfSamples);
            }
            if (bottomGraph == 3) {
                if (heartRateNumberOfSamples == 0) {
                    heartRateNumberOfSamples = countSamples(SensorHistory.getHeartRateHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getHeartRateHistory({}), 2, 0, 1.0, 5, false, bottomGraph, heartRateNumberOfSamples);
            }
        }

        if (hasTemperatureHistory) {
            if (upperField == 4 || bottomField == 4) {
                var iter = SensorHistory.getTemperatureHistory({});
                if (iter != null) {
                    var item = iter.next();
                    var value = null;
                    if (item != null) {
                        value = item.data;
                    }
                    if (value != null && graphCurrentValueColor != offSettingFlag) {
                        targetDc.setColor(graphCurrentValueColor, Graphics.COLOR_TRANSPARENT);
                        if (deviceSettings.temperatureUnits == System.UNIT_STATUTE) {
                            value = convertC_F(value);
                        }
                        if (upperField == 4) {
                            targetDc.drawText(screenRadius, 30, Graphics.FONT_TINY, value.format("%.1f") + StringUtil.utf8ArrayToString([0xC2,0xB0]), Graphics.TEXT_JUSTIFY_CENTER);
                        }
                        if (bottomField == 4) {
                            targetDc.drawText(screenRadius, screenWidth - Graphics.getFontHeight(font) - 30, Graphics.FONT_TINY, value.format("%.1f") + StringUtil.utf8ArrayToString([0xC2,0xB0]), Graphics.TEXT_JUSTIFY_CENTER);
                        }
                    }
                }
                iter = null;
            }
            if (upperGraph == 4) {
                if (temperatureNumberOfSamples == 0) {
                    temperatureNumberOfSamples = countSamples(SensorHistory.getTemperatureHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getTemperatureHistory({}), 1, 1, 1.0, 5, true, upperGraph, temperatureNumberOfSamples);
            }
            if (bottomGraph == 4) {
                if (temperatureNumberOfSamples == 0) {
                    temperatureNumberOfSamples = countSamples(SensorHistory.getTemperatureHistory({}));
                }
                drawGraph(targetDc, SensorHistory.getTemperatureHistory({}), 2, 1, 1.0, 5, true, bottomGraph, temperatureNumberOfSamples);
            }
        }

        targetDc.setColor(graphCurrentValueColor, Graphics.COLOR_TRANSPARENT);
        if (upperField == 1) {
            var distance = ActivityMonitor.getInfo().distance;
            if (deviceSettings.distanceUnits == System.UNIT_STATUTE) {
                distance = convertKm_Mi(distance);
            }
            targetDc.drawText(screenRadius, 30, Graphics.FONT_TINY, (distance/100000.0).format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (bottomField == 1) {
            var distance = ActivityMonitor.getInfo().distance;
            if (deviceSettings.distanceUnits == System.UNIT_STATUTE) {
                distance = convertKm_Mi(distance);
            }
            targetDc.drawText(screenRadius, screenWidth - Graphics.getFontHeight(font) - 30, Graphics.FONT_TINY, (distance/100000.0).format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);
        }

        if (handsOnTop) {
            drawHands(targetDc, clockTime);
        }

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

        if (shouldPowerSave()) {
            drawPowerSaverIcon(dc);
            return;
        }

        if (partialUpdatesAllowed && hrColor != offSettingFlag) {
            onPartialUpdate(dc);
        }

        fullScreenRefresh = false;
    }

    //called when this View is removed from the screen. Save the state
    //of this View here. This includes freeing resources from memory.
    function onHide() {
    }

    //the user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() {
        isAwake = true;
    }

    //terminate any active timers and prepare for slow updates.
    function onEnterSleep() {
        isAwake = false;
        requestUpdate();
    }

    function loadUserSettings() {
        var app = Application.getApp();

        oneColor = app.getProperty("oneColor");
        if (oneColor == offSettingFlag) {
            battery100Color = app.getProperty("battery100Color");
            battery30Color = app.getProperty("battery30Color");
            battery15Color = app.getProperty("battery15Color");
            notificationColor = app.getProperty("notificationColor");
            bluetoothColor = app.getProperty("bluetoothColor");
            dndColor = app.getProperty("dndColor");
            alarmColor = app.getProperty("alarmColor");
            sunriseColor = app.getProperty("sunriseColor");
			sunsetColor = app.getProperty("sunsetColor");
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
            sunriseColor = oneColor;
			sunsetColor = oneColor;
        }
        bgColor = app.getProperty("bgColor");
        ticksColor = app.getProperty("ticksColor");
        if (ticksColor != offSettingFlag) {
            ticks1MinWidth = app.getProperty("ticks1MinWidth");
            ticks5MinWidth = app.getProperty("ticks5MinWidth");
            ticks15MinWidth = app.getProperty("ticks15MinWidth");
        }
        handsColor = app.getProperty("handsColor");
        handsOutlineColor = app.getProperty("handsOutlineColor");
        hourHandWidth = app.getProperty("hourHandWidth");
        minuteHandWidth = app.getProperty("minuteHandWidth");
        dateColor = app.getProperty("dateColor");
        hrColor = app.getProperty("hrColor");

        if (dateColor != offSettingFlag) {
            dateFormat = app.getProperty("dateFormat");
        }

        if (hrColor != offSettingFlag) {
            hrRefreshInterval = app.getProperty("hrRefreshInterval");
        }

        handsOnTop = app.getProperty("handsOnTop");

        showBatteryIndicator = app.getProperty("showBatteryIndicator");

        upperField = app.getProperty("upperField");
        upperGraph = app.getProperty("upperGraph");
        bottomGraph = app.getProperty("bottomGraph");
        bottomField = app.getProperty("bottomField");
        graphCurrentValueColor = app.getProperty("graphCurrentValueColor");
        if (upperGraph > 0 || bottomGraph > 0) {
            graphBordersColor = app.getProperty("graphBordersColor");
            graphLegendColor = app.getProperty("graphLegendColor");
            graphLineWidth = app.getProperty("graphLineWidth");
            if (oneColor == offSettingFlag) {
                graphLineColor = app.getProperty("graphLineColor");
            } else {
                graphLineColor = oneColor;
            }
        }

        var power = app.getProperty("powerSaver");
        if (power == 1) {
        	powerSaver = false;
    	} else {
    		powerSaver = true;
            var powerSaverBeginning;
            var powerSaverEnd;
            if (power == 2) {
                powerSaverBeginning = app.getProperty("powerSaverBeginning");
                powerSaverEnd = app.getProperty("powerSaverEnd");
            } else {
                powerSaverBeginning = "00:00";
                powerSaverEnd = "23:59";
            }
            startPowerSaverMin = parsePowerSaverTime(powerSaverBeginning);
            if (startPowerSaverMin == -1) {
                powerSaver = false;
            } else {
                endPowerSaverMin = parsePowerSaverTime(powerSaverEnd);
                if (endPowerSaverMin == -1) {
                    powerSaver = false;
                }
            }
        }
		powerSaverRefreshInterval = app.getProperty("powerSaverRefreshInterval");
		powerSaverIconColor = app.getProperty("powerSaverIconColor");
		
		locationLatitude = app.getProperty("locationLatitude");
		locationLongitude = app.getProperty("locationLongitude");

        //ensure that screen will be refreshed when settings are changed 
    	powerSaverDrawn = false;   	
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants(dc) {
        screenWidth = dc.getWidth();
        screenRadius = screenWidth / 2;

        //computes hand lenght for watches with different screen resolution than 240x240
        screenResolutionRatio = screenWidth / 240.0;
        hourHandLength = (60 * screenResolutionRatio).toNumber();
        minuteHandLength = (90 * screenResolutionRatio).toNumber();
        handsTailLength = (15 * screenResolutionRatio).toNumber();

        powerSaverIconRatio = screenResolutionRatio; //big icon
        if (powerSaverRefreshInterval != offSettingFlag) {
            powerSaverIconRatio = 0.6 * screenResolutionRatio; //small icon
        }

        if (!((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0))) {
            //array of ticks coordinates
            computeTicks();
        }

        hrTextDimension = dc.getTextDimensions("888", Graphics.FONT_TINY); //to compute correct clip boundaries
        halfHRTextWidth = hrTextDimension[0] / 2;
    }

    function parsePowerSaverTime(time) {
        var pos = time.find(":");
        if (pos != null) {
            var hour = time.substring(0, pos).toNumber();
            var min = time.substring(pos + 1, time.length()).toNumber();
            if (hour != null && min != null) {
                return (hour * 60) + min;
            } else {
                return -1;
            }
        } else {
            return -1;
        }
    }

    function computeTicks() {
        var angle;
        ticks = new [16];
        //to save the memory compute only a quarter of the ticks, the rest will be mirrored.
        //I believe it will still save some CPU utilization
        for (var i = 0; i < 16; i++) {
            angle = i * Math.PI * 2 / 60.0;
            if ((i % 15) == 0) { //quarter tick
                if (ticks15MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 20, ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 17, ticks5MinWidth);
                }
            } else if (ticks1MinWidth > 0) { //1-minute tick
                ticks[i] = computeTickRectangle(angle, 10, ticks1MinWidth);
            }
        }
    }

    function computeTickRectangle(angle, length, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, screenRadius], [-halfWidth, screenRadius - length], [halfWidth, screenRadius - length], [halfWidth, screenRadius]];
        return computeRectangle(coords, angle);
    }

    function computeRectangle(coords, angle) {
        var rect = new [4];
        var x;
        var y;
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        //transform coordinates
        for (var i = 0; i < 4; i++) {
            x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;
            rect[i] = [screenRadius + x, screenRadius + y];
        }

        return rect;
    }

    function drawSmartArc(dc, color, arcDirection, startAngle, endAngle) {
        dc.setPenWidth(10);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(screenRadius, screenRadius, screenRadius - 5, arcDirection, startAngle, endAngle);
    }

    function drawTicks(dc) {
        var coord = new [4];
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 16; i++) {
        	//30-45 ticks
            if (ticks[i] != null) {
                dc.fillPolygon(ticks[i]);
            }

            //mirror pre-computed ticks
            if (i >= 0 && i <= 15 && ticks[i] != null) {
            	//15-30 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], ticks[i][j][1]];
                }
                dc.fillPolygon(coord);

				//45-60 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [ticks[i][j][0], screenWidth - ticks[i][j][1]];
                }
                dc.fillPolygon(coord);

				//0-15 ticks
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], screenWidth - ticks[i][j][1]];
                }
                dc.fillPolygon(coord);
            }
        }
    }

    function drawHands(dc, clockTime) {
        var hourAngle, minAngle;

        //draw hour hand
        hourAngle = ((clockTime.hour % 12) * 60.0) + clockTime.min;
        hourAngle = hourAngle / (12 * 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + 2, handsTailLength + 2, hourHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * Math.PI * 2;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(minAngle, minuteHandLength + 2, handsTailLength + 2, minuteHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(minAngle, minuteHandLength, handsTailLength, minuteHandWidth));

        //draw bullet
        var bulletRadius = hourHandWidth > minuteHandWidth ? hourHandWidth / 2 : minuteHandWidth / 2;
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, bulletRadius + 1);
        dc.setPenWidth(bulletRadius);
        dc.setColor(handsColor,Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(screenRadius, screenRadius, bulletRadius + 2);
    }

    function drawHand(dc, color, coords) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(coords);
    }

    function computeHandRectangle(angle, handLength, tailLength, width) {
        var halfWidth = width / 2;
        var coords = [[-halfWidth, tailLength], [-halfWidth, -handLength], [halfWidth, -handLength], [halfWidth, tailLength]];
        return computeRectangle(coords, angle);
    }

    //Handle the partial update event
    function onPartialUpdate(dc) {
		//refresh whole screen before drawing power saver icon
        if (powerSaverDrawn && shouldPowerSave()) {
    		return;
    	}

        powerSaverDrawn = false;

        var refreshHR = false;
        var clockSeconds = System.getClockTime().sec;

        //should be HR refreshed?
        if (hrColor != offSettingFlag) {
            if (hrRefreshInterval == 1) {
                refreshHR = true;
            } else if (clockSeconds % hrRefreshInterval == 0) {
                refreshHR = true;
            }
        }

        //if we're not doing a full screen refresh we need to re-draw the background
        //before drawing the updated second hand position. Note this will only re-draw
        //the background in the area specified by the previously computed clipping region.
        if(!fullScreenRefresh) {
            drawBackground(dc);
        }

        //draw HR
        if (hrColor != offSettingFlag) {
            drawHR(dc, refreshHR);
        }
        
        if (shouldPowerSave()) {
            requestUpdate();
        }
    }

    //Draw the watch face background
    //onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    //to the main display.
    //onPartialUpdate uses this to blank the second hand from the previous
    //second before outputing the new one.
    function drawBackground(dc) {
        //If we have an offscreen buffer that has been written to
        //draw it to the screen.
        if( null != offscreenBuffer ) {
            dc.drawBitmap(0, 0, offscreenBuffer);
        }
    }

    //Compute a bounding box from the passed in points
    function getBoundingBox( points ) {
        var min = [9999,9999];
        var max = [0,0];

        for (var i = 0; i < points.size(); ++i) {
            if(points[i][0] < min[0]) {
                min[0] = points[i][0];
            }
            if(points[i][1] < min[1]) {
                min[1] = points[i][1];
            }
            if(points[i][0] > max[0]) {
                max[0] = points[i][0];
            }
            if(points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }

        return [min, max];
    }

    function drawHR(dc, refreshHR) {
        var hr = 0;
        var hrText;
        var activityInfo;
        var hrTextDimension = dc.getTextDimensions("888", font); //to compute correct clip boundaries

        if (refreshHR) {
            activityInfo = Activity.getActivityInfo();
            if (activityInfo != null) {
                hr = activityInfo.currentHeartRate;
                lastMeasuredHR = hr;
            }
        } else {
            hr = lastMeasuredHR;
        }

        if (hr == null || hr == 0) {
            hrText = "";
        } else {
            hrText = hr.format("%i");
        }

        dc.setClip(screenWidth - hrTextDimension[0] - 30, screenRadius - (hrTextDimension[1] / 2), hrTextDimension[0], hrTextDimension[1]);

        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        //debug rectangle
//        dc.drawRectangle(screenWidth - hrTextDimension[0] - 30, screenRadius - (hrTextDimension[1] / 2), hrTextDimension[0], hrTextDimension[1]);
        dc.drawText(screenWidth - 30, screenRadius, font, hrText, Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawGraph(dc, iterator, graphPosition, decimalCount, divider, minimalRange, showLatestValue, graphType, numberOfSamples) {
        var minVal = iterator.getMin();
        var maxVal = iterator.getMax();
        if (minVal == null || maxVal == null || numberOfSamples == 0) {
            return;
        }

        var leftX = 37;
        var topY;
        if (graphPosition == 1) {
            topY = 68 * screenResolutionRatio;
        } else {
            topY = 137 * screenResolutionRatio;
        }

        minVal = Math.floor(minVal / divider);
        maxVal = Math.ceil(maxVal / divider);
        var range = maxVal - minVal;
        if (range < minimalRange) {
            var avg = (minVal + maxVal) / 2.0;
            minVal = avg - (minimalRange / 2.0);
            maxVal = avg + (minimalRange / 2.0);
            range = minimalRange;
        }

        var minValStr = minVal.format("%.0f");
        var maxValStr = maxVal.format("%.0f");
        if (graphType == 1 && deviceSettings.elevationUnits == System.UNIT_STATUTE) {
            minValStr = convertM_Ft(minVal).format("%.0f");
            maxValStr = convertM_Ft(maxVal).format("%.0f");
        } else if (graphType == 4 && deviceSettings.temperatureUnits == System.UNIT_STATUTE) {
            minValStr = convertC_F(minVal).format("%.0f");
            maxValStr = convertC_F(maxVal).format("%.0f");
        }

        //draw min and max values
        dc.setColor(graphLegendColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + 8, topY - 17, Graphics.FONT_XTINY, maxValStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(leftX + 8, topY + 41 - 12, Graphics.FONT_XTINY, minValStr, Graphics.TEXT_JUSTIFY_LEFT);
        //draw graph borders
        if (graphBordersColor != offSettingFlag) {
            var maxX = leftX + (dc.getTextDimensions(maxValStr, Graphics.FONT_XTINY))[0] + 5;
            var minX = leftX + (dc.getTextDimensions(minValStr, Graphics.FONT_XTINY))[0] + 5;
            dc.setColor(graphBordersColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(leftX + 1, topY, leftX + 6, topY);
            dc.drawLine(leftX + 1, topY + 35, leftX + 6, topY + 35);
            dc.drawLine(maxX + 5, topY, screenWidth - leftX + 1, topY);
            dc.drawLine(minX + 5, topY + 35, screenWidth - leftX + 1, topY + 35);

            var x;
            for (var i = 0; i <= 6; i++) {
                x = screenWidth - leftX - (i * 27.5);
                dc.drawLine(x, topY, x, topY + 5 + 1);
                dc.drawLine(x, topY + 30, x, topY + 35);
            }
        }

        //get latest sample
        var item = iterator.next();
        var counter = 1; //used only for 180 samples history
        var value = null;
        var valueStr = "";
        var x1 = screenWidth - leftX;
        var y1, x2, y2;
        dc.setColor(graphLineColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(graphLineWidth);
        if (item != null) {
            value = item.data;            
            if (value != null) {
                valueStr = value;
                if (graphType == 1 && deviceSettings.elevationUnits == System.UNIT_STATUTE) {
                    valueStr = convertM_Ft(value);
                } else if (graphType == 4 && deviceSettings.temperatureUnits == System.UNIT_STATUTE) {
                    valueStr = convertC_F(value);
                }
                y1 = (topY + 35 + 1) - ((value / divider) - minVal) / range * 35;
                dc.drawPoint(x1, y1);
            }
        } else {
            //no samples
            return;
        }

        item = iterator.next();
        counter++;
        var timestamp = Toybox.Time.Gregorian.info(item.when, Time.FORMAT_SHORT);
        while (item != null) {
            if (numberOfSamples <= 165) {
                //don't skip any sample
            }
            if (numberOfSamples == 180 && counter % 12 == 0) {
                //skip each 12th sample to display only 165 samples instead of 180 because of screen size
                item = iterator.next();
                counter++;
                continue;
            }
            timestamp = Toybox.Time.Gregorian.info(item.when, Time.FORMAT_SHORT);
            if (numberOfSamples == 360) {
                if (timestamp.min % 24 == 0) {
                    //skip each 12th sample to display only 165 samples instead of 180 because of screen size
                    item = iterator.next();
                    continue;
                }
                if (timestamp.min % 2 == 1) {
                    //many samples, skip every second sample
                    item = iterator.next();
                    continue;
                }
            }

            value = item.data;
            x2 = x1 - 1;
            if (value != null) {
                y2 = (topY + 35 + 1) - ((value / divider) - minVal) / range * 35;
                if (y1 != null) {
                    dc.drawLine(x2, y2, x1, y1);
                } else {
                    dc.drawPoint(x2, y2);
                }
                y1 = y2;
            } else {
                y1 = null;
            }
            x1 = x2;

            item = iterator.next();
            counter++;
        }

        //draw latest value on top of graph
        if (showLatestValue) {
            dc.setColor(graphCurrentValueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(leftX + 8, topY + 6, Graphics.FONT_XTINY, (valueStr / divider).format("%." + decimalCount + "f"), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function countSamples(iterator) {
        var count = 0;
        while (iterator.next() != null) {
            count++;
        }

        return count;
    }

    function convertKm_Mi(value) {
        return (value / 1.609344);
    }

    function convertM_Ft(value) {
        return (value * 3.2808);
    }

    function convertC_F(value) {
        return ((value * 1.8) + 32);
    }

    function shouldPowerSave() {
        if (powerSaver && !isAwake) {
        var refreshDisplay = true;
        var time = System.getClockTime();
        var timeMinOfDay = (time.hour * 60) + time.min;
        
        if (startPowerSaverMin <= endPowerSaverMin) {
        	if ((startPowerSaverMin <= timeMinOfDay) && (timeMinOfDay < endPowerSaverMin)) {
        		refreshDisplay = false;
        	}
        } else {
        	if ((startPowerSaverMin <= timeMinOfDay) || (timeMinOfDay < endPowerSaverMin)) {
        		refreshDisplay = false;
        	}        
        }
        return !refreshDisplay;
        } else {
            return false;
        }
    }

    function drawPowerSaverIcon(dc) {
        dc.setColor(handsColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, 45 * powerSaverIconRatio);
        dc.setColor(bgColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(screenRadius, screenRadius, 40 * powerSaverIconRatio);
        dc.setColor(handsColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(screenRadius - (13 * powerSaverIconRatio), screenRadius - (23 * powerSaverIconRatio), 26 * powerSaverIconRatio, 51 * powerSaverIconRatio);
        dc.fillRectangle(screenRadius - (4 * powerSaverIconRatio), screenRadius - (27 * powerSaverIconRatio), 8 * powerSaverIconRatio, 5 * powerSaverIconRatio);
        if (oneColor == offSettingFlag) {
            dc.setColor(powerSaverIconColor, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(oneColor, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(screenRadius - (10 * powerSaverIconRatio), screenRadius - (20 * powerSaverIconRatio), 20 * powerSaverIconRatio, 45 * powerSaverIconRatio);

        powerSaverDrawn = true;
    }

	function computeSunConstants() {
    	var posInfo = Toybox.Position.getInfo();
    	if (posInfo != null && posInfo.position != null) {
	    	var sc = new SunCalc();
	    	var time_now = Time.now();    	
	    	var loc = posInfo.position.toRadians();
    		var hasLocation = (loc[0].format("%.2f").equals("3.14") && loc[1].format("%.2f").equals("3.14")) || (loc[0] == 0 && loc[1] == 0) ? false : true;

	    	if (!hasLocation && locationLatitude != offSettingFlag) {
	    		loc[0] = locationLatitude;
	    		loc[1] = locationLongitude;
	    	}

	    	if (hasLocation) {
				Application.getApp().setProperty("locationLatitude", loc[0]);
				Application.getApp().setProperty("locationLongitude", loc[1]);
				locationLatitude = loc[0];
				locationLongitude = loc[1];
			}
			
	        sunriseStartAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.DAWN));	        
	        sunriseEndAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.SUNRISE));
	        sunsetStartAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.SUNSET));
	        sunsetEndAngle = computeSunAngle(sc.calculate(time_now, loc, SunCalc.DUSK));

            if (((sunriseStartAngle < sunsetStartAngle) && (sunriseStartAngle > sunsetEndAngle)) ||
                    ((sunriseEndAngle < sunsetStartAngle) && (sunriseEndAngle > sunsetEndAngle)) ||
                    ((sunsetStartAngle < sunriseStartAngle) && (sunsetStartAngle > sunriseEndAngle)) ||
                    ((sunsetEndAngle < sunriseStartAngle) && (sunsetEndAngle > sunriseEndAngle))) {
                sunArcsOffset = 13;
            } else {
                sunArcsOffset = 17;
            }
        }
	}

	function computeSunAngle(time) {
        var timeInfo = Time.Gregorian.info(time, Time.FORMAT_SHORT);       
        var angle = ((timeInfo.hour % 12) * 60.0) + timeInfo.min;
        angle = angle / (12 * 60.0) * Math.PI * 2;
        return -(angle - Math.PI/2) * 180 / Math.PI;	
	}

	function drawSun(dc) {
        dc.setPenWidth(7);

        //draw sunrise
        if (sunriseColor != offSettingFlag) {
	        dc.setColor(sunriseColor, Graphics.COLOR_TRANSPARENT);
	        if (sunriseStartAngle > sunriseEndAngle) {
				dc.drawArc(screenRadius, screenRadius, screenRadius - 17, Graphics.ARC_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
			} else {
				dc.drawArc(screenRadius, screenRadius, screenRadius - 17, Graphics.ARC_COUNTER_CLOCKWISE, sunriseStartAngle, sunriseEndAngle);
			}
		}

        //draw sunset
        if (sunsetColor != offSettingFlag) {
	        dc.setColor(sunsetColor, Graphics.COLOR_TRANSPARENT);
	        if (sunsetStartAngle > sunsetEndAngle) {
				dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset, Graphics.ARC_CLOCKWISE, sunsetStartAngle, sunsetEndAngle);
			} else {
				dc.drawArc(screenRadius, screenRadius, screenRadius - sunArcsOffset, Graphics.ARC_COUNTER_CLOCKWISE, sunsetStartAngle, sunsetEndAngle);
			}
		}
	}
	
}
