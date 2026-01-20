Schema.DescribeSObjectResult d = dbt__Timesheet_Line_Item__c.SObjectType.getDescribe();
Map<String, Schema.SObjectField> fields = d.fields.getMap();
System.debug('Fields on dbt__Timesheet_Line_Item__c: ' + fields.keySet());
