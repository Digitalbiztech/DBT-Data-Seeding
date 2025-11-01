export function buildConcatenatedKey(record, fields) {
    return (fields || [])
        .map((f) => (record && (record[f] === null || record[f] === undefined) ? '' : String(record[f])))
        .join('|');
}

