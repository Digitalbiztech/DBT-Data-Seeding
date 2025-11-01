@isTest
public class ExternalOrgConnectionServiceTest {
    @isTest static void testConnectionThrows() {
        try {
            ExternalOrgConnectionService.testConnection('','','');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Not implemented', e.getMessage());
        }
    }
}

