/*
    This file is part of SmartArcs Trip watch face.
    https://github.com/okdar/smartarcs

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
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

class SmartArcsTripView extends WatchUi.WatchFace {

    var isAwake = false;
    var partialUpdatesAllowed = false;
    var hasElevationHistory = false;
    var hasPressureHistory = false;
    var hasTemperatureHistory = false;
    var curClip;
    var fullScreenRefresh;
    var offscreenBuffer;
    var offSettingFlag = -999;
    var font = Graphics.FONT_TINY;
    var precompute;
    var lastMeasuredHR;
    var deviceSettings;

    //variables for pre-computation
    var screenWidth;
    var screenRadius;
    var arcRadius;
    var twoPI = Math.PI * 2;
    var ticks;
    var showTicks;
    var hourHandLength;
    var minuteHandLength;
    var handsTailLength;
    var arcPenWidth = 10;
    var hrTextDimension;
    var halfHRTextWidth;

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

    function initialize() {
        loadUserSettings();
        WatchFace.initialize();
        fullScreenRefresh = true;
        partialUpdatesAllowed = (Toybox.WatchUi.WatchFace has :onPartialUpdate);

        if (Toybox has :SensorHistory) {
            if (Toybox.SensorHistory has :getElevationHistory) {
                hasElevationHistory = true;
            }
            if (Toybox.SensorHistory has :getPressureHistory) {
                hasPressureHistory = true;
            }
            if (Toybox.SensorHistory has :getTemperatureHistory) {
                hasTemperatureHistory = true;
            }
        }
    }

    //load resources here
    function onLayout(dc) {
        //if this device supports BufferedBitmap, allocate the buffers we use for drawing
        if (Toybox.Graphics has :BufferedBitmap) {
            // Allocate a full screen size buffer with a palette of only 4 colors to draw
            // the background image of the watchface.  This is used to facilitate blanking
            // the second hand during partial updates of the display
            offscreenBuffer = new Graphics.BufferedBitmap({
                :width => dc.getWidth(),
                :height => dc.getHeight()
            });
        } else {
            offscreenBuffer = null;
        }

        curClip = null;
    }

    //called when this View is brought to the foreground. Restore
    //the state of this View and prepare it to be shown. This includes
    //loading resources into memory.
    function onShow() {
    }

    //update the view
    function onUpdate(dc) {
        deviceSettings = System.getDeviceSettings();

        //compute what does not need to be computed on each update
        if (precompute) {
            computeConstants(dc);
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
            drawBattery(targetDc);
        }
        if (notificationColor != offSettingFlag) {
            drawNotifications(targetDc, deviceSettings.notificationCount);
        }
        if (bluetoothColor != offSettingFlag) {
            drawBluetooth(targetDc, deviceSettings.phoneConnected);
        }
        if (dndColor != offSettingFlag) {
            drawDoNotDisturb(targetDc, deviceSettings.doNotDisturb);
        }
        if (alarmColor != offSettingFlag) {
            drawAlarms(targetDc, deviceSettings.alarmCount);
        }

        if (showTicks) {
            drawTicks(targetDc);
        }

        if (!handsOnTop) {
            drawHands(targetDc, System.getClockTime());
        }

//        if (dateColor != offSettingFlag) {
//            drawDate(targetDc, Time.today());
//        }

        if (hasElevationHistory) {
            var elevationIter = SensorHistory.getElevationHistory({});
            if (elevationIter != null) {
                drawChart(targetDc, elevationIter, 45, 65, 0, 1.0, 5);
            }
        }
        if (hasPressureHistory) {
            var pressureIter = SensorHistory.getPressureHistory({});
            if (pressureIter != null) {
                drawChart(targetDc, pressureIter, 45, 140, 1, 100.0, 5);
            }
        }
        if (hasTemperatureHistory) {
            targetDc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            var temperatureIter = SensorHistory.getTemperatureHistory({});
            var temp = temperatureIter.next();
            var t = temp.data.format("%.1f") + StringUtil.utf8ArrayToString([0xC2,0xB0]);
            targetDc.drawText(screenRadius, screenWidth - Graphics.getFontHeight(font) - 30, Graphics.FONT_TINY, t, Graphics.TEXT_JUSTIFY_CENTER);
        }

        targetDc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        targetDc.drawText(screenRadius, 30, Graphics.FONT_TINY, (ActivityMonitor.getInfo().distance/100000.0).format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);

        if (handsOnTop) {
            drawHands(targetDc, System.getClockTime());
        }

        //output the offscreen buffers to the main display if required.
        drawBackground(dc);

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
        } else {
            notificationColor = oneColor;
            bluetoothColor = oneColor;
            dndColor = oneColor;
            alarmColor = oneColor;
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

        //ensure that constants will be pre-computed
        precompute = true;
    }

    //pre-compute values which don't need to be computed on each update
    function computeConstants(dc) {
        screenWidth = dc.getWidth();
        screenRadius = screenWidth / 2;

        //computes hand lenght for watches with different screen resolution than 240x240
        var handLengthCorrection = screenWidth / 240.0;
        hourHandLength = (60 * handLengthCorrection).toNumber();
        minuteHandLength = (90 * handLengthCorrection).toNumber();
        handsTailLength = (15 * handLengthCorrection).toNumber();

        showTicks = ((ticksColor == offSettingFlag) ||
            (ticksColor != offSettingFlag && ticks1MinWidth == 0 && ticks5MinWidth == 0 && ticks15MinWidth == 0)) ? false : true;
        if (showTicks) {
            //array of ticks coordinates
            computeTicks();
        }

        arcRadius = screenRadius - (arcPenWidth / 2);

        hrTextDimension = dc.getTextDimensions("888", Graphics.FONT_TINY); //to compute correct clip boundaries
        halfHRTextWidth = hrTextDimension[0] / 2;

        //constants pre-computed, doesn't need to be computed again
        precompute = false;
    }

    function computeTicks() {
        var angle;
        ticks = new [31];
        //to save the memory compute only half of the ticks, second half will be mirrored.
        //I believe it will still save some CPU utilization
        for (var i = 0; i < 31; i++) {
            angle = i * twoPI / 60.0;
            if ((i % 15) == 0) { //quarter tick
                if (ticks15MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 20, ticks15MinWidth);
                }
            } else if ((i % 5) == 0) { //5-minute tick
                if (ticks5MinWidth > 0) {
                    ticks[i] = computeTickRectangle(angle, 20, ticks5MinWidth);
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

    function drawBattery(dc) {
        var batStat = System.getSystemStats().battery;
        dc.setPenWidth(arcPenWidth);
        if (oneColor != offSettingFlag) {
            dc.setColor(oneColor, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
        } else {
            if (batStat > 30) {
                dc.setColor(battery100Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                dc.setColor(battery30Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 153);
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 166.5);
            } else if (batStat <= 30 && batStat > 15){
                dc.setColor(battery30Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 166.5);
            } else {
                dc.setColor(battery15Color, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 180, 180 - 0.9 * batStat);
            }
        }
    }

    function drawNotifications(dc, notifications) {
        if (notifications > 0) {
            drawItems(dc, notifications, 90, notificationColor);
        }
    }

    function drawBluetooth(dc, phoneConnected) {
        if (phoneConnected) {
            dc.setColor(bluetoothColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(arcPenWidth);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, 0, -30);
        }
    }

    function drawDoNotDisturb(dc, doNotDisturb) {
        if (doNotDisturb) {
            dc.setColor(dndColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(arcPenWidth);
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_COUNTER_CLOCKWISE, 270, -60);
        }
    }

    function drawAlarms(dc, alarms) {
        if (alarms > 0) {
            drawItems(dc, alarms, 270, alarmColor);
        }
    }

    function drawItems(dc, count, angle, color) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(arcPenWidth);
        if (count < 11) {
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, angle, angle - 30 - ((count - 1) * 6));
        } else {
            dc.drawArc(screenRadius, screenRadius, arcRadius, Graphics.ARC_CLOCKWISE, angle, angle - 90);
        }
    }

    function drawTicks(dc) {
        var coord = new [4];
        dc.setColor(ticksColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 31; i++) {
            if (ticks[i] != null) {
                dc.fillPolygon(ticks[i]);
            }

            //mirror pre-computed ticks from the left side to the right side
            if (i > 0 && i <30 && ticks[i] != null) {
                for (var j = 0; j < 4; j++) {
                    coord[j] = [screenWidth - ticks[i][j][0], ticks[i][j][1]];
                }
                dc.fillPolygon(coord);
            }
        }
    }

    function drawHands(dc, clockTime) {
        var hourAngle, minAngle;

        //draw hour hand
        hourAngle = ((clockTime.hour % 12) * 60.0) + clockTime.min;
        hourAngle = hourAngle / (12 * 60.0) * twoPI;
        if (handsOutlineColor != offSettingFlag) {
            drawHand(dc, handsOutlineColor, computeHandRectangle(hourAngle, hourHandLength + 2, handsTailLength + 2, hourHandWidth + 4));
        }
        drawHand(dc, handsColor, computeHandRectangle(hourAngle, hourHandLength, handsTailLength, hourHandWidth));

        //draw minute hand
        minAngle = (clockTime.min / 60.0) * twoPI;
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
    }

    //Draw the watch face background
    //onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    //to the main display.
    //onPartialUpdate uses this to blank the second hand from the previous
    //second before outputing the new one.
    function drawBackground(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

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

    function drawDate(dc, today) {
        var info = Gregorian.info(today, Time.FORMAT_MEDIUM);

        var dateString;
        switch (dateFormat) {
            case 0: dateString = info.day;
                    break;
            case 1: dateString = Lang.format("$1$ $2$", [info.day_of_week.substring(0, 3), info.day]);
                    break;
            case 2: dateString = Lang.format("$1$ $2$", [info.day, info.day_of_week.substring(0, 3)]);
                    break;
            case 3: dateString = Lang.format("$1$ $2$", [info.day, info.month.substring(0, 3)]);
                    break;
            case 4: dateString = Lang.format("$1$ $2$", [info.month.substring(0, 3), info.day]);
                    break;
        }
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(screenWidth - 30, screenRadius, font, dateString, Graphics.TEXT_JUSTIFY_RIGHT|Graphics.TEXT_JUSTIFY_VCENTER);
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

    function drawChart(dc, iterator, leftX, topY, decimalCount, divider, minimalRange) {
        var stringFormater =  "%." + decimalCount + "f";
        var minVal = Math.floor(iterator.getMin() / divider);
        var maxVal = Math.ceil(iterator.getMax() / divider);
        var range = maxVal - minVal;
        if (range < minimalRange) {
            var avg = (minVal + maxVal) / 2.0;
            minVal = avg - (minimalRange / 2.0);
            maxVal = avg + (minimalRange / 2.0);
            range = minimalRange;
        }
        var minValStr = minVal.format("%.0f");
        var maxValStr = maxVal.format("%.0f");

        var item = iterator.next();
        if (item != null) {
            var value = item.data;
            if (value != null) {
                var valueStr = value.format(stringFormater);
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                //draw latest value
                dc.drawText(screenRadius, topY + 2, Graphics.FONT_TINY, (value / divider).format(stringFormater), Graphics.TEXT_JUSTIFY_CENTER);
                //draw min and max values
                dc.drawText(leftX, topY - 6, Graphics.FONT_XTINY, maxValStr, Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText(leftX, topY + 35 - 18, Graphics.FONT_XTINY, minValStr, Graphics.TEXT_JUSTIFY_LEFT);
                //draw min and max lines
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                var maxX = leftX + (dc.getTextDimensions(maxValStr, Graphics.FONT_XTINY))[0] + 5;
                var minX = leftX + (dc.getTextDimensions(minValStr, Graphics.FONT_XTINY))[0] + 5;
                dc.drawLine(maxX, topY, screenWidth - leftX, topY);
                dc.drawLine(minX, topY + 35, screenWidth - leftX, topY + 35);

                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                var x1 = screenWidth - leftX;
                var y1 = (topY + 35) - ((value / divider) - minVal) / range * 35;
                var x2;
                var y2;
                item = iterator.next();
                if (item != null) {
                    value = item.data;
                    while (value != null) {
                        x2 = x1 - 1;
                        y2 = (topY + 35) - ((value / divider) - minVal) / range * 35;
                        dc.drawLine(x1, y1, x2, y2);
                        x1 = x2;
                        y1 = y2;
                        if (x1 == maxX || x1 == minX) {
                            break;
                        }
                        item = iterator.next();
                        if (item == null) {
                            break;
                        }
                        value = item.data;
                    }
                }
            }
        }
    }

}
