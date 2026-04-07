Schema.DescribeFieldResult f = dbt__Project__c.dbt__Active__c.getDescribe();
System.debug('Type: ' + f.getType());
if(f.getType() == Schema.DisplayType.Picklist) {
    for(Schema.PicklistEntry ple : f.getPicklistValues()) {
        System.debug('VALUE: ' + ple.getValue());
    }
}
