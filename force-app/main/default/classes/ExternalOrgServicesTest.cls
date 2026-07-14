@isTest
@SuppressWarnings(
  'PMD.AvoidDebugStatements, PMD.ApexDoc, PMD.CyclomaticComplexity, PMD.IfStmtsMustUseBraces, PMD.IfElseStmtsMustUseBraces, PMD.DebugsShouldUseLoggingLevel, PMD.EmptyCatchBlock, PMD.ApexAssertionsShouldIncludeMessage, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.StdCyclomaticComplexity, PMD.AvoidDeeplyNestedIfStmts, PMD.NcssMethodCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.FieldDeclarationsShouldBeAtStart, PMD.ForLoopsMustUseBraces, PMD.UnusedLocalVariable, PMD.ExcessivePublicCount, PMD.NcssTypeCount, PMD.ApexSuggestUsingNamedCred, PMD.AvoidHardcodingId, PMD.ApexSOQLInjection'
)
private class ExternalOrgServicesTest {
  // ==========================================
  // Auth Service Tests
  // ==========================================
  @isTest
  static void testAuthLoginSuccess() {
    Test.setMock(HttpCalloutMock.class, new MockSoapLoginSuccess());

    Test.startTest();
    ExternalOrgAuthService.LoginResult res = ExternalOrgAuthService.login(
      'user',
      'pass',
      'Production'
    );
    Test.stopTest();

    System.assertEquals('FakeSessionId', res.sessionId);
    System.assertEquals(
      'https://na1.salesforce.com/services/Soap/u/62.0',
      res.serverUrl
    );
  }

  @isTest
  static void testTestConnectionSuccess() {
    Test.setMock(HttpCalloutMock.class, new MockSoapLoginSuccess());

    Test.startTest();
    ExternalOrgAuthService.ConnectionTestResult res = ExternalOrgAuthService.testConnection(
      'user',
      'pass',
      'Production'
    );
    Test.stopTest();

    System.assertEquals(true, res.success);
    System.assertEquals('https://na1.salesforce.com', res.instanceUrl);
  }

  @isTest
  static void testTestConnectionFailure() {
    Test.setMock(HttpCalloutMock.class, new MockSoapLoginFailure());

    Test.startTest();
    ExternalOrgAuthService.ConnectionTestResult res = ExternalOrgAuthService.testConnection(
      'user',
      'pass',
      'Production'
    );
    Test.stopTest();

    System.assertEquals(false, res.success);
    System.assert(res.message.contains('Login failed'));
  }

  @isTest
  static void testAuthExceptions() {
    Test.startTest();
    try {
      ExternalOrgAuthService.testConnection(null, null, null);
    } catch (Exception e) {
    }
    try {
      ExternalOrgAuthService.login(null, null, null);
    } catch (Exception e) {
    }
    Test.stopTest();
  }

  // ==========================================
  // Query Service Tests
  // ==========================================
  @isTest
  static void testQueryWithSession() {
    Test.setMock(HttpCalloutMock.class, new MockQueryResponse());

    Test.startTest();
    ExternalOrgQueryService.QueryResultWrapper res = ExternalOrgQueryService.queryWithSession(
      'sess',
      'https://inst',
      'SELECT Id FROM Account'
    );
    Test.stopTest();

    System.assertEquals(1, res.totalSize);
    System.assertEquals(1, res.rows.size());
    System.assertEquals('001FakeId', res.rows[0].get('Id'));
  }

  @isTest
  static void testQueryByUrl() {
    Test.setMock(HttpCalloutMock.class, new MockQueryResponse());

    Test.startTest();
    ExternalOrgQueryService.QueryResultWrapper res = ExternalOrgQueryService.queryByUrl(
      'sess',
      'https://inst',
      '/services/data/v62.0/query/01g...'
    );
    Test.stopTest();
  }

  @isTest
  static void testQueryExceptions() {
    Test.startTest();
    try {
      ExternalOrgQueryService.queryWithSession(null, null, null);
    } catch (Exception e) {
    }
    try {
      ExternalOrgQueryService.queryByUrl(null, null, null);
    } catch (Exception e) {
    }
    try {
      ExternalOrgQueryService.queryCurrent(null, null);
    } catch (Exception e) {
    }
    Test.stopTest();
  }

  // ==========================================
  // Describe Service Tests
  // ==========================================
  @isTest
  static void testGetAvailableObjects() {
    Test.setMock(HttpCalloutMock.class, new MockDescribeGlobal());

    Test.startTest();
    List<String> objs = ExternalOrgDescribeService.getAvailableObjects(
      'sess',
      'https://inst'
    );
    Test.stopTest();

    System.assert(objs.contains('Account'));
    System.assert(objs.contains('Contact'));
  }

  @isTest
  static void testDescribeExceptions() {
    Test.startTest();
    try {
      ExternalOrgDescribeService.getAvailableObjects(null, null);
    } catch (Exception e) {
    }
    try {
      ExternalOrgDescribeService.getObjectDependencies(
        null,
        null,
        null,
        null,
        null
      );
    } catch (Exception e) {
    }
    Test.stopTest();
  }

  // ==========================================
  // Mocks
  // ==========================================
  class MockSoapLoginSuccess implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String body =
        '<?xml version="1.0" encoding="UTF-8"?>' +
        '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com">' +
        '<soapenv:Body><loginResponse><result>' +
        '<sessionId>FakeSessionId</sessionId>' +
        '<serverUrl>https://na1.salesforce.com/services/Soap/u/62.0</serverUrl>' +
        '</result></loginResponse></soapenv:Body></soapenv:Envelope>';
      res.setBody(body);
      return res;
    }
  }

  class MockSoapLoginFailure implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Internal Server Error');
      res.setBody(
        '<soapenv:Fault><faultstring>INVALID_LOGIN</faultstring></soapenv:Fault>'
      );
      return res;
    }
  }

  class MockQueryResponse implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String body = '{"totalSize": 1, "done": true, "nextRecordsUrl": "/next", "records": [{"Id": "001FakeId", "Name": "Test", "attributes": {"type": "Account"}}]}';
      res.setBody(body);
      return res;
    }
  }

  class MockDescribeGlobal implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String body = '{"sobjects": [{"name": "Account", "queryable": true}, {"name": "Contact", "queryable": true}, {"name": "Hidden", "queryable": false}]}';
      res.setBody(body);
      return res;
    }
  }
}
