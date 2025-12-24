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
        return this.taskList;
    }

    public void execute(Database.BatchableContext bc, List<Map<String, Object>> scope) {
        for (Map<String, Object> task : scope) {
            try {
                processTask(task);
            } catch (Exception e) {
                logError((String)task.get('objectName'), null, e.getMessage(), e.getStackTraceString());
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
        
        // 1. Query Source
        List<Map<String, Object>> rows;
        try {
            rows = fetchSourceRecords(soql);
        } catch (Exception e) {
            throw new AuraHandledException('Source query failed for ' + objectName + ': ' + e.getMessage());
        }
        
        if (rows.isEmpty()) return;

        // 2. Remap Relationships
        List<Map<String, Object>> recordsToInsert = new List<Map<String, Object>>();
        Map<String, String> refFields = this.referenceFieldCache.containsKey(objectName) 
            ? this.referenceFieldCache.get(objectName) 
            : new Map<String, String>();

        for (Map<String, Object> row : rows) {
            String oldId = (String) row.get('Id');
            if (oldId == null) continue;

            Map<String, Object> newRec = new Map<String, Object>();
            for (String field : row.keySet()) {
                if (field == 'Id' || field == 'attributes') continue;
                Object val = row.get(field);
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
            newRec.put('Id', oldId); 
            recordsToInsert.add(newRec);
        }

        // 3. Insert/Create in Destination
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

        for (ExternalOrgQueryController.InsertMapping res : results) {
            if (res.success && res.oldId != null && res.newId != null) {
                objectMap.put(res.oldId, res.newId);
            } else if (!res.success) {
                logError(objectName, res.oldId, res.errorMessage, null);
            }
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
        // Could send an email or notification
    }
}
