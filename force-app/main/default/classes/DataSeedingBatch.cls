public class DataSeedingBatch implements Database.Batchable<Map<String, Object>>, Database.Stateful, Database.AllowsCallouts {
    
    // Configuration
    private String sourceSessionId;
    private String sourceInstanceUrl;
    private String destSessionId;
    private String destInstanceUrl;
    
    // The Plan: List of query definitions map: { "objectName": "...", "soql": "...", "fields": [...] }
    private List<Map<String, Object>> taskList;
    
    // State: Maps old Id -> new Id. Key: ObjectName, Value: Map<OldId, NewId>
    // Note: We flatten this to Map<String, String> "ObjectName|OldId" -> "NewId" if needed, 
    // but Map<String, Map<String, String>> is clearer.
    private Map<String, Map<String, String>> idRemap;
    
    // Metadata cache for reference fields: ObjectName -> Map<FieldName, ReferenceToObjectName>
    private Map<String, Map<String, String>> referenceFieldCache;

    public class BatchError {
        @AuraEnabled public String objectName;
        @AuraEnabled public String recordId;
        @AuraEnabled public String message;
        @AuraEnabled public String stackTrace;
    }

    // State: List of errors encountered
    private List<BatchError> errors;

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
        this.errors = new List<BatchError>();
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
                logError(objName, null, e.getMessage(), e.getStackTraceString());
            }
        }
    }

    private void logError(String obj, String recId, String msg, String stack) {
        if (this.errors.size() < 200) {
            BatchError err = new BatchError();
            err.objectName = obj;
            err.recordId = recId;
            err.message = msg;
            err.stackTrace = stack;
            this.errors.add(err);
        }
        System.debug('DataSeeding Error [' + obj + ']: ' + msg);
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

        // 2. Remap Relationships
        List<Map<String, Object>> recordsToInsert = new List<Map<String, Object>>();
        Map<String, String> refFields = this.referenceFieldCache.containsKey(objectName) 
            ? this.referenceFieldCache.get(objectName) 
            : new Map<String, String>();
        
        System.debug('Reference fields for ' + objectName + ': ' + refFields);

        for (Map<String, Object> row : rows) {
            String oldId = (String) row.get('Id');
            if (oldId == null) continue;

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
                            Object newVal = parentMap.get((String)val);
                            System.debug('Remapping ' + field + ' from ' + val + ' to ' + newVal);
                            val = newVal;
                        } else {
                             // If we can't find the parent, and it's required? 
                             // For now we keep the old ID, which will likely fail reference check in dest,
                             // or we could null it out.
                             // Leaving as is allows for "external ID" references if they happen to match, 
                             // but usually it fails.
                        }
                    }
                }
                newRec.put(field, val);
            }
            newRec.put('Id', oldId); // Pass oldId for tracking (will be removed before insert by controller if needed)
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

        // 4. Update ID Map and capture row-level errors
        if (!this.idRemap.containsKey(objectName)) {
            this.idRemap.put(objectName, new Map<String, String>());
        }
        Map<String, String> objectMap = this.idRemap.get(objectName);
        
        Integer successCount = 0;
        Integer errorCount = 0;

        for (ExternalOrgQueryController.InsertMapping res : results) {
            if (res.success && res.oldId != null && res.newId != null) {
                objectMap.put(res.oldId, res.newId);
                successCount++;
            } else if (!res.success) {
                logError(objectName, res.oldId, res.errorMessage, null);
                errorCount++;
            }
        }
        System.debug('Batch result for ' + objectName + ': ' + successCount + ' successes, ' + errorCount + ' errors.');
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
        if (!this.errors.isEmpty()) {
            System.debug('Errors encountered: ' + this.errors.size());
            for(BatchError e : this.errors) {
                System.debug('Err: ' + e.objectName + ' ' + e.recordId + ' ' + e.message);
            }
        }
    }
}
