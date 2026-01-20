Schema.DescribeSObjectResult d = dbt__Project__c.SObjectType.getDescribe();
Map<String, Schema.SObjectField> fields = d.fields.getMap();
System.debug('Fields on dbt__Project__c: ' + fields.keySet());
// Check for Status
if(fields.containsKey('dbt__status__c')) {
    Schema.DescribeFieldResult f = fields.get('dbt__status__c').getDescribe();
    List<Schema.PicklistEntry> ples = f.getPicklistValues();
    for(Schema.PicklistEntry p : ples) {
        System.debug('Project Status Value: ' + p.getValue());
    }
}
