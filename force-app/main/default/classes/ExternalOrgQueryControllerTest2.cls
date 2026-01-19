@isTest
private class ExternalOrgQueryControllerTest2 {
  @isTest
  static void testGetRequiredFields() {
    // Mocking metadata describe is hard in Apex without heavy lifting or Stub API.
    // But we can test against the local org's schema since the controller supports it or uses callouts.
    // Wait, getRequiredFields makes a callout to `describeSObject`.
    // We need to mock the callout.

    Test.setMock(HttpCalloutMock.class, new MockDescribeResponse());

    Test.startTest();
    List<String> reqs = ExternalOrgQueryController.getRequiredFields(
      'sess',
      'https://example.com',
      'Account'
    );
    Test.stopTest();

    System.assertNotEquals(null, reqs);
    // In our mock, we will define 'Name' as required
    System.assert(reqs.contains('Name'), 'Name should be required');
  }

  class MockDescribeResponse implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);

      // Minimal describe response
      String body =
        '{' +
        '"fields": [' +
        '{ "name": "Name", "nillable": false, "defaultedOnCreate": false, "createable": true, "type": "string" },' +
        '{ "name": "Description", "nillable": true, "defaultedOnCreate": false, "createable": true, "type": "string" },' +
        '{ "name": "OwnerId", "nillable": false, "defaultedOnCreate": true, "createable": true, "type": "reference" }' +
        ']' +
        '}';

      res.setBody(body);
      return res;
    }
  }
}
