public with sharing class ExternalOrgAuthService {
  public class LoginResult {
    @AuraEnabled
    public String sessionId;
    @AuraEnabled
    public String serverUrl;
  }

  public class ConnectionTestResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String instanceUrl;
    @AuraEnabled
    public String apiVersion;
    @AuraEnabled
    public String sessionId;
  }

  public static ConnectionTestResult testConnection(
    String username,
    String password,
    String environment
  ) {
    System.debug(
      'ExternalOrgAuthService.testConnection invoked. Username=' +
        username +
        ', Env=' +
        environment
    );
    ConnectionTestResult res = new ConnectionTestResult();

    try {
      if (
        String.isBlank(username) ||
        String.isBlank(password) ||
        String.isBlank(environment)
      ) {
        throw new CalloutException(
          'Username, password, and environment are required.'
        );
      }

      LoginResult loginResult = login(username, password, environment);
      Integer idx = loginResult.serverUrl.indexOf('/services/Soap');
      String hostBase = idx > 0
        ? loginResult.serverUrl.substring(0, idx)
        : loginResult.serverUrl;

      res.success = true;
      res.message = 'Login successful';
      res.instanceUrl = hostBase;
      res.apiVersion = '62.0';
      res.sessionId = loginResult.sessionId;
      return res;
    } catch (Exception e) {
      System.debug(
        'testConnection Error: ' +
          e.getMessage() +
          ' Stack: ' +
          e.getStackTraceString()
      );
      res.success = false;
      res.message = e.getMessage();
      return res;
    }
  }

  public static LoginResult login(
    String username,
    String password,
    String environment
  ) {
    String loginHost = (environment == 'Sandbox')
      ? 'https://test.salesforce.com'
      : 'https://login.salesforce.com';
    System.debug('Preparing SOAP login callout to host: ' + loginHost);
    String loginEndpoint = loginHost + '/services/Soap/u/62.0';

    String soapEnvelope =
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
      'xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
      '<env:Body>' +
      '<n1:login xmlns:n1="urn:partner.soap.sforce.com">' +
      '<n1:username>' +
      xmlEscape(username) +
      '</n1:username>' +
      '<n1:password>' +
      xmlEscape(password) +
      '</n1:password>' +
      '</n1:login>' +
      '</env:Body>' +
      '</env:Envelope>';

    HttpRequest request = new HttpRequest();
    request.setEndpoint(loginEndpoint);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
    request.setHeader('SOAPAction', 'login');
    request.setBody(soapEnvelope);

    Http http = new Http();
    System.debug('Sending SOAP login callout to: ' + loginEndpoint);
    HTTPResponse response = http.send(request);

    System.debug('Login response code: ' + response.getStatusCode());

    if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
      String msg =
        'Login failed: ' +
        response.getStatus() +
        ' ' +
        response.getBody();
      System.debug(msg);
      throw new CalloutException(msg);
    }

    Dom.Document doc = new Dom.Document();
    doc.load(response.getBody());

    Dom.XMLNode envelope = doc.getRootElement();
    Dom.XMLNode body = envelope.getChildElement(
      'Body',
      'http://schemas.xmlsoap.org/soap/envelope/'
    );
    if (body == null) {
      throw new CalloutException('Invalid SOAP response: missing Body');
    }
    Dom.XMLNode loginResponse = body.getChildElement(
      'loginResponse',
      'urn:partner.soap.sforce.com'
    );
    if (loginResponse == null) {
      Dom.XMLNode fault = body.getChildElement(
        'Fault',
        'http://schemas.xmlsoap.org/soap/envelope/'
      );
      if (fault != null) {
        String faultText = fault.getText();
        throw new CalloutException(
          'Login fault' + (String.isBlank(faultText) ? '' : (': ' + faultText))
        );
      }
      throw new CalloutException(
        'Invalid SOAP response: missing loginResponse'
      );
    }
    Dom.XMLNode resultNode = loginResponse.getChildElement(
      'result',
      'urn:partner.soap.sforce.com'
    );
    if (resultNode == null) {
      throw new CalloutException('Invalid SOAP response: missing result');
    }

    String sessionId = safeGetText(resultNode, 'sessionId');
    String serverUrl = safeGetText(resultNode, 'serverUrl');
    if (String.isBlank(sessionId) || String.isBlank(serverUrl)) {
      throw new CalloutException(
        'Login response missing sessionId or serverUrl'
      );
    }

    LoginResult loginResult = new LoginResult();
    loginResult.sessionId = sessionId;
    loginResult.serverUrl = serverUrl;
    return loginResult;
  }

  private static String safeGetText(Dom.XMLNode parent, String childLocalName) {
    Dom.XMLNode child = parent.getChildElement(
      childLocalName,
      'urn:partner.soap.sforce.com'
    );
    return child == null ? null : child.getText();
  }

  private static String xmlEscape(String input) {
    if (input == null) {
      return '';
    }
    String s = input;
    s = s.replace('&', '&amp;');
    s = s.replace('<', '&lt;');
    s = s.replace('>', '&gt;');
    s = s.replace('"', '&quot;');
    s = s.replace(String.fromCharArray(new List<Integer>{ 39 }), '&apos;');
    return s;
  }
}
