import { buildConcatenatedKey } from 'c/externalServices';

test('buildConcatenatedKey concatenates values', () => {
    const key = buildConcatenatedKey({ A: '1', B: '2' }, ['A', 'B']);
    expect(key).toBe('1|2');
});


