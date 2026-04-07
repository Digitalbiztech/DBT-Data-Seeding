@isTest
public class DataSeedingServicesTestV2 {

    private class SeedingMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/query')) {
                if (endpoint.contains('Profile')) {
                    res.setBody('{"totalSize": 1, "done": true, "records": [{"Id": "src_prof_1", "Name": "Standard User", "attributes": {"type": "Profile"}}]}');
                } else if (endpoint.contains('Account')) {
                    res.setBody('{"totalSize": 1, "done": true, "records": [{"Id": "src_acc_1", "Name": "Acc 1", "attributes": {"type": "Account"}}]}');
                } else if (endpoint.contains('User')) {
                    res.setBody('{"totalSize": 1, "done": true, "records": [{"Id": "src_user_1", "Username": "test@test.com", "Email": "test@test.com", "ProfileId": "src_prof_1", "attributes": {"type": "User"}}]}');
                } else {
                    res.setBody('{"totalSize": 1, "done": true, "records": [{"Id": "src_id_1", "Name": "Mock Rec", "Email": "test@test.com", "attributes": {"type": "Contact"}}]}');
                }
            } else if (endpoint.contains('/composite/sobjects')) {
                res.setBody('[{"success": true, "id": "001WG0000000000AAA"}]');
            } else if (endpoint.contains('/describe')) {
                res.setBody('{"name": "Account", "fields": [{"name": "Id", "type": "id"}, {"name": "Name", "type": "string"}, {"name": "ProfileId", "type": "reference", "referenceTo": ["Profile"]}]}');
            } else if (endpoint.contains('/jobs/ingest')) {
                res.setBody('{"id": "707WG0000000000AAA", "state": "JobComplete"}');
            }
            return res;
        }
    }

    @isTest
    static void testDataSeedingBatchComprehensive() {
        Test.setMock(HttpCalloutMock.class, new SeedingMock());
        
        DataSeedingBatch batch = new DataSeedingBatch(
            'src_sess', 'https://src.com',
            'dest_sess', 'https://dest.com',
            new List<Map<String, Object>>(),
            new Map<String, Map<String, String>>(),
            '707WG0000000000AAA'
        );
        
        Test.startTest();
        // resolveUserProfiles with data
        List<Map<String, Object>> userRows = new List<Map<String, Object>>{ new Map<String, Object>{'ProfileId' => 'src_prof_1'} };
        batch.resolveUserProfiles(userRows);
        
        // resolveReferences with data
        batch.resolveReferences('Account', new Set<String>{'src_acc_1'});
        
        // getLocalReferenceFields
        batch.getLocalReferenceFields('Account');
        
        // saveReport
        batch.logs = new List<DataSeedingBatch.LogEntry>{ new DataSeedingBatch.LogEntry() };
        batch.saveReport('707WG0000000000AAA');
        
        // Pagination & User remapping
        Map<String, Object> task = new Map<String, Object>{ 'objectName' => 'User', 'soql' => 'SELECT Id, ProfileId FROM User' };
        batch = new DataSeedingBatch('s', 'u', 'd', 'u', new List<Map<String, Object>>{task}, new Map<String, Map<String, String>>(), null);
        batch.currentNextRecordsUrl = '/next/page';
        batch.execute(null, new List<Integer>{0});
        batch.finish(null);
        
        // Test local reference fields branch
        batch.getLocalReferenceFields('User');
        Test.stopTest();
    }

    @isTest
    static void testDataSeedingServiceComprehensive() {
        Test.setMock(HttpCalloutMock.class, new SeedingMock());
        
        Test.startTest();
        Map<String, Map<String, String>> remap = new Map<String, Map<String, String>>();
        List<Map<String, Object>> rows = new List<Map<String, Object>>{ new Map<String, Object>{'ProfileId' => 'src_prof_1'} };
        
        DataSeedingService.resolveUserProfiles(rows, remap, 's', 'u', 'd', 'u');
        DataSeedingService.resolveReferences('Account', new Set<String>{'src_acc_1'}, remap, 's', 'u', 'd', 'u');
        DataSeedingService.findMatchingRecords('s', 'u', 'Account', new List<String>{'Name'}, new List<Map<String, Object>>{ new Map<String, Object>{'Name' => 'MatchMe'} });
        DataSeedingService.findMatchingRecords(null, null, 'Account', new List<String>{'Name'}, new List<Map<String, Object>>{ new Map<String, Object>{'Name' => 'MatchMe'} });
        
        List<Map<String, Object>> tasks = new List<Map<String, Object>>{ new Map<String, Object>{'objectName' => 'Account', 'soql' => 'SELECT Id FROM Account'} };
        DataSeedingService.startDataSeedingBatch('s', 'u', 'd', 'u', tasks, new Map<String, Map<String, String>>());
        
        try { DataSeedingService.getBatchJobStatus('707WG0000000000AAA'); } catch (Exception e) {}
        try { DataSeedingService.getBatchReport('jobid'); } catch (Exception e) {}
        DataSeedingService.preprocessRecords('User', rows, 's', 'u', 'd', 'u');
        
        // ExternalOrgQueryService coverage
        try { ExternalOrgQueryService.loginAndQuery('u','p','P','SELECT Id FROM Account'); } catch(Exception e){}
        try { ExternalOrgQueryService.queryWithSession('s','u','SELECT Id FROM Account'); } catch(Exception e){}
        try { ExternalOrgQueryService.queryCurrent('SELECT Id FROM Account'); } catch(Exception e){}
        try { ExternalOrgQueryService.queryByUrl('s','u','/url'); } catch(Exception e){}
        
        Test.stopTest();
    }
}
