public with sharing class ExternalOrgQueryService {
  public class QueryResultWrapper {
    @AuraEnabled
    public Integer totalSize;
    @AuraEnabled
    public Boolean done;
    @AuraEnabled
    public List<String> columns;
    @AuraEnabled
    public List<Map<String, Object>> rows;
    @AuraEnabled
    public String nextRecordsUrl;
  }

  public static QueryResultWrapper loginAndQuery(
    String username,
    String password,
    String environment,
    String soql
  ) {
    System.debug(
      'ExternalOrgQueryService.loginAndQuery invoked. Username=' +
        username +
        ', Env=' +
        environment
    );
    try {
      if (
        String.isBlank(username) ||
        String.isBlank(password) ||
        String.isBlank(environment) ||
        String.isBlank(soql)
      ) {
        throw new CalloutException(
          'All inputs (username, password, environment, soql) are required.'
        );
      }

      ExternalOrgAuthService.LoginResult loginResult = ExternalOrgAuthService.login(
        username,
        password,
        environment
      );

      HttpRequest request = new HttpRequest();
      request.setMethod('GET');

      String soapServerUrl = loginResult.serverUrl;
      Integer idx = soapServerUrl.indexOf('/services/Soap');
      if (idx <= 0) {
        throw new CalloutException(
          'Unexpected serverUrl in login response: ' + soapServerUrl
        );
      }
      String hostBase = soapServerUrl.substring(0, idx);
      String endpoint =
        hostBase +
        '/services/data/v62.0/query?q=' +
        EncodingUtil.urlEncode(soql, 'UTF-8');
      request.setEndpoint(endpoint);
      request.setHeader('Authorization', 'Bearer ' + loginResult.sessionId);
      request.setHeader('Content-Type', 'application/json');

      Http http = new Http();
      System.debug('Sending REST query callout to: ' + endpoint);
      HTTPResponse response = http.send(request);
      System.debug('REST query response code: ' + response.getStatusCode());

      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        throw new CalloutException(
          'Query failed: ' + response.getStatus() + ' ' + response.getBody()
        );
      }

      return parseQueryResponse(response.getBody());
    } catch (Exception e) {
      System.debug(
        'loginAndQuery Error: ' +
          e.getMessage() +
          ' Stack: ' +
          e.getStackTraceString()
      );
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static QueryResultWrapper queryWithSession(
    String sessionId,
    String instanceUrl,
    String soql
  ) {
    System.debug('queryWithSession invoked. SOQL: ' + soql);
    try {
      if (
        String.isBlank(sessionId) ||
        String.isBlank(instanceUrl) ||
        String.isBlank(soql)
      ) {
        throw new CalloutException(
          'SessionId, instanceUrl, and soql are required.'
        );
      }

      HttpRequest request = new HttpRequest();
      request.setMethod('GET');
      String endpoint =
        instanceUrl +
        '/services/data/v62.0/query?q=' +
        EncodingUtil.urlEncode(soql, 'UTF-8');
      request.setEndpoint(endpoint);
      request.setHeader('Authorization', 'Bearer ' + sessionId);
      request.setHeader('Content-Type', 'application/json');

      Http http = new Http();
      HTTPResponse response = http.send(request);

      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        throw new CalloutException(
          'Query failed: ' + response.getStatus() + ' ' + response.getBody()
        );
      }

      return parseQueryResponse(response.getBody());
    } catch (Exception e) {
      System.debug('queryWithSession Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static QueryResultWrapper queryByUrl(
    String sessionId,
    String instanceUrl,
    String url
  ) {
    System.debug('queryByUrl invoked. URL: ' + url);
    try {
      if (
        String.isBlank(sessionId) ||
        String.isBlank(instanceUrl) ||
        String.isBlank(url)
      ) {
        throw new CalloutException(
          'SessionId, instanceUrl, and url are required.'
        );
      }

      HttpRequest request = new HttpRequest();
      request.setMethod('GET');
      String endpoint = url.startsWith('http') ? url : instanceUrl + url;
      request.setEndpoint(endpoint);
      request.setHeader('Authorization', 'Bearer ' + sessionId);
      request.setHeader('Content-Type', 'application/json');

      Http http = new Http();
      HTTPResponse response = http.send(request);

      if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
        throw new CalloutException(
          'Query failed: ' + response.getStatus() + ' ' + response.getBody()
        );
      }

      return parseQueryResponse(response.getBody());
    } catch (Exception e) {
      System.debug('queryByUrl Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static QueryResultWrapper queryCurrent(String soql) {
    return queryCurrent(soql, null);
  }

  public static QueryResultWrapper queryCurrent(
    String soql,
    List<String> fields
  ) {
    if (String.isBlank(soql)) {
      AuraHandledException ahe = new AuraHandledException('SOQL is required.');
      ahe.setMessage('SOQL is required.');
      throw ahe;
    }
    try {
      String finalSoql = soql;
      if (!finalSoql.toUpperCase().contains('WITH SECURITY_ENFORCED')) {
          Integer limitIdx = finalSoql.toUpperCase().lastIndexOf(' LIMIT ');
          if (limitIdx != -1) {
              finalSoql = finalSoql.substring(0, limitIdx) + ' WITH SECURITY_ENFORCED ' + finalSoql.substring(limitIdx);
          } else {
              finalSoql += ' WITH SECURITY_ENFORCED';
          }
      }
      List<SObject> recs = Database.query(finalSoql);
      QueryResultWrapper wrap = new QueryResultWrapper();
      wrap.totalSize = recs.size();
      wrap.done = true;
      List<Map<String, Object>> rows = new List<Map<String, Object>>();
      Set<String> allCols = new Set<String>();

      for (SObject s : recs) {
        Map<String, Object> row = new Map<String, Object>();
        if (fields != null && !fields.isEmpty()) {
          for (String f : fields) {
            // Handle relationship fields (e.g. Account.Name) if necessary, 
            // but for seeding we mostly care about flat fields. 
            // However, s.get() works for direct fields.
            try {
               Object val = s.get(f);
               row.put(f, val);
               allCols.add(f);
            } catch (Exception e) {
               // Field might not be in query or invalid
            }
          }
          // Ensure Id is always there
          row.put('Id', s.Id);
          allCols.add('Id');
        } else {
          Map<String, Object> populated = s.getPopulatedFieldsAsMap();
          for (String k : populated.keySet()) {
            row.put(k, populated.get(k));
            allCols.add(k);
          }
        }
        rows.add(row);
      }
      
      List<String> columns = new List<String>(allCols);
      Boolean hasId = false;
      for (String c : columns) {
        if (c == 'Id') {
          hasId = true;
          break;
        }
      }
      if (hasId && !columns.isEmpty()) {
        List<String> reordered = new List<String>();
        reordered.add('Id');
        for (String c : columns) {
          if (c != 'Id')
            reordered.add(c);
        }
        columns = reordered;
      }
      wrap.columns = columns;
      wrap.rows = rows;
      return wrap;
    } catch (Exception e) {
      System.debug('queryCurrent Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  private static QueryResultWrapper parseQueryResponse(String responseBody) {
    Map<String, Object> untyped = (Map<String, Object>) JSON.deserializeUntyped(
      responseBody
    );
    QueryResultWrapper resultWrapper = new QueryResultWrapper();
    resultWrapper.totalSize = (Integer) untyped.get('totalSize');
    resultWrapper.done = (Boolean) untyped.get('done');
    resultWrapper.nextRecordsUrl = (String) untyped.get('nextRecordsUrl');

    List<Object> rawRecords = (List<Object>) untyped.get('records');
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    List<String> columns = new List<String>();
    if (rawRecords != null) {
      Map<String, Boolean> seenColumns = new Map<String, Boolean>();
      for (Integer i = 0; i < rawRecords.size(); i++) {
        Map<String, Object> rec = (Map<String, Object>) rawRecords[i];
        if (rec == null)
          continue;
        rec.remove('attributes');
        rows.add(rec);

        for (String k : rec.keySet()) {
          if (!seenColumns.containsKey(k)) {
            columns.add(k);
            seenColumns.put(k, true);
          }
        }
      }
    }

    Boolean hasId = false;
    for (String c : columns) {
      if (c == 'Id') {
        hasId = true;
        break;
      }
    }
    if (hasId && (columns.isEmpty() == false)) {
      List<String> reordered = new List<String>();
      reordered.add('Id');
      for (String c : columns) {
        if (c != 'Id')
          reordered.add(c);
      }
      columns = reordered;
    }

    resultWrapper.columns = columns;
    resultWrapper.rows = rows;
    return resultWrapper;
  }
}
