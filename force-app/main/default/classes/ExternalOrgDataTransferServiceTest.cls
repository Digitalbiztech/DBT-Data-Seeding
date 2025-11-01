@isTest
public class ExternalOrgDataTransferServiceTest {
    @isTest static void testExportRecordsThrows() {
        try {
            ExternalOrgDataTransferService.exportRecords(new Map<String, Object>());
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Not implemented', e.getMessage());
        }
    }
    @isTest static void testImportRecordsThrows() {
        try {
            ExternalOrgDataTransferService.importRecords(new Map<String, Object>());
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assertEquals('Not implemented', e.getMessage());
        }
    }
}

