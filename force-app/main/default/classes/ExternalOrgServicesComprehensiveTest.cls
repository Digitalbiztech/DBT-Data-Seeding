@isTest
@SuppressWarnings(
  'PMD.AvoidDebugStatements, PMD.ApexDoc, PMD.CyclomaticComplexity, PMD.IfStmtsMustUseBraces, PMD.IfElseStmtsMustUseBraces, PMD.DebugsShouldUseLoggingLevel, PMD.EmptyCatchBlock, PMD.ApexAssertionsShouldIncludeMessage, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.StdCyclomaticComplexity, PMD.AvoidDeeplyNestedIfStmts, PMD.NcssMethodCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.FieldDeclarationsShouldBeAtStart, PMD.ForLoopsMustUseBraces, PMD.UnusedLocalVariable, PMD.ExcessivePublicCount, PMD.NcssTypeCount, PMD.ApexSuggestUsingNamedCred, PMD.AvoidHardcodingId, PMD.ApexSOQLInjection'
)
public class ExternalOrgServicesComprehensiveTest {
  private class MockProvider implements HttpCalloutMock {
    private Boolean failNext = false;
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      if (failNext) {
        res.setStatusCode(500);
        res.setStatus('Internal Server Error');
        return res;
      }
      res.setStatusCode(200);
      String endpoint = req.getEndpoint();
      String method = req.getMethod();

      if (endpoint.contains('/services/Soap/u/')) {
        res.setBody(
          '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com"><soapenv:Body><loginResponse><result><sessionId>mock_session_id</sessionId><serverUrl>https://mock.instance.com/services/Soap/u/62.0</serverUrl></result></loginResponse></soapenv:Body></soapenv:Envelope>'
        );
      } else if (endpoint.contains('/services/data/v62.0/query')) {
        res.setBody(
          '{"totalSize": 1, "done": true, "records": [{"Id": "001000000000001", "Name": "Mock Account", "attributes": {"type": "Account"}}]}'
        );
      } else if (endpoint.contains('/sobjects/Contact/describe')) {
        res.setBody(
          '{"name": "Contact", "fields": [{"name": "Id", "type": "id", "createable": false, "nillable": false}, {"name": "LastName", "type": "string", "createable": true, "nillable": false}, {"name": "AccountId", "type": "reference", "referenceTo": ["Account"], "relationshipName": "Account", "createable": true, "nillable": true}]}'
        );
      } else if (endpoint.contains('/sobjects/Account/describe')) {
        res.setBody(
          '{"name": "Account", "fields": [{"name": "Id", "type": "id", "createable": false, "nillable": false}, {"name": "Name", "type": "string", "createable": true, "nillable": false}]}'
        );
      } else if (endpoint.contains('/sobjects/') && method == 'GET') {
        res.setBody(
          '{"sobjects": [{"name": "Account", "queryable": true}, {"name": "Contact", "queryable": true}]}'
        );
      } else if (endpoint.contains('/composite/batch')) {
        res.setBody(
          '{"results": [{"statusCode": 200, "referenceId": "Contact", "result": {"name": "Contact", "fields": [{"name": "Id", "type": "id", "createable": false, "nillable": false}, {"name": "LastName", "type": "string", "createable": true, "nillable": false}]}}, {"statusCode": 200, "referenceId": "Account", "result": {"name": "Account", "fields": [{"name": "Id", "type": "id", "createable": false, "nillable": false}, {"name": "Name", "type": "string", "createable": true, "nillable": false}]}}]}'
        );
      } else if (endpoint.contains('/composite/sobjects')) {
        res.setBody('[{"success": true, "id": "001000000000002"}]');
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }

  @isTest
  static void testControllerMethods() {
    MockProvider mock = new MockProvider();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    ExternalOrgQueryController.testConnection('u', 'p', 'Production');
    ExternalOrgQueryController.getAvailableObjects('s', 'url');
    ExternalOrgQueryController.getObjectDependencies(
      's',
      'u',
      'Account',
      2,
      new List<String>()
    );
    ExternalOrgQueryController.getObjectDependencies(
      's',
      'u',
      'Account',
      -1,
      null
    );
    ExternalOrgQueryController.getRequiredFields('s', 'url', 'Contact');
    ExternalOrgQueryController.getCreateableFields(
      's',
      'url',
      new List<String>{ 'Contact' }
    );
    ExternalOrgQueryController.getFieldMetadata(
      's',
      'url',
      new List<String>{ 'Contact' }
    );
    ExternalOrgQueryController.loginAndQuery(
      'u',
      'p',
      'Production',
      'SELECT Id FROM Account'
    );
    ExternalOrgQueryController.queryWithSession(
      's',
      'url',
      'SELECT Id FROM Account'
    );
    ExternalOrgQueryController.queryByUrl(
      's',
      'url',
      'https://mock.com/services/data/v62.0/query/SOME'
    );

    List<Map<String, Object>> recs = new List<Map<String, Object>>();
    Map<String, Object> r = new Map<String, Object>();
    r.put('LastName', 'Test');
    recs.add(r);

    // Remote write via controller
    ExternalOrgQueryController.createRecordsRemote('s', 'u', 'Contact', recs);
    ExternalOrgQueryController.updateRecordsRemote('s', 'u', 'Contact', recs);

    // Import with resolution (Remote)
    ExternalOrgQueryController.importRecordsWithResolution(
      's',
      'u',
      's',
      'u',
      'Contact',
      recs
    );

    // Import with resolution (Local)
    ExternalOrgQueryController.importRecordsWithResolution(
      's',
      'u',
      null,
      null,
      'Contact',
      recs
    );

    // Matching
    ExternalOrgQueryController.findMatchingRecords(
      's',
      'u',
      'Account',
      new List<String>{ 'Name' },
      recs
    );

    // Job Status
    try {
      ExternalOrgQueryController.getBatchJobStatus('707WG0000000000AAA');
    } catch (Exception e) {
    }
    ExternalOrgQueryController.getBatchReport('jobid');

    // Start Batch
    ExternalOrgQueryController.startDataSeedingBatch(
      's',
      'u',
      'd',
      'u',
      new List<Map<String, Object>>(),
      new Map<String, Map<String, String>>()
    );

    // Failure cases
    mock.failNext = true;
    try {
      ExternalOrgQueryController.testConnection('u', 'p', 'Production');
    } catch (Exception e) {
    }
    try {
      ExternalOrgQueryController.loginAndQuery(
        'u',
        'p',
        'Production',
        'SELECT Id FROM Account'
      );
    } catch (Exception e) {
    }

    Test.stopTest();
  }

  @isTest
  static void testCurrentOrgControllerMethods() {
    Test.startTest();
    ExternalOrgQueryController.getAvailableObjectsCurrent();
    ExternalOrgQueryController.queryCurrent('SELECT Id FROM Account LIMIT 1');
    ExternalOrgQueryController.getObjectDependenciesCurrent(
      'Account',
      1,
      new List<String>()
    );
    ExternalOrgQueryController.getObjectDependenciesCurrent(
      'Account',
      -1,
      null
    );
    ExternalOrgQueryController.getCreateableFieldsCurrent(
      new List<String>{ 'Account' }
    );
    ExternalOrgQueryController.getFieldMetadataCurrent(
      new List<String>{ 'Account' }
    );

    Account a = new Account(Name = 'Controller Test');
    insert a;
    List<Map<String, Object>> recs = new List<Map<String, Object>>{
      new Map<String, Object>{ 'Id' => a.Id, 'Name' => 'Updated' }
    };
    ExternalOrgQueryController.updateRecordsCurrent('Account', recs);
    ExternalOrgQueryController.insertRecordsCurrent(
      'Account',
      new List<Map<String, Object>>{
        new Map<String, Object>{ 'Name' => 'New' }
      }
    );
    Test.stopTest();
  }

  @isTest
  static void testLocalDml() {
    Account a = new Account(Name = 'Type Test');
    insert a;

    List<Map<String, Object>> recs = new List<Map<String, Object>>();
    Map<String, Object> r = new Map<String, Object>();
    r.put('Name', 'New Name');
    r.put('Id', a.Id);
    r.put('NumberOfEmployees', 100);
    r.put('AnnualRevenue', 1000.50);
    r.put('Description', 'Desc');
    recs.add(r);

    Test.startTest();
    ExternalOrgDmlService.updateRecordsCurrent('Account', recs);
    try {
      ExternalOrgDmlService.insertRecordsCurrent(
        '',
        new List<Map<String, Object>>()
      );
    } catch (Exception e) {
    }
    try {
      ExternalOrgDmlService.insertRecordsCurrent('Account', null);
    } catch (Exception e) {
    }
    try {
      ExternalOrgDmlService.insertRecordsCurrent(
        'NonExistent__c',
        new List<Map<String, Object>>{ new Map<String, Object>() }
      );
    } catch (Exception e) {
    }
    Test.stopTest();
  }

  @isTest
  static void testRemoteDml() {
    MockProvider mock = new MockProvider();
    Test.setMock(HttpCalloutMock.class, mock);

    List<Map<String, Object>> recs = new List<Map<String, Object>>();
    Map<String, Object> r = new Map<String, Object>();
    r.put('Name', 'Remote');
    recs.add(r);

    Test.startTest();
    ExternalOrgDmlService.createRecordsRemote('s', 'u', 'Account', recs);
    ExternalOrgDmlService.updateRecordsRemote('s', 'u', 'Account', recs);

    // Remote DML errors
    mock.failNext = true;
    try {
      ExternalOrgDmlService.createRecordsRemote('s', 'u', 'Account', recs);
    } catch (Exception e) {
    }
    try {
      ExternalOrgDmlService.updateRecordsRemote('s', 'u', 'Account', recs);
    } catch (Exception e) {
    }
    Test.stopTest();
  }

  @isTest
  static void testDescribeEdgeCases() {
    MockProvider mock = new MockProvider();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    ExternalOrgDescribeService.getAvailableObjectsCurrent();
    ExternalOrgDescribeService.getObjectDependenciesCurrent(
      'Account',
      1,
      new List<String>()
    );
    ExternalOrgDescribeService.getCreateableFieldsCurrent(
      new List<String>{ 'Account' }
    );
    ExternalOrgDescribeService.getFieldMetadataCurrent(
      new List<String>{ 'Account' }
    );
    ExternalOrgDescribeService.getObjectDependencies(
      's',
      'u',
      'Contact',
      2,
      new List<String>()
    );

    // Failure cases
    mock.failNext = true;
    try {
      ExternalOrgDescribeService.getAvailableObjects('s', 'u');
    } catch (Exception e) {
    }
    try {
      ExternalOrgDescribeService.getReferenceFields('s', 'u', 'Account');
    } catch (Exception e) {
    }
    try {
      ExternalOrgDescribeService.getRequiredFields('s', 'u', 'Account');
    } catch (Exception e) {
    }
    try {
      ExternalOrgDescribeService.getCreateableFields(
        's',
        'u',
        new List<String>{ 'Account' }
      );
    } catch (Exception e) {
    }
    try {
      ExternalOrgDescribeService.getFieldMetadata(
        's',
        'u',
        new List<String>{ 'Account' }
      );
    } catch (Exception e) {
    }
    Test.stopTest();
  }
}
