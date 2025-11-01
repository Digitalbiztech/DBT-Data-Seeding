@isTest
public class ExternalOrgDependencyServiceTest {
    @isTest static void testBuildDependencyGraphThrows() {
        try {
            ExternalOrgDependencyService.buildDependencyGraph('Account');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Not implemented', e.getMessage());
        }
    }
}

