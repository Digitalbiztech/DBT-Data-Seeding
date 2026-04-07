Schema.DescribeFieldResult f = dbt__Project__c.dbt__Billable__c.getDescribe();
for (Schema.PicklistEntry ple : f.getPicklistValues()) {
    System.debug('VALUE: ' + ple.getValue());
}
