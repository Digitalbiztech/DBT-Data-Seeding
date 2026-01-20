Schema.DescribeFieldResult f = dbt__Timesheet_Line_Item__c.dbt__Activity__c.getDescribe();
System.debug('dbt__Activity__c Type: ' + f.getType());
if(f.getType() == Schema.DisplayType.REFERENCE) {
    System.debug('Reference To: ' + f.getReferenceTo());
} else if (f.getType() == Schema.DisplayType.PICKLIST) {
    List<Schema.PicklistEntry> ples = f.getPicklistValues();
    for(Schema.PicklistEntry p : ples) {
        System.debug('Picklist Value: ' + p.getValue());
    }
}
