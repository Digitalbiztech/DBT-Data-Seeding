import svc from 'c/externalServices';

describe('externalServices/connectionService', () => {
    it('throws on testConnection placeholder', async () => {
        await expect(svc.testConnection({ username: 'u', password: 'p', environment: 'e' }))
            .rejects.toThrow('Not implemented');
    });
});


