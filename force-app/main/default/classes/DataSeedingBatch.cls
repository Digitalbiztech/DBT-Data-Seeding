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
          res = ExternalOrgQueryService.queryCurrent(soql);
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
        Object val = row.get(field);

        // Remap if it is a reference field
        if (refFields.containsKey(field)) {
          String parentObj = refFields.get(field);
          if (this.idRemap.containsKey(parentObj)) {
            Map<String, String> parentMap = this.idRemap.get(parentObj);
            if (val instanceof String && parentMap.containsKey((String) val)) {
              val = parentMap.get((String) val);
            }
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
}
