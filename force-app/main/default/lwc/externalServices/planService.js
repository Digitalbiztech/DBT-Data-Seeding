export function computeExportOrder(edgesByObject, rootObject) {
    const nodes = new Set();
    const adj = new Map();
    const inDegree = new Map();
    const ensure = (n) => { if (!inDegree.has(n)) inDegree.set(n, 0); };
    for (const [fromObj, edges] of edgesByObject.entries()) {
        nodes.add(fromObj); ensure(fromObj);
        for (const e of edges) {
            nodes.add(e.target); ensure(e.target);
            if (!adj.has(e.target)) adj.set(e.target, new Set());
            if (!adj.get(e.target).has(fromObj)) {
                adj.get(e.target).add(fromObj);
                inDegree.set(fromObj, (inDegree.get(fromObj) || 0) + 1);
            }
        }
    }
    const order = []; const q = []; const inQ = new Set();
    const enq = (n) => { if (!inQ.has(n) && (inDegree.get(n) || 0) === 0) { q.push(n); inQ.add(n); } };
    for (const n of nodes) enq(n);
    while (q.length) {
        const n = q.shift(); order.push(n);
        for (const c of Array.from(adj.get(n) || [])) {
            inDegree.set(c, (inDegree.get(c) || 0) - 1);
            enq(c);
        }
    }
    for (const n of nodes) if (!order.includes(n)) order.push(n);
    return order;
}

