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
        this.referenceFieldCache = planEdges; // Reuse the plan edges passed from UI as the schema map
    }

    public Iterable<Map<String, Object>> start(Database.BatchableContext bc) {
        // We iterate over the list of query tasks defined by the UI
        return this.taskList;
    }

    public void execute(Database.BatchableContext bc, List<Map<String, Object>> scope) {
        // Scope size should be small (e.g. 1 task) to manage callout limits and complexity
        for (Map<String, Object> task : scope) {
            processTask(task);
        }
    }

    private void processTask(Map<String, Object> task) {
        String objectName = (String) task.get('objectName');
        String soql = (String) task.get('soql');
        
        System.debug('Processing batch task for: ' + objectName);

        // 1. Query Source
        List<Map<String, Object>> rows = fetchSourceRecords(soql);
        if (rows.isEmpty()) return;

        // 2. Remap Relationships
        List<Map<String, Object>> recordsToInsert = new List<Map<String, Object>>();
        Map<String, String> nameByOldId = new Map<String, String>(); // For logging/tracking

        // Get reference map for this object (Field -> ParentObject)
        Map<String, String> refFields = this.referenceFieldCache.containsKey(objectName) 
            ? this.referenceFieldCache.get(objectName) 
            : new Map<String, String>();

        for (Map<String, Object> row : rows) {
            String oldId = (String) row.get('Id');
            if (oldId == null) continue;

            Map<String, Object> newRec = new Map<String, Object>();
            // newRec.put('attributes', new Map<String, String>{ 'type' => objectName }); // Handled by controller method if remote

            for (String field : row.keySet()) {
                if (field == 'Id' || field == 'attributes') continue;
                
                Object val = row.get(field);
                
                // Remap if it's a reference field we know about
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
            
            // Keep track of source Id for the mapping step
            newRec.put('Id', oldId); // We pass Source ID to the insert helper so it can return it in the result
            recordsToInsert.add(newRec);
        }

        // 3. Insert/Create in Destination
        List<ExternalOrgQueryController.InsertMapping> results;
        
        if (String.isNotBlank(destSessionId) && String.isNotBlank(destInstanceUrl)) {
            // Remote Destination
            // Note: createRecordsRemote handles removing the 'Id' field before sending to Salesforce REST API,
            // but uses it to map the result back.
            results = ExternalOrgQueryController.createRecordsRemote(destSessionId, destInstanceUrl, objectName, recordsToInsert);
        } else {
            // Local Destination
            results = ExternalOrgQueryController.insertRecordsCurrent(objectName, recordsToInsert);
        }

        // 4. Update ID Map
        if (!this.idRemap.containsKey(objectName)) {
            this.idRemap.put(objectName, new Map<String, String>());
        }
        Map<String, String> objectMap = this.idRemap.get(objectName);

        for (ExternalOrgQueryController.InsertMapping res : results) {
            if (res.success && res.oldId != null && res.newId != null) {
                objectMap.put(res.oldId, res.newId);
            } else {
                // Log error? For now, standard debug
                if (!res.success) System.debug('Batch Insert Error: ' + res.errorMessage);
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
