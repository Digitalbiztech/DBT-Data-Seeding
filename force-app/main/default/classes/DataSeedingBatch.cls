public class DataSeedingBatch implements Database.Batchable<Integer>, Database.Stateful, Database.AllowsCallouts {
  // Configuration
  private String sourceSessionId;
  private String sourceInstanceUrl;
  private String destSessionId;
  private String destInstanceUrl;

  // The Plan
  private List<Map<String, Object>> taskList;

  // State
  private Integer currentTaskIndex = 0;
  private String currentNextRecordsUrl = null;
  private String chainHeadJobId = null;

  // Maps old Id -> new Id. Key: ObjectName, Value: Map<OldId, NewId>
  private Map<String, Map<String, String>> idRemap;

  // Metadata cache for reference fields: ObjectName -> Map<FieldName, ReferenceToObjectName>
  private Map<String, Map<String, String>> referenceFieldCache;

  public class LogEntry {
    public String objectName;
    public String sourceId;
    public String destId;
    public String name;
    public String status; // 'Success' or 'Error'
    public String message;
    public String recordUrl;
    public String sourceUrl;
    public String rawError;
  }

  // State: List of all logs
  private List<LogEntry> logs;
  private Integer successLogCount = 0;
  private static final Integer MAX_SUCCESS_LOGS = 1000;

  public DataSeedingBatch(
    String sourceSessionId,
    String sourceInstanceUrl,
    String destSessionId,
    String destInstanceUrl,
    List<Map<String, Object>> tasks,
    Map<String, Map<String, String>> planEdges,
    String chainHeadJobId
  ) {
    this.sourceSessionId = sourceSessionId;
    this.sourceInstanceUrl = sourceInstanceUrl;
    this.destSessionId = destSessionId;
    this.destInstanceUrl = destInstanceUrl;
    this.taskList = tasks;
    this.idRemap = new Map<String, Map<String, String>>();
    this.referenceFieldCache = planEdges;
    this.logs = new List<LogEntry>();
    this.successLogCount = 0;
    this.currentTaskIndex = 0;
    this.currentNextRecordsUrl = null;
    this.chainHeadJobId = chainHeadJobId;
  }

  // Return a dummy list of size 1 to ensure execute runs exactly once per job submission
  public Iterable<Integer> start(Database.BatchableContext bc) {
    if (String.isBlank(this.chainHeadJobId)) {
      this.chainHeadJobId = bc.getJobId();
    }
    System.debug(
      'DataSeedingBatch start. Task Index: ' +
        currentTaskIndex +
        ' NextUrl: ' +
        currentNextRecordsUrl +
        ' ChainHead: ' +
        chainHeadJobId
    );
    return new List<Integer>{ 1 };
  }

  public void execute(Database.BatchableContext bc, List<Integer> scope) {
    try {
      if (
        this.taskList == null ||
        this.currentTaskIndex >= this.taskList.size()
      ) {
        System.debug('No more tasks to process.');
        return;
      }

      Map<String, Object> task = this.taskList[this.currentTaskIndex];
      processCurrentTaskBatch(task);
    } catch (Exception e) {
      System.debug(
        'Critical Error in Batch Execution: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
      LogEntry err = new LogEntry();
      err.status = 'Error';
      err.message = 'Critical Batch Error: ' + e.getMessage();
      this.logs.add(err);
    }
  }

  private void processCurrentTaskBatch(Map<String, Object> task) {
    String objectName = (String) task.get('objectName');
    String soql = (String) task.get('soql');

    // Extract fields to ensure we retrieve null values from local queries
    List<Object> fieldsObj = (List<Object>) task.get('fields');
    List<String> queryFields = new List<String>();
    if (fieldsObj != null) {
      for (Object o : fieldsObj)
        queryFields.add((String) o);
    }

    System.debug(
      'Processing ' +
        objectName +
        (String.isNotBlank(this.currentNextRecordsUrl)
          ? ' (Continuation)'
          : ' (Start)')
    );

    // 1. Fetch Records (Page)
    ExternalOrgQueryService.QueryResultWrapper res;
    try {
      if (String.isNotBlank(this.currentNextRecordsUrl)) {
        if (
          String.isNotBlank(sourceSessionId) &&
          String.isNotBlank(sourceInstanceUrl)
        ) {
          res = ExternalOrgQueryService.queryByUrl(
            sourceSessionId,
            sourceInstanceUrl,
            this.currentNextRecordsUrl
          );
        } else {
          throw new CalloutException(
            'Pagination for local query not supported yet via URL.'
          );
        }
      } else {
        if (
          String.isNotBlank(sourceSessionId) &&
          String.isNotBlank(sourceInstanceUrl)
        ) {
          res = ExternalOrgQueryService.queryWithSession(
            sourceSessionId,
            sourceInstanceUrl,
            soql
          );
        } else {
          res = ExternalOrgQueryService.queryCurrent(soql, queryFields);
        }
      }
    } catch (Exception e) {
      // If query fails, we can't proceed with this object.
      System.debug('Query failed for ' + objectName + ': ' + e.getMessage());
      throw e;
    }

    // Update State for Pagination
    if (res != null) {
      this.currentNextRecordsUrl = res.nextRecordsUrl; // Can be null if done
      // If local query, done is true.
    } else {
      this.currentNextRecordsUrl = null;
    }

    List<Map<String, Object>> rows = (res != null &&
      res.rows != null)
      ? res.rows
      : new List<Map<String, Object>>();
    System.debug('Fetched ' + rows.size() + ' records.');

    if (rows.isEmpty()) {
      return;
    }

    // 2. Remap & Prepare
    List<Map<String, Object>> recordsToInsert = new List<Map<String, Object>>();
    Map<String, String> refFields = this.referenceFieldCache.containsKey(
        objectName
      )
      ? this.referenceFieldCache.get(objectName)
      : new Map<String, String>();

    if (objectName == 'User') {
      resolveUserProfiles(rows);
      if (!refFields.containsKey('ProfileId')) {
        refFields.put('ProfileId', 'Profile');
      }
    }

    // Pre-scan for missing references and attempt to resolve them
    Map<String, Set<String>> missingRefs = new Map<String, Set<String>>();
    for (Map<String, Object> row : rows) {
      for (String field : refFields.keySet()) {
        Object val = row.get(field);
        if (val != null && val instanceof String) {
          String sVal = (String) val;
          String parentObj = refFields.get(field);
          // Check if we already have a mapping
          Boolean hasMapping =
            this.idRemap.containsKey(parentObj) &&
            this.idRemap.get(parentObj).containsKey(sVal);

          if (!hasMapping) {
            if (!missingRefs.containsKey(parentObj)) {
              missingRefs.put(parentObj, new Set<String>());
            }
            missingRefs.get(parentObj).add(sVal);
          }
        }
      }
    }

    // Resolve missing references
    for (String refObj : missingRefs.keySet()) {
      resolveReferences(refObj, missingRefs.get(refObj));
    }

    List<Map<String, Object>> originalRows = new List<Map<String, Object>>();

    for (Map<String, Object> row : rows) {
      String oldId = (String) row.get('Id');
      if (oldId == null)
        continue;

      originalRows.add(row);

      Map<String, Object> newRec = new Map<String, Object>();
      for (String field : row.keySet()) {
        if (field == 'Id' || field == 'attributes')
          continue;

        // Skip specific fields for User object as requested
        if (objectName == 'User') {
          String f = field.toLowerCase();
          if (
            f == 'userroleid' ||
            f.contains('userlicense') ||
            f == 'managerid'
          ) {
            continue;
          }
        }

        Object val = row.get(field);

        // Remap if it is a reference field
        if (refFields.containsKey(field)) {
          String parentObj = refFields.get(field);
          if (this.idRemap.containsKey(parentObj)) {
            Map<String, String> parentMap = this.idRemap.get(parentObj);
            if (val instanceof String && parentMap.containsKey((String) val)) {
              val = parentMap.get((String) val);
            } else if (val instanceof String) {
              // WARN: Reference ID not found in map and not resolved
              System.debug(
                'WARNING: Unresolved Source ID for field ' +
                  field +
                  ': ' +
                  val +
                  ' (Target: ' +
                  parentObj +
                  ')'
              );
            }
          } else if (val instanceof String) {
            System.debug(
              'WARNING: No mappings found for object ' +
                parentObj +
                '. Field ' +
                field +
                ' with value ' +
                val +
                ' remains unresolved.'
            );
          }
        }
        newRec.put(field, val);
      }
      newRec.put('Id', oldId);
      recordsToInsert.add(newRec);
    }

    // 3. Insert/Create in Destination
    List<ExternalOrgDmlService.InsertMapping> results;
    try {
      if (
        String.isNotBlank(destSessionId) && String.isNotBlank(destInstanceUrl)
      ) {
        results = ExternalOrgDmlService.createRecordsRemote(
          destSessionId,
          destInstanceUrl,
          objectName,
          recordsToInsert
        );
      } else {
        results = ExternalOrgDmlService.insertRecordsCurrent(
          objectName,
          recordsToInsert
        );
      }
    } catch (Exception e) {
      throw new AuraHandledException(
        'Destination write failed for ' + objectName + ': ' + e.getMessage()
      );
    }

    // 4. Update ID Map and Logs
    if (!this.idRemap.containsKey(objectName)) {
      this.idRemap.put(objectName, new Map<String, String>());
    }
    Map<String, String> objectMap = this.idRemap.get(objectName);

    String baseUrl = String.isNotBlank(destInstanceUrl)
      ? destInstanceUrl
      : URL.getOrgDomainUrl().toExternalForm();
    String srcBaseUrl = String.isNotBlank(sourceInstanceUrl)
      ? sourceInstanceUrl
      : URL.getOrgDomainUrl().toExternalForm();

    for (Integer i = 0; i < results.size(); i++) {
      ExternalOrgDmlService.InsertMapping mapping = results[i];
      Map<String, Object> original = originalRows[i];

      LogEntry entry = new LogEntry();
      entry.objectName = objectName;
      entry.sourceId = mapping.oldId;
      entry.name = (original.containsKey('Name'))
        ? String.valueOf(original.get('Name'))
        : mapping.oldId;
      entry.sourceUrl = srcBaseUrl + '/' + mapping.oldId;

      if (mapping.success && mapping.newId != null) {
        objectMap.put(mapping.oldId, mapping.newId);

        if (this.successLogCount < MAX_SUCCESS_LOGS) {
          entry.destId = mapping.newId;
          entry.status = 'Success';
          entry.recordUrl = baseUrl + '/' + mapping.newId;
          this.logs.add(entry);
          this.successLogCount++;
        }
      } else {
        entry.status = 'Error';
        entry.message = mapping.errorMessage;
        entry.rawError = mapping.rawError;
        this.logs.add(entry);
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('DataSeedingBatch Step Finished.');

    // Logic to chain
    Boolean chain = false;

    if (String.isNotBlank(this.currentNextRecordsUrl)) {
      // More pages for current object
      chain = true;
      System.debug(
        'Chaining for next page of ' +
        this.taskList[this.currentTaskIndex].get('objectName')
      );
    } else {
      // Current object done, move to next
      this.currentTaskIndex++;
      this.currentNextRecordsUrl = null; // Reset for next object
      if (
        this.taskList != null &&
        this.currentTaskIndex < this.taskList.size()
      ) {
        chain = true;
        System.debug(
          'Chaining for next object: ' +
          this.taskList[this.currentTaskIndex].get('objectName')
        );
      }
    }

    if (chain) {
      if (!Test.isRunningTest()) {
        Database.executeBatch(this, 1);
      }
    } else {
      // All done
      saveReport(
        String.isNotBlank(this.chainHeadJobId)
          ? this.chainHeadJobId
          : bc.getJobId()
      );
    }
  }

  private void saveReport(String jobId) {
    System.debug('All Tasks Completed. Saving Report.');
    System.debug('Total logs: ' + (this.logs != null ? this.logs.size() : 0));

    try {
      ContentVersion cv = new ContentVersion();
      cv.Title = 'SeedingReport_' + jobId;
      cv.PathOnClient = 'SeedingReport.json';
      String jsonBody = JSON.serialize(this.logs);
      cv.VersionData = Blob.valueOf(jsonBody);
      cv.IsMajorVersion = true;
      insert cv;
      System.debug('Saved execution report: ' + cv.Id);
    } catch (Exception e) {
      System.debug('Failed to save batch report: ' + e.getMessage());
    }
  }

  private void resolveUserProfiles(List<Map<String, Object>> rows) {
    Set<String> sourceProfileIds = new Set<String>();
    for (Map<String, Object> row : rows) {
      if (
        row != null &&
        row.containsKey('ProfileId') &&
        row.get('ProfileId') != null
      ) {
        sourceProfileIds.add((String) row.get('ProfileId'));
      }
    }
    if (sourceProfileIds.isEmpty())
      return;

    if (!idRemap.containsKey('Profile')) {
      idRemap.put('Profile', new Map<String, String>());
    }
    Map<String, String> profileMap = idRemap.get('Profile');

    Set<String> toResolve = new Set<String>();
    for (String pid : sourceProfileIds) {
      if (!profileMap.containsKey(pid)) {
        toResolve.add(pid);
      }
    }
    if (toResolve.isEmpty())
      return;

    List<String> pidList = new List<String>();
    for (String pid : toResolve) {
      pidList.add('\'' + String.escapeSingleQuotes(pid) + '\'');
    }
    String sourceSoql =
      'SELECT Id, Name FROM Profile WHERE Id IN (' +
      String.join(pidList, ',') +
      ')';

    ExternalOrgQueryService.QueryResultWrapper sourceRes;
    try {
      if (
        String.isNotBlank(sourceSessionId) &&
        String.isNotBlank(sourceInstanceUrl)
      ) {
        sourceRes = ExternalOrgQueryService.queryWithSession(
          sourceSessionId,
          sourceInstanceUrl,
          sourceSoql
        );
      } else {
        sourceRes = ExternalOrgQueryService.queryCurrent(sourceSoql);
      }
    } catch (Exception e) {
      System.debug('Error querying source profiles: ' + e.getMessage());
      return;
    }

    if (sourceRes == null || sourceRes.rows == null || sourceRes.rows.isEmpty())
      return;

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

    String destSoql =
      'SELECT Id, Name FROM Profile WHERE Name IN (' +
      String.join(names, ',') +
      ')';

    ExternalOrgQueryService.QueryResultWrapper destRes;
    try {
      if (
        String.isNotBlank(destSessionId) && String.isNotBlank(destInstanceUrl)
      ) {
        destRes = ExternalOrgQueryService.queryWithSession(
          destSessionId,
          destInstanceUrl,
          destSoql
        );
      } else {
        destRes = ExternalOrgQueryService.queryCurrent(destSoql);
      }
    } catch (Exception e) {
      System.debug('Error querying dest profiles: ' + e.getMessage());
      return;
    }

    if (destRes == null || destRes.rows == null)
      return;

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

  private void resolveReferences(String refObj, Set<String> missingSourceIds) {
    if (missingSourceIds == null || missingSourceIds.isEmpty())
      return;

    String matchField = (refObj == 'User') ? 'Email' : 'Name';

    // 1. Query Source for Match Values
    List<String> quotedIds = new List<String>();
    for (String id : missingSourceIds) {
      quotedIds.add('\'' + String.escapeSingleQuotes(id) + '\'');
    }

    String sourceSoql =
      'SELECT Id, ' +
      matchField +
      ' FROM ' +
      refObj +
      ' WHERE Id IN (' +
      String.join(quotedIds, ',') +
      ')';

    ExternalOrgQueryService.QueryResultWrapper sourceRes;
    try {
      if (
        String.isNotBlank(sourceSessionId) &&
        String.isNotBlank(sourceInstanceUrl)
      ) {
        sourceRes = ExternalOrgQueryService.queryWithSession(
          sourceSessionId,
          sourceInstanceUrl,
          sourceSoql
        );
      } else {
        sourceRes = ExternalOrgQueryService.queryCurrent(sourceSoql);
      }
    } catch (Exception e) {
      System.debug(
        'resolveReferences: Error querying source ' +
          refObj +
          ': ' +
          e.getMessage()
      );
      return;
    }

    if (sourceRes == null || sourceRes.rows == null || sourceRes.rows.isEmpty())
      return;

    Map<String, String> valueToSourceId = new Map<String, String>();
    List<String> matchValues = new List<String>();

    for (Map<String, Object> r : sourceRes.rows) {
      Object val = r.get(matchField);
      String id = (String) r.get('Id');
      if (val != null) {
        String sVal = String.valueOf(val);
        // Use lowercase key for case-insensitive matching
        valueToSourceId.put(sVal.toLowerCase(), id);
        matchValues.add('\'' + String.escapeSingleQuotes(sVal) + '\'');
      }
    }

    if (matchValues.isEmpty())
      return;
    
    System.debug('resolveReferences: Looking for ' + matchValues.size() + ' values in ' + refObj);

    // 2. Query Destination for Ids matching Match Values
    String destSoql =
      'SELECT Id, ' +
      matchField +
      ' FROM ' +
      refObj +
      ' WHERE ' +
      matchField +
      ' IN (' +
      String.join(matchValues, ',') +
      ')';

    ExternalOrgQueryService.QueryResultWrapper destRes;
    try {
      if (
        String.isNotBlank(destSessionId) && String.isNotBlank(destInstanceUrl)
      ) {
        destRes = ExternalOrgQueryService.queryWithSession(
          destSessionId,
          destInstanceUrl,
          destSoql
        );
      } else {
        destRes = ExternalOrgQueryService.queryCurrent(destSoql);
      }
    } catch (Exception e) {
      System.debug(
        'resolveReferences: Error querying dest ' +
          refObj +
          ': ' +
          e.getMessage()
      );
      return;
    }

    if (destRes == null || destRes.rows == null)
      return;
      
    System.debug('resolveReferences: Found ' + destRes.rows.size() + ' potential matches in destination.');

    // 3. Update idRemap
    if (!this.idRemap.containsKey(refObj)) {
      this.idRemap.put(refObj, new Map<String, String>());
    }
    Map<String, String> objMap = this.idRemap.get(refObj);

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
}
