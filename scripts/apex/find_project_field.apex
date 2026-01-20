Map<String, Schema.SObjectField> tsFields = dbt__Timesheet__c.SObjectType.getDescribe().fields.getMap();
for(String s : tsFields.keySet()) { 
    if(s.contains('project')) System.debug('Timesheet Field: ' + s); 
}

Map<String, Schema.SObjectField> tslFields = dbt__Timesheet_Line_Item__c.SObjectType.getDescribe().fields.getMap();
for(String s : tslFields.keySet()) { 
    if(s.contains('project')) System.debug('LineItem Field: ' + s); 
}
