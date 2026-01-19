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
}
