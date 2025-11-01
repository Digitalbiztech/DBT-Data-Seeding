import { computeExportOrder } from 'c/externalServices';

test('computeExportOrder returns topo order', () => {
    const edges = new Map([
        ['Child', [{ fieldName: 'Parent__c', target: 'Parent' }]],
        ['Parent', []]
    ]);
    const order = computeExportOrder(edges, 'Child');
    expect(order.indexOf('Parent')).toBeLessThan(order.indexOf('Child'));
});


