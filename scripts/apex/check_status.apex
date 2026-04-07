Schema.DescribeFieldResult fieldResult = dbt__Timesheet__c.dbt__Status__c.getDescribe();
for (Schema.PicklistEntry ple : fieldResult.getPicklistValues()) {
    System.debug('VALUE: ' + ple.getValue());
}
