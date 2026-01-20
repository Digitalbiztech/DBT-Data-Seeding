public with sharing class ExternalOrgDmlService {
  public class InsertMapping {
    @AuraEnabled
    public String oldId;
    @AuraEnabled
    public String newId;
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String recordUrl;
  }

  public static List<InsertMapping> insertRecordsCurrent(
    String objectName,
    List<Map<String, Object>> records
  ) {
    try {
      if (String.isBlank(objectName)) {
        throw new CalloutException('objectName is required');
      }
      List<InsertMapping> out = new List<InsertMapping>();
      if (records == null || records.isEmpty()) {
        return out;
      }
      Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
      if (t == null) {
        throw new CalloutException('Unknown sObject: ' + objectName);
      }
      List<SObject> toInsert = new List<SObject>();
      List<String> oldIds = new List<String>();
      List<String> inputNames = new List<String>();

      for (Map<String, Object> rec : records) {
        if (rec == null)
          continue;
        SObject sobj = t.newSObject();
        String oldId = (rec.containsKey('Id') && rec.get('Id') != null)
          ? String.valueOf(rec.get('Id'))
          : null;
        oldIds.add(oldId);

        String recName = (rec.containsKey('Name'))
          ? String.valueOf(rec.get('Name'))
          : oldId;
        inputNames.add(recName);

        for (String key : rec.keySet()) {
          if (key == 'Id')
            continue; // never attempt to set Id on insert

          if (objectName == 'User') {
            String low = key.toLowerCase();
            if (low == 'userroleid' || low.contains('userlicense')) {
              continue;
            }
          }

          try {
            sobj.put(key, rec.get(key));
          } catch (Exception e) {
            // Ignore fields that do not exist or cannot be set
          }
        }
        toInsert.add(sobj);
      }
      Database.SaveResult[] results = Database.insert(toInsert, false);
      String baseUrl = URL.getOrgDomainUrl().toExternalForm();

      for (Integer i = 0; i < results.size(); i++) {
        InsertMapping m = new InsertMapping();
        m.oldId = i < oldIds.size() ? oldIds[i] : null;
        m.name = i < inputNames.size() ? inputNames[i] : null;

        Database.SaveResult sr = results[i];
        if (sr.isSuccess()) {
          m.success = true;
          m.newId = (String) sr.getId();
          m.recordUrl = baseUrl + '/' + m.newId;
        } else {
          m.success = false;
          if (sr.getErrors() != null && sr.getErrors().size() > 0) {
            Database.Error err = sr.getErrors()[0];
            String msg = err.getMessage();
            if (err.getFields() != null && !err.getFields().isEmpty()) {
              msg += ' (Fields: ' + String.join(err.getFields(), ', ') + ')';
            }
            m.errorMessage = msg;
          } else {
            m.errorMessage = 'Unknown DML error';
          }
        }
        out.add(m);
      }
      return out;
    } catch (Exception e) {
      System.debug('insertRecordsCurrent Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static List<InsertMapping> updateRecordsCurrent(
    String objectName,
    List<Map<String, Object>> records
  ) {
    try {
      if (String.isBlank(objectName)) {
        throw new CalloutException('objectName is required');
      }
      List<InsertMapping> out = new List<InsertMapping>();
      if (records == null || records.isEmpty()) {
        return out;
      }
      Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
      if (t == null) {
        throw new CalloutException('Unknown sObject: ' + objectName);
      }
      List<SObject> toUpdate = new List<SObject>();
      List<String> targetIds = new List<String>();
      List<String> inputNames = new List<String>();

      for (Map<String, Object> rec : records) {
        if (rec == null)
          continue;
        SObject sobj = t.newSObject();
        String targetId = (rec.containsKey('Id') && rec.get('Id') != null)
          ? String.valueOf(rec.get('Id'))
          : null;
        if (String.isBlank(targetId)) {
          continue;
        }
        targetIds.add(targetId);
        String recName = (rec.containsKey('Name'))
          ? String.valueOf(rec.get('Name'))
          : targetId;
        inputNames.add(recName);

        for (String key : rec.keySet()) {
          if (objectName == 'User') {
            String low = key.toLowerCase();
            if (low == 'userroleid' || low.contains('userlicense')) {
              continue;
            }
          }

          try {
            sobj.put(key, rec.get(key));
          } catch (Exception e) {
            // Ignore
          }
        }
        toUpdate.add(sobj);
      }

      if (toUpdate.isEmpty()) {
        return out;
      }

      Database.SaveResult[] results = Database.update(toUpdate, false);
      String baseUrl = URL.getOrgDomainUrl().toExternalForm();

      for (Integer i = 0; i < results.size(); i++) {
        InsertMapping m = new InsertMapping();
        m.oldId = i < targetIds.size() ? targetIds[i] : null;
        m.name = i < inputNames.size() ? inputNames[i] : null;

        Database.SaveResult sr = results[i];
        if (sr.isSuccess()) {
          m.success = true;
          m.newId = (String) sr.getId();
          m.recordUrl = baseUrl + '/' + m.newId;
        } else {
          m.success = false;
          if (sr.getErrors() != null && sr.getErrors().size() > 0) {
            Database.Error err = sr.getErrors()[0];
            String msg = err.getMessage();
            if (err.getFields() != null && !err.getFields().isEmpty()) {
              msg += ' (Fields: ' + String.join(err.getFields(), ', ') + ')';
            }
            m.errorMessage = msg;
          } else {
            m.errorMessage = 'Unknown DML error';
          }
        }
        out.add(m);
      }
      return out;
    } catch (Exception e) {
      System.debug('updateRecordsCurrent Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static List<InsertMapping> createRecordsRemote(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<Map<String, Object>> records
  ) {
    return executeRemoteComposite(
      sessionId,
      instanceUrl,
      objectName,
      records,
      'POST'
    );
  }

  public static List<InsertMapping> updateRecordsRemote(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<Map<String, Object>> records
  ) {
    return executeRemoteComposite(
      sessionId,
      instanceUrl,
      objectName,
      records,
      'PATCH'
    );
  }

  private static List<InsertMapping> executeRemoteComposite(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<Map<String, Object>> records,
    String method
  ) {
    List<InsertMapping> out = new List<InsertMapping>();
    if (records == null || records.isEmpty())
      return out;

    Integer batchSize = 200;
    for (Integer i = 0; i < records.size(); i += batchSize) {
      List<Map<String, Object>> chunk = new List<Map<String, Object>>();
      for (Integer j = i; j < Math.min(i + batchSize, records.size()); j++) {
        chunk.add(records[j]);
      }
      out.addAll(sendBatch(sessionId, instanceUrl, objectName, chunk, method));
    }
    return out;
  }

  private static List<InsertMapping> sendBatch(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<Map<String, Object>> records,
    String method
  ) {
    try {
      if (
        String.isBlank(sessionId) ||
        String.isBlank(instanceUrl) ||
        String.isBlank(objectName)
      ) {
        throw new CalloutException(
          'SessionId, InstanceUrl, and ObjectName are required.'
        );
      }
      List<InsertMapping> out = new List<InsertMapping>();
      if (records == null || records.isEmpty())
        return out;

      List<Map<String, Object>> payloadRecords = new List<Map<String, Object>>();
      List<String> trackingIds = new List<String>();
      List<String> inputNames = new List<String>();

      for (Map<String, Object> r : records) {
        Map<String, Object> rec = new Map<String, Object>(r);

        String tid = r.containsKey('Id') ? String.valueOf(r.get('Id')) : null;
        trackingIds.add(tid);

        String recName = (r.containsKey('Name'))
          ? String.valueOf(r.get('Name'))
          : tid;
        inputNames.add(recName);

        if (method == 'POST' && rec.containsKey('Id')) {
          rec.remove('Id');
        }

        if (objectName == 'User') {
          List<String> toRemove = new List<String>();
          for (String key : rec.keySet()) {
            String low = key.toLowerCase();
            if (low == 'userroleid' || low.contains('userlicense')) {
              toRemove.add(key);
            }
          }
          for (String key : toRemove) {
            rec.remove(key);
          }
        }

        Map<String, String> attributes = new Map<String, String>{
          'type' => objectName
        };
        rec.put('attributes', attributes);
        payloadRecords.add(rec);
      }

      Map<String, Object> requestBody = new Map<String, Object>();
      requestBody.put('allOrNone', false);
      requestBody.put('records', payloadRecords);

      HttpRequest req = new HttpRequest();
      req.setMethod(method);
      req.setEndpoint(instanceUrl + '/services/data/v62.0/composite/sobjects');
      req.setHeader('Authorization', 'Bearer ' + sessionId);
      req.setHeader('Content-Type', 'application/json');
      req.setBody(JSON.serialize(requestBody));

      Http http = new Http();
      HttpResponse res = http.send(req);

      if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
        List<Object> results = (List<Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        for (Integer i = 0; i < results.size(); i++) {
          Map<String, Object> result = (Map<String, Object>) results[i];
          InsertMapping m = new InsertMapping();
          m.oldId = (i < trackingIds.size()) ? trackingIds[i] : null;
          m.name = (i < inputNames.size()) ? inputNames[i] : null;
          Boolean success = (Boolean) result.get('success');
          m.success = success;
          if (success == true) {
            m.newId = (String) result.get('id');
            m.recordUrl = instanceUrl + '/' + m.newId;
          } else {
            List<Object> errors = (List<Object>) result.get('errors');
            if (errors != null && !errors.isEmpty()) {
              Map<String, Object> err = (Map<String, Object>) errors[0];
              String msg = (String) err.get('message');
              List<Object> fields = (List<Object>) err.get('fields');
              if (fields != null && !fields.isEmpty()) {
                msg += ' (Fields: ' + String.join(fields, ', ') + ')';
              }
              m.errorMessage = msg;
            } else {
              m.errorMessage = 'Unknown remote error';
            }
          }
          out.add(m);
        }
      } else {
        // If the entire batch fails (e.g. 400 Bad Request), ensure we return errors for all items
        // so the caller maintains index alignment.
        String failMsg =
          'Remote ' +
          method +
          ' failed: ' +
          res.getStatus() +
          ' ' +
          res.getBody();
        for (Integer i = 0; i < records.size(); i++) {
          InsertMapping m = new InsertMapping();
          m.oldId = (i < trackingIds.size()) ? trackingIds[i] : null;
          m.name = (i < inputNames.size()) ? inputNames[i] : null;
          m.success = false;
          m.errorMessage = failMsg;
          out.add(m);
        }
      }
      return out;
    } catch (Exception e) {
      System.debug('sendBatch Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }
}
