import svc from 'c/externalServices';

describe('externalServices/dataTransferService', () => {
    it('export throws placeholder', async () => {
        await expect(svc.export({ objectName: 'X', ids: [] }))
            .rejects.toThrow('Not implemented');
    });
});


