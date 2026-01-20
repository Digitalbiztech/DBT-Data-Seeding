Schema.DescribeSObjectResult d = dbt__Timesheet__c.SObjectType.getDescribe();
Map<String, Schema.SObjectField> fields = d.fields.getMap();
System.debug('Fields on dbt__Timesheet__c: ' + fields.keySet());
