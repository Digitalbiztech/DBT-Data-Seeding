public with sharing class DataSeedingService {
  public class MatchResult {
    @AuraEnabled
    public String sourceId;
    @AuraEnabled
    public String destId;
  }

  public static List<MatchResult> findMatchingRecords(
    String sessionId,
    String instanceUrl,
    String objectName,
    List<String> matchFields,
    List<Map<String, Object>> sourceRecords
  ) {
    List<MatchResult> results = new List<MatchResult>();
    try {
      if (
        sourceRecords == null ||
        sourceRecords.isEmpty() ||
        matchFields == null ||
        matchFields.isEmpty()
      ) {
        return results;
      }

      Map<String, Set<String>> fieldValues = new Map<String, Set<String>>();
      for (String f : matchFields) {
        fieldValues.put(f, new Set<String>());
      }

      for (Map<String, Object> row : sourceRecords) {
        for (String f : matchFields) {
          Object val = row.get(f);
          if (val != null) {
            fieldValues.get(f).add(String.valueOf(val));
          }
        }
      }

      String selectClause = 'Id, ' + String.join(matchFields, ', ');
      String whereClause = '';

      for (String f : matchFields) {
        Set<String> vals = fieldValues.get(f);
        if (vals.isEmpty())
          continue;

        List<String> quoted = new List<String>();
        String quote = String.fromCharArray(new List<Integer>{ 39 });
        for (String v : vals) {
          quoted.add(quote + String.escapeSingleQuotes(v) + quote);
        }

        if (whereClause.length() > 0)
          whereClause += ' AND ';
        whereClause += f + ' IN (' + String.join(quoted, ',') + ')';
      }

      if (String.isBlank(whereClause)) {
        return results;
      }

      String soql =
        'SELECT ' +
        selectClause +
        ' FROM ' +
        objectName +
        ' WHERE ' +
        whereClause +
        ' LIMIT 10000';

      List<Map<String, Object>> destRows = new List<Map<String, Object>>();

      if (String.isNotBlank(sessionId) && String.isNotBlank(instanceUrl)) {
        ExternalOrgQueryService.QueryResultWrapper qr = ExternalOrgQueryService.queryWithSession(
          sessionId,
          instanceUrl,
          soql
        );
        if (qr != null && qr.rows != null) {
          destRows = qr.rows;
        }
      } else {
        for (SObject s : Database.query(soql)) {
          Map<String, Object> r = new Map<String, Object>();
          r.put('Id', s.Id);
          for (String f : matchFields) {
            try {
              r.put(f, s.get(f));
            } catch (Exception e) {
              /* ignore */
            }
          }
          destRows.add(r);
        }
      }

      Map<String, String> destMap = new Map<String, String>();
      for (Map<String, Object> d : destRows) {
        String key = generateCompositeKey(d, matchFields);
        if (!destMap.containsKey(key)) {
          destMap.put(key, (String) d.get('Id'));
        }
      }

      for (Map<String, Object> s : sourceRecords) {
        String key = generateCompositeKey(s, matchFields);
        if (destMap.containsKey(key)) {
          MatchResult mr = new MatchResult();
          mr.sourceId = (String) s.get('Id');
          mr.destId = destMap.get(key);
          results.add(mr);
        }
      }

      return results;
    } catch (Exception e) {
      System.debug('findMatchingRecords Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  private static String generateCompositeKey(
    Map<String, Object> record,
    List<String> fields
  ) {
    List<String> parts = new List<String>();
    for (String f : fields) {
      Object v = record.get(f);
      parts.add(v == null ? '' : String.valueOf(v));
    }
    return String.join(parts, '|');
  }

  public static String startDataSeedingBatch(
    String sourceSessionId,
    String sourceInstanceUrl,
    String destSessionId,
    String destInstanceUrl,
    List<Map<String, Object>> tasks,
    Map<String, Map<String, String>> planEdges
  ) {
    try {
      DataSeedingBatch batch = new DataSeedingBatch(
        sourceSessionId,
        sourceInstanceUrl,
        destSessionId,
        destInstanceUrl,
        tasks,
        planEdges,
        null
      );
      return Database.executeBatch(batch, 1);
    } catch (Exception e) {
      System.debug('startDataSeedingBatch Error: ' + e.getMessage());
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  public static AsyncApexJob getBatchJobStatus(String jobId) {
    AsyncApexJob job = [
      SELECT
        Id,
        Status,
        JobItemsProcessed,
        TotalJobItems,
        NumberOfErrors,
        ExtendedStatus,
        CreatedDate
      FROM AsyncApexJob
      WHERE Id = :jobId
    ];

    if (job.Status == 'Completed') {
      List<AsyncApexJob> chained = [
        SELECT
          Id,
          Status,
          JobItemsProcessed,
          TotalJobItems,
          NumberOfErrors,
          ExtendedStatus
        FROM AsyncApexJob
        WHERE
          ApexClass.Name = 'DataSeedingBatch'
          AND CreatedDate >= :job.CreatedDate
          AND Id != :jobId
          AND Status IN ('Queued', 'Processing', 'Preparing', 'Holding')
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!chained.isEmpty()) {
        return chained[0];
      }
    }
    return job;
  }

  public static String getBatchReport(String jobId) {
    System.debug('getBatchReport called for Job ID: ' + jobId);
    if (String.isBlank(jobId))
      return null;
    try {
      String queryId = jobId;
      if (jobId.length() > 15) {
        queryId = jobId.substring(0, 15);
      }
      String titlePrefix = 'SeedingReport_' + queryId;
      System.debug(
        'Searching for ContentVersion with Title starting with: ' + titlePrefix
      );
      List<ContentVersion> cvs = [
        SELECT VersionData
        FROM ContentVersion
        WHERE Title LIKE :titlePrefix + '%' AND IsLatest = TRUE
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!cvs.isEmpty()) {
        System.debug('Report found. Size: ' + cvs[0].VersionData.size());
        return cvs[0].VersionData.toString();
      } else {
        System.debug(
          'Report NOT found for Title starting with: ' + titlePrefix
        );
      }
    } catch (Exception e) {
      System.debug('Error retrieving batch report: ' + e.getMessage());
    }
    return null;
  }

  // --- Preprocessing Logic for Synchronous Import (Check & Import) ---

  public static List<Map<String, Object>> preprocessRecords(
    String objectName,
    List<Map<String, Object>> records,
    String sourceSessionId,
    String sourceInstanceUrl,
    String destSessionId,
    String destInstanceUrl
  ) {
    if (records == null || records.isEmpty()) return records;

    // Local ID Remap for this batch
    Map<String, Map<String, String>> idRemap = new Map<String, Map<String, String>>();
    
    // 1. Discover References
    Map<String, String> refFields = new Map<String, String>();
    try {
        if (String.isNotBlank(sourceSessionId) && String.isNotBlank(sourceInstanceUrl)) {
             refFields = ExternalOrgDescribeService.getReferenceFields(sourceSessionId, sourceInstanceUrl, objectName);
        } else if (String.isBlank(sourceSessionId)) { // Local source
             refFields = getLocalReferenceFields(objectName);
        }
    } catch (Exception e) {
        System.debug('preprocessRecords: Failed to discover references: ' + e.getMessage());
    }

    if (objectName == 'User') {
      resolveUserProfiles(records, idRemap, sourceSessionId, sourceInstanceUrl, destSessionId, destInstanceUrl);
      if (!refFields.containsKey('ProfileId')) {
        refFields.put('ProfileId', 'Profile');
      }
    }

    // 2. Scan for missing refs
    Map<String, Set<String>> missingRefs = new Map<String, Set<String>>();
    for (Map<String, Object> row : records) {
      for (String field : refFields.keySet()) {
        Object val = row.get(field);
        if (val != null && val instanceof String) {
          String sVal = (String) val;
          String parentObj = refFields.get(field);
          
          Boolean hasMapping = idRemap.containsKey(parentObj) && idRemap.get(parentObj).containsKey(sVal);
          if (!hasMapping) {
            if (!missingRefs.containsKey(parentObj)) {
              missingRefs.put(parentObj, new Set<String>());
            }
            missingRefs.get(parentObj).add(sVal);
          }
        }
      }
    }

    // 3. Resolve missing
    for (String refObj : missingRefs.keySet()) {
      resolveReferences(refObj, missingRefs.get(refObj), idRemap, sourceSessionId, sourceInstanceUrl, destSessionId, destInstanceUrl);
    }

    // 4. Apply Updates
    List<Map<String, Object>> processed = new List<Map<String, Object>>();
    for (Map<String, Object> row : records) {
      // Clone row to avoid mutating original list structure if needed, but we typically just map to new structure
      Map<String, Object> newRec = new Map<String, Object>();
      String oldId = (String) row.get('Id');
      if (oldId != null) newRec.put('Id', oldId); // Keep ID for tracking

      for (String field : row.keySet()) {
         if (field == 'Id' || field == 'attributes') continue;
         
         if (objectName == 'User') {
            String f = field.toLowerCase();
            if (f == 'userroleid' || f.contains('userlicense') || f == 'managerid') continue;
         }

         Object val = row.get(field);
         if (refFields.containsKey(field) && val instanceof String) {
            String parentObj = refFields.get(field);
            if (idRemap.containsKey(parentObj)) {
               Map<String, String> parentMap = idRemap.get(parentObj);
               if (parentMap.containsKey((String)val)) {
                  val = parentMap.get((String)val);
               }
            }
         }
         newRec.put(field, val);
      }
      processed.add(newRec);
    }
    return processed;
  }

  @TestVisible
  private static void resolveReferences(
    String refObj, 
    Set<String> missingSourceIds,
    Map<String, Map<String, String>> idRemap,
    String sourceSessionId, String sourceInstanceUrl,
    String destSessionId, String destInstanceUrl
  ) {
    if (missingSourceIds == null || missingSourceIds.isEmpty()) return;

    String matchField = (refObj == 'User') ? 'Email' : 'Name';

    // Query Source
    List<String> quotedIds = new List<String>();
    for (String id : missingSourceIds) quotedIds.add('\'' + String.escapeSingleQuotes(id) + '\'');

    String sourceSoql = 'SELECT Id, ' + matchField + ' FROM ' + refObj + ' WHERE Id IN (' + String.join(quotedIds, ',') + ')';
    ExternalOrgQueryService.QueryResultWrapper sourceRes = queryAny(sourceSessionId, sourceInstanceUrl, sourceSoql);
    
    if (sourceRes == null || sourceRes.rows == null || sourceRes.rows.isEmpty()) return;

    Map<String, String> valueToSourceId = new Map<String, String>();
    List<String> matchValues = new List<String>();
    for (Map<String, Object> r : sourceRes.rows) {
      Object val = r.get(matchField);
      String id = (String) r.get('Id');
      if (val != null) {
        String sVal = String.valueOf(val);
        valueToSourceId.put(sVal.toLowerCase(), id);
        matchValues.add('\'' + String.escapeSingleQuotes(sVal) + '\'');
      }
    }
    if (matchValues.isEmpty()) return;

    // Query Dest
    String destSoql = 'SELECT Id, ' + matchField + ' FROM ' + refObj + ' WHERE ' + matchField + ' IN (' + String.join(matchValues, ',') + ')';
    ExternalOrgQueryService.QueryResultWrapper destRes = queryAny(destSessionId, destInstanceUrl, destSoql);

    if (destRes == null || destRes.rows == null) return;

    if (!idRemap.containsKey(refObj)) idRemap.put(refObj, new Map<String, String>());
    Map<String, String> objMap = idRemap.get(refObj);

    for (Map<String, Object> r : destRes.rows) {
      Object val = r.get(matchField);
      String destId = (String) r.get('Id');
      if (val != null) {
        String sVal = String.valueOf(val);
        String key = sVal.toLowerCase();
        if (valueToSourceId.containsKey(key)) {
           objMap.put(valueToSourceId.get(key), destId);
        }
      }
    }
  }

  @TestVisible
  private static void resolveUserProfiles(
      List<Map<String, Object>> rows,
      Map<String, Map<String, String>> idRemap,
      String sourceSessionId, String sourceInstanceUrl,
      String destSessionId, String destInstanceUrl
  ) {
    Set<String> sourceProfileIds = new Set<String>();
    for (Map<String, Object> row : rows) {
      if (row.containsKey('ProfileId') && row.get('ProfileId') != null) {
        sourceProfileIds.add((String) row.get('ProfileId'));
      }
    }
    if (sourceProfileIds.isEmpty()) return;

    List<String> pidList = new List<String>();
    for (String pid : sourceProfileIds) pidList.add('\'' + String.escapeSingleQuotes(pid) + '\'');
    String sourceSoql = 'SELECT Id, Name FROM Profile WHERE Id IN (' + String.join(pidList, ',') + ')';
    
    ExternalOrgQueryService.QueryResultWrapper sourceRes = queryAny(sourceSessionId, sourceInstanceUrl, sourceSoql);
    if (sourceRes == null || sourceRes.rows == null || sourceRes.rows.isEmpty()) return;

    Map<String, String> nameToSourceId = new Map<String, String>();
    List<String> names = new List<String>();
    for (Map<String, Object> r : sourceRes.rows) {
       String name = (String) r.get('Name');
       String id = (String) r.get('Id');
       if (name != null) {
           nameToSourceId.put(name.toLowerCase(), id);
           names.add('\'' + String.escapeSingleQuotes(name) + '\'');
       }
    }

    String destSoql = 'SELECT Id, Name FROM Profile WHERE Name IN (' + String.join(names, ',') + ')';
    ExternalOrgQueryService.QueryResultWrapper destRes = queryAny(destSessionId, destInstanceUrl, destSoql);

    if (destRes == null || destRes.rows == null) return;

    if (!idRemap.containsKey('Profile')) idRemap.put('Profile', new Map<String, String>());
    Map<String, String> profileMap = idRemap.get('Profile');

    for (Map<String, Object> r : destRes.rows) {
       String name = (String) r.get('Name');
       String destId = (String) r.get('Id');
       if (name != null) {
          String key = name.toLowerCase();
          if (nameToSourceId.containsKey(key)) {
             profileMap.put(nameToSourceId.get(key), destId);
          }
       }
    }
  }

  private static ExternalOrgQueryService.QueryResultWrapper queryAny(String sessionId, String instanceUrl, String soql) {
    try {
        if (String.isNotBlank(sessionId) && String.isNotBlank(instanceUrl)) {
            return ExternalOrgQueryService.queryWithSession(sessionId, instanceUrl, soql);
        } else {
            return ExternalOrgQueryService.queryCurrent(soql);
        }
    } catch (Exception e) {
        System.debug('queryAny Error: ' + e.getMessage());
        return null;
    }
  }

  private static Map<String, String> getLocalReferenceFields(String objectName) {
      Map<String, String> refs = new Map<String, String>();
      try {
          Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName);
          if (t != null) {
              Schema.DescribeSObjectResult d = t.getDescribe();
              for (Schema.SObjectField f : d.fields.getMap().values()) {
                  Schema.DescribeFieldResult fd = f.getDescribe();
                  if (fd.getType() == Schema.DisplayType.REFERENCE) {
                      List<Schema.SObjectType> rTo = fd.getReferenceTo();
                      if (rTo != null && !rTo.isEmpty()) {
                          refs.put(fd.getName(), rTo[0].getDescribe().getName());
                      }
                  }
              }
          }
      } catch (Exception e) {
          System.debug('Error getting local refs: ' + e.getMessage());
      }
      return refs;
  }
}
