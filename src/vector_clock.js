const VC_RESULTS = {
    BEFORE: 'BEFORE',
    AFTER: 'AFTER',
    CONCURRENT: 'CONCURRENT',
    EQUAL: 'EQUAL'
};

/**
 * Compare two vector clocks
 * @param {Object} vc1 
 * @param {Object} vc2 
 * @returns {String} BEFORE, AFTER, CONCURRENT, or EQUAL
 */
function compare(vc1, vc2) {
    let isLess = false;
    let isGreater = false;

    // Get all unique keys from both vector clocks
    const keys = new Set([...Object.keys(vc1 || {}), ...Object.keys(vc2 || {})]);

    for (const key of keys) {
        const val1 = vc1[key] || 0;
        const val2 = vc2[key] || 0;

        if (val1 < val2) {
            isLess = true;
        } else if (val1 > val2) {
            isGreater = true;
        }
    }

    if (isLess && isGreater) return VC_RESULTS.CONCURRENT;
    if (isLess) return VC_RESULTS.BEFORE;
    if (isGreater) return VC_RESULTS.AFTER;
    return VC_RESULTS.EQUAL;
}

/**
 * Merge two vector clocks, taking the maximum of each counter
 * @param {Object} vc1 
 * @param {Object} vc2 
 * @returns {Object} A new merged vector clock
 */
function merge(vc1, vc2) {
    const merged = {};
    const keys = new Set([...Object.keys(vc1 || {}), ...Object.keys(vc2 || {})]);

    for (const key of keys) {
        const val1 = vc1[key] || 0;
        const val2 = vc2[key] || 0;
        merged[key] = Math.max(val1, val2);
    }

    return merged;
}

module.exports = {
    compare,
    merge,
    VC_RESULTS
};
