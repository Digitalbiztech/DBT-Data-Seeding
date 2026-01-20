// Existing IDs
String projId = 'a05WG00000Un6HXYAZ';
String empId = 'a01WG00000zPPEzYAO';
String tsId = 'a07WG0000VKsE7RYQV';

// Custom Objects (dbt__)
try {
    // 1. Update Project to be Active (to satisfy Lookup Filter)
    Map<String, Object> projUpdate = new Map<String, Object>();
    projUpdate.put('Id', projId);
    projUpdate.put('dbt__Active__c', true); // Assumption: Boolean Checkbox

    List<Map<String, Object>> projUpdateList = new List<Map<String, Object>>{projUpdate};
    System.debug('Updating dbt__Project__c to Active...');
    List<ExternalOrgDmlService.InsertMapping> projRes = ExternalOrgQueryController.updateRecordsCurrent('dbt__Project__c', projUpdateList);
    System.debug('Project Update Result: ' + projRes);

    if (projRes[0].success) {
        // 2. Insert Line Item
        Map<String, Object> tsl = new Map<String, Object>();
        tsl.put('dbt__Timesheet__c', tsId);
        tsl.put('Id', 'a06000000000001AAA');
        tsl.put('dbt__Date__c', String.valueOf(Date.today()));
        tsl.put('dbt__Duration__c', 8.0); 
        tsl.put('dbt__Description__c', 'Test Work');
        tsl.put('dbt__Billable__c', 'Yes');
        tsl.put('dbt__Project__c', projId); 
        tsl.put('dbt__Activity__c', 'Development-Coding');

        List<Map<String, Object>> tslList = new List<Map<String, Object>>{tsl};
        System.debug('Inserting dbt__Timesheet_Line_Item__c...');
        List<ExternalOrgDmlService.InsertMapping> tslRes = ExternalOrgQueryController.insertRecordsCurrent('dbt__Timesheet_Line_Item__c', tslList);
        System.debug('Timesheet Line Item Result: ' + tslRes);
    }
} catch (Exception e) {
    System.debug('Custom Object Import Error: ' + e.getMessage());
    System.debug('Stack: ' + e.getStackTraceString());
}