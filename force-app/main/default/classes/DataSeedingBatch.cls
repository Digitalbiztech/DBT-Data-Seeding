public class DataSeedingBatch implements Database.Batchable<Map<String, Object>>, Database.Stateful, Database.AllowsCallouts {
    
    // Configuration
    private String sourceSessionId;
    private String sourceInstanceUrl;
    private String destSessionId;
    private String destInstanceUrl;
    
    // The Plan: List of query definitions map: { "objectName": "...", "soql": "...", "fields": [...] }
    private List<Map<String, Object>> taskList;
    
    // State: Maps old Id -> new Id. Key: ObjectName, Value: Map<OldId, NewId>
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
    }

    // State: List of all logs (success and error)
    private List<LogEntry> logs;

    public DataSeedingBatch(
        String sourceSessionId, 
        String sourceInstanceUrl, 
        String destSessionId, 
        String destInstanceUrl,
        List<Map<String, Object>> tasks,
        Map<String, Map<String, String>> planEdges // To know relationships
    ) {
        this.sourceSessionId = sourceSessionId;
        this.sourceInstanceUrl = sourceInstanceUrl;
        this.destSessionId = destSessionId;
        this.destInstanceUrl = destInstanceUrl;
        this.taskList = tasks;
        this.idRemap = new Map<String, Map<String, String>>();
        this.referenceFieldCache = planEdges;
        this.logs = new List<LogEntry>();
    }

    public Iterable<Map<String, Object>> start(Database.BatchableContext bc) {
        System.debug('DataSeedingBatch start. Tasks: ' + (this.taskList != null ? this.taskList.size() : 0));
        return this.taskList;
    }

    public void execute(Database.BatchableContext bc, List<Map<String, Object>> scope) {
        System.debug('DataSeedingBatch execute started. Scope size: ' + scope.size());
        for (Map<String, Object> task : scope) {
            String objName = (String)task.get('objectName');
            System.debug('Processing task for object: ' + objName);
            try {
                processTask(task);
            } catch (Exception e) {
                System.debug('Error processing task ' + objName + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
                LogEntry err = new LogEntry();
                err.objectName = objName;
                err.status = 'Error';
                err.message = e.getMessage();
                this.logs.add(err);
            }
        }
    }

    private void processTask(Map<String, Object> task) {
        String objectName = (String) task.get('objectName');
        String soql = (String) task.get('soql');
        
        System.debug('processTask: ' + objectName + ' SOQL: ' + soql);

        // 1. Query Source
        List<Map<String, Object>> rows;
        try {
            rows = fetchSourceRecords(soql);
            System.debug('Fetched ' + (rows != null ? rows.size() : 0) + ' source records for ' + objectName);
        } catch (Exception e) {
            throw new AuraHandledException('Source query failed for ' + objectName + ': ' + e.getMessage());
        }
        
        if (rows == null || rows.isEmpty()) {
            System.debug('No records to process for ' + objectName);
            return;
        }

        // 2. Remap Relationships & Prepare Insert
        List<Map<String, Object>> recordsToInsert = new List<Map<String, Object>>();
        Map<String, String> refFields = this.referenceFieldCache.containsKey(objectName) 
            ? this.referenceFieldCache.get(objectName) 
            : new Map<String, String>();
        
        // Helper map to lookup original row data by index for logging
        List<Map<String, Object>> originalRows = new List<Map<String, Object>>();

        for (Map<String, Object> row : rows) {
            String oldId = (String) row.get('Id');
            if (oldId == null) continue;
            
            originalRows.add(row);

            Map<String, Object> newRec = new Map<String, Object>();
            for (String field : row.keySet()) {
                if (field == 'Id' || field == 'attributes') continue;
                Object val = row.get(field);
                
                // Remap if it is a reference field
                if (refFields.containsKey(field)) {
                    String parentObj = refFields.get(field);
                    if (this.idRemap.containsKey(parentObj)) {
                        Map<String, String> parentMap = this.idRemap.get(parentObj);
                        if (val instanceof String && parentMap.containsKey((String)val)) {
                            val = parentMap.get((String)val);
                        }
                    }
                }
                newRec.put(field, val);
            }
            newRec.put('Id', oldId); // Pass oldId for tracking
            recordsToInsert.add(newRec);
        }

        // 3. Insert/Create in Destination
        System.debug('Inserting ' + recordsToInsert.size() + ' records into destination.');
        List<ExternalOrgQueryController.InsertMapping> results;
        try {
            if (String.isNotBlank(destSessionId) && String.isNotBlank(destInstanceUrl)) {
                results = ExternalOrgQueryController.createRecordsRemote(destSessionId, destInstanceUrl, objectName, recordsToInsert);
            } else {
                results = ExternalOrgQueryController.insertRecordsCurrent(objectName, recordsToInsert);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Destination write failed for ' + objectName + ': ' + e.getMessage());
        }

        // 4. Update ID Map and Capture Logs
        if (!this.idRemap.containsKey(objectName)) {
            this.idRemap.put(objectName, new Map<String, String>());
        }
        Map<String, String> objectMap = this.idRemap.get(objectName);
        
        String baseUrl = String.isNotBlank(destInstanceUrl) ? destInstanceUrl : URL.getOrgDomainUrl().toExternalForm();

        for (Integer i = 0; i < results.size(); i++) {
            ExternalOrgQueryController.InsertMapping res = results[i];
            Map<String, Object> original = originalRows[i];
            
            LogEntry entry = new LogEntry();
            entry.objectName = objectName;
            entry.sourceId = res.oldId;
            entry.name = (original.containsKey('Name')) ? String.valueOf(original.get('Name')) : res.oldId;
            
            if (res.success && res.newId != null) {
                entry.destId = res.newId;
                entry.status = 'Success';
                entry.recordUrl = baseUrl + '/' + res.newId;
                objectMap.put(res.oldId, res.newId);
            } else {
                entry.status = 'Error';
                entry.message = res.errorMessage;
            }
            this.logs.add(entry);
        }
    }

    private List<Map<String, Object>> fetchSourceRecords(String soql) {
        ExternalOrgQueryController.QueryResultWrapper res;
        if (String.isNotBlank(sourceSessionId) && String.isNotBlank(sourceInstanceUrl)) {
            res = ExternalOrgQueryController.queryWithSession(sourceSessionId, sourceInstanceUrl, soql);
        } else {
            res = ExternalOrgQueryController.queryCurrent(soql);
        }
        return (res != null && res.rows != null) ? res.rows : new List<Map<String, Object>>();
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Data Seeding Batch Completed.');
        
        try {
            // Save logs to a ContentVersion file for retrieval by UI
            ContentVersion cv = new ContentVersion();
            cv.Title = 'SeedingReport_' + bc.getJobId();
            cv.PathOnClient = 'SeedingReport.json';
            cv.VersionData = Blob.valueOf(JSON.serialize(this.logs));
            cv.IsMajorVersion = true;
            insert cv;
            System.debug('Saved execution report: ' + cv.Id);
        } catch (Exception e) {
            System.debug('Failed to save batch report: ' + e.getMessage());
        }
    }
}
