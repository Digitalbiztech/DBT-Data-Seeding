@isTest
@SuppressWarnings(
  'PMD.AvoidDebugStatements, PMD.ApexDoc, PMD.CyclomaticComplexity, PMD.IfStmtsMustUseBraces, PMD.IfElseStmtsMustUseBraces, PMD.DebugsShouldUseLoggingLevel, PMD.EmptyCatchBlock, PMD.ApexAssertionsShouldIncludeMessage, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.StdCyclomaticComplexity, PMD.AvoidDeeplyNestedIfStmts, PMD.NcssMethodCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.FieldDeclarationsShouldBeAtStart, PMD.ForLoopsMustUseBraces, PMD.UnusedLocalVariable, PMD.ExcessivePublicCount, PMD.NcssTypeCount, PMD.ApexSuggestUsingNamedCred, PMD.AvoidHardcodingId, PMD.ApexSOQLInjection'
)
private class DataSeedingBatchTest {
  private class MockHttpResponse implements HttpCalloutMock {
    private String body;

    public MockHttpResponse(String body) {
      this.body = body;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setBody(body);
      res.setStatusCode(200);
      return res;
    }
  }

  @isTest
  static void testBatchExecution() {
    User adminUser = TestDataFactory.createAdminUser();
    System.runAs(adminUser) {
      // Mock Tasks
      List<Map<String, Object>> tasks = new List<Map<String, Object>>();
      Map<String, Object> task = new Map<String, Object>();
      task.put('objectName', 'Account');
      task.put('soql', 'SELECT Id, Name FROM Account');
      tasks.add(task);

      // Mock Plan Edges
      Map<String, Map<String, String>> planEdges = new Map<String, Map<String, String>>();

      // Setup Batch
      DataSeedingBatch batch = new DataSeedingBatch(
        'srcSession',
        'https://src.salesforce.com',
        'destSession',
        'https://dest.salesforce.com',
        tasks,
        planEdges,
        null
      );

      // Mock Callouts
      // We need a composite mock or handle multiple callouts?
      // The batch does:
      // 1. queryWithSession (GET query)
      // 2. createRecordsRemote (POST composite)

      // Simple mock that returns valid JSON for both
      String queryResp = '{"totalSize": 1, "done": true, "records": [{"Id": "001000000000001", "Name": "Test Acc", "attributes": {"type": "Account"}}]}';
      String insertResp = '[{"success": true, "id": "001000000000002"}]';

      // We can't easily switch mocks within one execute unless we use a smarter mock
      // Let's use a MultiRequestMock

      Test.setMock(
        HttpCalloutMock.class,
        new MultiRequestMock(queryResp, insertResp)
      );

      Test.startTest();
      Database.executeBatch(batch, 1);
      Test.stopTest();

      // Verify logs were saved
      List<ContentVersion> cvs = [
        SELECT Id, Title, VersionData
        FROM ContentVersion
        WHERE Title LIKE 'SeedingReport_%'
      ];
      System.assertEquals(1, cvs.size(), 'Report should be generated');

      String logBody = cvs[0].VersionData.toString();
      System.debug('Log Body: ' + logBody);
      System.assert(logBody.contains('Success'), 'Log should contain success');
    }
  }

  public class MultiRequestMock implements HttpCalloutMock {
    String queryResp;
    String insertResp;

    public MultiRequestMock(String q, String i) {
      this.queryResp = q;
      this.insertResp = i;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      if (req.getMethod() == 'GET' && req.getEndpoint().contains('/query')) {
        res.setBody(queryResp);
      } else if (
        req.getMethod() == 'POST' && req.getEndpoint().contains('/composite')
      ) {
        res.setBody(insertResp);
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }
}
