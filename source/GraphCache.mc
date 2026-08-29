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

using Toybox.Lang;

//Circular buffer holding pre-processed graph samples. The whole sensor history
//is read only once (see SmartArcsTripView.buildGraphCache); afterwards only the
//newest sample is pushed in while the oldest one is evicted, which keeps CPU
//utilization low compared to re-reading the whole iterator on every update.
class GraphCache {

    var values;      //circular buffer of sample values (may contain nulls for gaps)
    var size;        //number of columns/samples the buffer can hold
    var head;        //index of the newest value
    var minVal;      //cached minimum over the buffer
    var maxVal;      //cached maximum over the buffer
    var lastWhen;    //timestamp (Moment value) of the newest cached sample
    var graphType;   //sensor the buffer currently holds (SmartArcsTripView SG_* enum)
    var batchSize;   //number of history samples averaged into one column
    var pendingSum;  //running sum of non-null samples in the column being filled
    var pendingCount;//non-null samples accumulated into the current column
    var pendingNull; //null samples accumulated into the current column

    function initialize(bufferSize) {
        size = bufferSize;
        values = new [bufferSize];
        head = 0;
        minVal = null;
        maxVal = null;
        lastWhen = null;
        graphType = 0;
        batchSize = 1;
        resetPending();
    }

    function reset() {
        for (var i = 0; i < size; i++) {
            values[i] = null;
        }
        head = 0;
        minVal = null;
        maxVal = null;
        lastWhen = null;
        resetPending();
    }

    //discard the partially accumulated column so the next sample starts a fresh one
    function resetPending() {
        pendingSum = 0;
        pendingCount = 0;
        pendingNull = 0;
    }

    //value at position i counting from the newest (0) to the oldest (size - 1)
    function valueAt(i) {
        return values[(head + i) % size];
    }

    //rotate a new newest value in, evicting the oldest one; returns the evicted value
    function push(value) {
        head = (head + size - 1) % size;
        var evicted = values[head];
        values[head] = value;
        return evicted;
    }

    //add one history sample, averaging batchSize consecutive samples into a single
    //column so incremental updates match the downsampling done in buildGraphCache
    function addSample(value) {
        if (value != null) {
            pendingSum += value;
            pendingCount++;
        } else {
            pendingNull++;
        }

        var total = pendingCount + pendingNull;
        var colVal = (pendingCount > 0) ? (pendingSum / pendingCount) : null;

        if (total == 1) {
            //first sample of a new column: rotate a fresh column in
            push(colVal);
        } else {
            //still filling the newest column: refine its average in place
            values[head] = colVal;
        }

        if (total >= batchSize) {
            //column complete; the next sample starts a new one
            resetPending();
        }

        //the newest column changed value, so recompute extremes for correctness
        recomputeMinMax();
    }

    function recomputeMinMax() {
        var mn = null;
        var mx = null;
        var v;
        for (var i = 0; i < size; i++) {
            v = values[i];
            if (v != null) {
                if (mn == null || v < mn) {
                    mn = v;
                }
                if (mx == null || v > mx) {
                    mx = v;
                }
            }
        }
        minVal = mn;
        maxVal = mx;
    }
}
