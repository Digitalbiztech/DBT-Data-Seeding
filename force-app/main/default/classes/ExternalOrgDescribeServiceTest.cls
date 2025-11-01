@isTest
public class ExternalOrgDescribeServiceTest {
    @isTest static void testDescribeObjectThrows() {
        try {
            ExternalOrgDescribeService.describeObject('Account');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Not implemented', e.getMessage());
        }
    }
}

