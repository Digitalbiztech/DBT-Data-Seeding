@isTest
private class ExternalOrgDmlServiceTest {
  @isTest
  static void testInsertRecordsCurrent() {
    User adminUser = TestDataFactory.createAdminUser();
    System.runAs(adminUser) {
      List<Map<String, Object>> records = new List<Map<String, Object>>();
      Map<String, Object> r1 = new Map<String, Object>();
      r1.put('Name', 'Test Account 1');
      r1.put('Id', '001000000000001'); // Old ID
      records.add(r1);

      Test.startTest();
      List<ExternalOrgDmlService.InsertMapping> results = ExternalOrgDmlService.insertRecordsCurrent(
        'Account',
        records
      );
      Test.stopTest();

      System.assertEquals(1, results.size());
      System.assertEquals(true, results[0].success);
      System.assertNotEquals(null, results[0].newId);
      System.assertEquals('001000000000001', results[0].oldId);
    }
  }

  @isTest
  static void testCreateRecordsRemote() {
    // Mock the composite API
    Test.setMock(HttpCalloutMock.class, new MockCompositeResponse());

    List<Map<String, Object>> records = new List<Map<String, Object>>();
    // Create 205 records to test chunking (batch size 200)
    for (Integer i = 0; i < 205; i++) {
      Map<String, Object> r = new Map<String, Object>();
      r.put('Name', 'Remote Acc ' + i);
      r.put('Id', '001FakeId' + i);
      records.add(r);
    }

    Test.startTest();
    List<ExternalOrgDmlService.InsertMapping> results = ExternalOrgDmlService.createRecordsRemote(
      'sessId',
      'https://instance.url',
      'Account',
      records
    );
    Test.stopTest();

    System.assertEquals(
      205,
      results.size(),
      'Should return results for all records'
    );
    System.assertEquals(true, results[0].success);
    System.assertEquals('NewId0', results[0].newId);
    System.assertEquals('NewId204', results[204].newId);
  }

  public class MockCompositeResponse implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);

      // Parse body to see how many records came in
      Map<String, Object> bodyMap = (Map<String, Object>) JSON.deserializeUntyped(
        req.getBody()
      );
      List<Object> recs = (List<Object>) bodyMap.get('records');
      Integer count = recs.size();

      // Generate response for 'count' items
      List<Map<String, Object>> responseList = new List<Map<String, Object>>();
      for (Integer i = 0; i < count; i++) {
        Map<String, Object> item = (Map<String, Object>) recs[i];
        String name = (String) item.get('Name'); // We sent Name
        // Extract index from Name "Remote Acc X"
        String idxStr = name.substringAfterLast(' ');

        Map<String, Object> respItem = new Map<String, Object>();
        respItem.put('success', true);
        respItem.put('id', 'NewId' + idxStr);
        responseList.add(respItem);
      }

      res.setBody(JSON.serialize(responseList));
      return res;
    }
  }
}
