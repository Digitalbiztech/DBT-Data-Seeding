@isTest
private class DataSeedingServiceTest {
  @testSetup
  static void setup() {
    Account a = new Account(Name = 'MatchMe');
    insert a;
  }

  @isTest
  static void testFindMatchingRecordsLocal() {
    User adminUser = TestDataFactory.createAdminUser();
    System.runAs(adminUser) {
      List<Map<String, Object>> source = new List<Map<String, Object>>();

      Map<String, Object> r1 = new Map<String, Object>();
      r1.put('Id', 'SourceId1');
      r1.put('Name', 'MatchMe');
      source.add(r1);

      Map<String, Object> r2 = new Map<String, Object>();
      r2.put('Id', 'SourceId2');
      r2.put('Name', 'NoMatch');
      source.add(r2);

      Test.startTest();
      // Pass null session/url to use local query
      List<DataSeedingService.MatchResult> results = DataSeedingService.findMatchingRecords(
        null,
        null,
        'Account',
        new List<String>{ 'Name' },
        source
      );
      Test.stopTest();

      System.assertEquals(1, results.size());
      System.assertEquals('SourceId1', results[0].sourceId);
      System.assertNotEquals(null, results[0].destId);
    }
  }

  @isTest
  static void testFindMatchingRecordsRemote() {
    Test.setMock(HttpCalloutMock.class, new MockQueryResponse());

    List<Map<String, Object>> source = new List<Map<String, Object>>();
    Map<String, Object> r1 = new Map<String, Object>();
    r1.put('Id', 'SourceId1');
    r1.put('Name', 'RemoteMatch');
    source.add(r1);

    Test.startTest();
    List<DataSeedingService.MatchResult> results = DataSeedingService.findMatchingRecords(
      'sess',
      'https://instance.url',
      'Account',
      new List<String>{ 'Name' },
      source
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals('SourceId1', results[0].sourceId);
    System.assertEquals('DestId1', results[0].destId);
  }

  @isTest
  static void testStartDataSeedingBatch() {
    // Just verify it doesn't crash and returns an ID
    // The batch logic itself is tested in DataSeedingBatchTest
    List<Map<String, Object>> tasks = new List<Map<String, Object>>();
    Map<String, Object> t = new Map<String, Object>();
    t.put('objectName', 'Account');
    t.put('soql', 'SELECT Id FROM Account');
    tasks.add(t);

    Test.startTest();
    String jobId = DataSeedingService.startDataSeedingBatch(
      'sess',
      'url',
      'destSess',
      'destUrl',
      tasks,
      new Map<String, Map<String, String>>()
    );
    Test.stopTest();

    System.assertNotEquals(null, jobId);
  }

  public class MockQueryResponse implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      // Return a result that matches "RemoteMatch"
      // The service queries for Name IN ('RemoteMatch')
      // We return a record with Name='RemoteMatch', Id='DestId1'
      String body = '{"totalSize": 1, "done": true, "records": [{"Id": "DestId1", "Name": "RemoteMatch", "attributes": {"type": "Account"}}]}';
      res.setBody(body);
      return res;
    }
  }
}